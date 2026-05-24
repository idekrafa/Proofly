-- Tighten AI output caps and make reservation idempotency status explicit.
-- Privacy rule: usage/accounting tables continue to store only status, token,
-- cost, and hash metadata. No OCR text, prompts, filenames, paths, screenshots,
-- PDFs, case titles, notes, or AI outputs are stored remotely.

update public.ai_feature_pricing
set max_output_tokens = case feature
    when 'rewrite_note' then 450
    when 'timeline_summary' then 850
    when 'ask_ai_short' then 450
    when 'ask_ai_case' then 900
    when 'packet_polish' then 1700
    when 'deep_review' then 2400
    else max_output_tokens
  end,
  updated_at = now()
where feature in (
  'rewrite_note',
  'timeline_summary',
  'ask_ai_short',
  'ask_ai_case',
  'packet_polish',
  'deep_review'
);

drop function if exists public.proofkit_reserve_ai_credits(uuid, text, uuid, text);

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
  expires_at timestamptz,
  ledger_status text,
  was_existing boolean
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

  if p_idempotency_key is not null and btrim(p_idempotency_key) <> '' then
    select * into v_existing
    from public.ai_usage_ledger
    where user_id = v_user_id
      and idempotency_key = p_idempotency_key
    order by created_at desc
    limit 1
    for update;

    if found then
      select * into v_balance
      from public.ai_credit_balances
      where user_id = v_user_id;

      return query select
        v_existing.id,
        v_existing.credits_reserved,
        coalesce(v_balance.credits_remaining, 0),
        v_existing.reservation_expires_at,
        v_existing.status,
        true;
      return;
    end if;
  end if;

  select count(*) into v_recent_count
  from public.ai_usage_ledger
  where user_id = v_user_id
    and created_at > now() - interval '1 minute'
    and status in ('pending','succeeded');

  if v_recent_count >= 6 then
    raise exception 'ai_rate_limited';
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

  if not found then
    raise exception 'ai_credit_period_inactive';
  end if;

  if p_idempotency_key is not null and btrim(p_idempotency_key) <> '' then
    select * into v_existing
    from public.ai_usage_ledger
    where user_id = v_user_id
      and idempotency_key = p_idempotency_key
    order by created_at desc
    limit 1;

    if found then
      return query select
        v_existing.id,
        v_existing.credits_reserved,
        coalesce(v_balance.credits_remaining, 0),
        v_existing.reservation_expires_at,
        v_existing.status,
        true;
      return;
    end if;
  end if;

  if v_balance.period_end <= now() then
    raise exception 'ai_credit_period_inactive';
  end if;

  if v_balance.credits_remaining < v_pricing.credit_cost then
    raise exception 'insufficient_ai_credits';
  end if;

  begin
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
  exception when unique_violation then
    select * into v_existing
    from public.ai_usage_ledger
    where user_id = v_user_id
      and idempotency_key = p_idempotency_key
    order by created_at desc
    limit 1;

    if found then
      return query select
        v_existing.id,
        v_existing.credits_reserved,
        coalesce(v_balance.credits_remaining, 0),
        v_existing.reservation_expires_at,
        v_existing.status,
        true;
      return;
    end if;

    raise;
  end;

  update public.ai_credit_balances
  set credits_reserved = public.ai_credit_balances.credits_reserved + v_pricing.credit_cost,
      updated_at = now()
  where user_id = v_user_id
  returning public.ai_credit_balances.credits_remaining into v_remaining;

  return query select
    v_ledger_id,
    v_pricing.credit_cost,
    v_remaining,
    v_expires_at,
    'pending'::text,
    false;
end;
$$;

revoke all on function public.proofkit_reserve_ai_credits(uuid, text, uuid, text) from public, anon, authenticated;
grant execute on function public.proofkit_reserve_ai_credits(uuid, text, uuid, text) to service_role;
