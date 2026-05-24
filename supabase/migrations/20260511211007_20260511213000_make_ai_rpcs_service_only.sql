-- Move AI credit balance/reservation RPCs to service-role-only calls.
-- Edge Functions authenticate the user from the request JWT, then call these RPCs
-- with the verified user id using the service role client. This keeps credit
-- mutation RPCs out of direct authenticated-client reach.

drop function if exists public.proofkit_get_ai_credit_balance();
drop function if exists public.proofkit_reserve_ai_credits(text, uuid, text);

create or replace function public.proofkit_get_ai_credit_balance(
  p_user_id uuid
)
returns table (
  available_credits integer,
  reserved_credits integer,
  included_monthly_credits integer,
  renews_at timestamptz,
  updated_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := p_user_id;
begin
  if v_user_id is null then
    raise exception 'proofkit_get_ai_credit_balance requires a user id';
  end if;

  return query
    select
      b.credits_remaining,
      b.credits_reserved,
      b.credits_granted,
      b.period_end,
      b.updated_at
    from public.ai_credit_balances b
    where b.user_id = v_user_id;

  if not found then
    return query select 0, 0, 0, null::timestamptz, now();
  end if;
end;
$$;

create or replace function public.proofkit_reserve_ai_credits(
  p_user_id uuid,
  p_feature text,
  p_case_id uuid default null,
  p_idempotency_key text default null
)
returns table (
  ledger_id uuid,
  credits_reserved integer,
  remaining_credits integer,
  expires_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := p_user_id;
  v_pricing public.ai_feature_pricing%rowtype;
  v_account public.subscription_accounts%rowtype;
  v_balance public.ai_credit_balances%rowtype;
  v_existing public.ai_usage_ledger%rowtype;
  v_ledger_id uuid;
  v_remaining integer;
  v_expires_at timestamptz := now() + interval '15 minutes';
  v_recent_count integer;
begin
  if v_user_id is null then
    raise exception 'proofkit_reserve_ai_credits requires a user id';
  end if;

  select * into v_pricing
  from public.ai_feature_pricing
  where feature = p_feature and enabled = true;

  if not found then
    raise exception 'ai_feature_disabled:%', p_feature;
  end if;

  select count(*) into v_recent_count
  from public.ai_usage_ledger
  where user_id = v_user_id
    and created_at > now() - interval '1 minute'
    and status in ('pending','succeeded');

  if v_recent_count >= 6 then
    raise exception 'ai_rate_limited';
  end if;

  if p_idempotency_key is not null then
    select * into v_existing
    from public.ai_usage_ledger
    where user_id = v_user_id
      and idempotency_key = p_idempotency_key
    order by created_at desc
    limit 1;

    if found then
      select * into v_balance
      from public.ai_credit_balances
      where user_id = v_user_id;

      return query select
        v_existing.id,
        v_existing.credits_reserved,
        coalesce(v_balance.credits_remaining, 0),
        v_existing.reservation_expires_at;
      return;
    end if;
  end if;

  select * into v_account
  from public.subscription_accounts
  where user_id = v_user_id
    and status in ('trialing','active_weekly','active_monthly')
    and coalesce(current_period_end, now() + interval '1 second') > now()
  order by updated_at desc
  limit 1;

  if not found then
    raise exception 'no_active_ai_entitlement';
  end if;

  select * into v_balance
  from public.ai_credit_balances
  where user_id = v_user_id
  for update;

  if not found or v_balance.period_end <= now() then
    raise exception 'ai_credit_period_inactive';
  end if;

  if v_balance.credits_remaining < v_pricing.credit_cost then
    raise exception 'insufficient_ai_credits';
  end if;

  update public.ai_credit_balances
  set credits_reserved = public.ai_credit_balances.credits_reserved + v_pricing.credit_cost,
      updated_at = now()
  where user_id = v_user_id
  returning public.ai_credit_balances.credits_remaining into v_remaining;

  insert into public.ai_usage_ledger (
    user_id,
    case_id,
    feature,
    provider,
    model,
    status,
    credits_reserved,
    credits_charged,
    idempotency_key,
    reservation_expires_at
  ) values (
    v_user_id,
    p_case_id,
    p_feature,
    'anthropic',
    v_pricing.model_tier,
    'pending',
    v_pricing.credit_cost,
    0,
    p_idempotency_key,
    v_expires_at
  ) returning id into v_ledger_id;

  return query select v_ledger_id, v_pricing.credit_cost, v_remaining, v_expires_at;
end;
$$;

revoke all on function public.proofkit_get_ai_credit_balance(uuid) from public, anon, authenticated;
revoke all on function public.proofkit_reserve_ai_credits(uuid, text, uuid, text) from public, anon, authenticated;

grant execute on function public.proofkit_get_ai_credit_balance(uuid) to service_role;
grant execute on function public.proofkit_reserve_ai_credits(uuid, text, uuid, text) to service_role;
