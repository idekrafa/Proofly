-- Trial users receive full Pro non-AI access, but only 3 AI credits total
-- during the trial period. Privacy rule: usage/accounting tables continue to
-- store entitlement, credit, status, token, cost, and hash metadata only.

create or replace function public.proofkit_sync_subscription_account(
  p_user_id uuid,
  p_provider_customer_id text default null,
  p_entitlement_id text default null,
  p_plan text default 'none',
  p_status text default 'expired',
  p_current_period_start timestamptz default null,
  p_current_period_end timestamptz default null,
  p_trial_ends_at timestamptz default null,
  p_renews_into_plan text default null,
  p_source_event_id text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_account_id uuid;
  v_allowance integer := 0;
  v_unlimited_cases boolean := false;
  v_period_start timestamptz := coalesce(p_current_period_start, now());
  v_period_end timestamptz := p_current_period_end;
  v_existing_period_start timestamptz;
  v_existing_period_end timestamptz;
  v_period_changed boolean;
begin
  if p_user_id is null then
    raise exception 'proofkit_sync_subscription_account requires a user id';
  end if;

  if p_plan = 'trial_weekly_intro' or p_status = 'trialing' then
    v_allowance := 3;
    v_unlimited_cases := true;
    v_period_end := coalesce(v_period_end, now() + interval '7 days');
  elsif p_plan = 'weekly_pro' then
    v_allowance := 15;
    v_unlimited_cases := true;
    v_period_end := coalesce(v_period_end, now() + interval '7 days');
  elsif p_plan = 'monthly_pro' then
    v_allowance := 75;
    v_unlimited_cases := true;
    v_period_end := coalesce(v_period_end, now() + interval '1 month');
  else
    v_allowance := 0;
    v_unlimited_cases := false;
    v_period_end := coalesce(v_period_end, now() + interval '1 second');
  end if;

  if p_status in ('expired','billing_retry','revoked_or_refunded') then
    v_allowance := 0;
    v_unlimited_cases := false;
  end if;

  insert into public.subscription_accounts (
    user_id,
    provider,
    provider_customer_id,
    entitlement_id,
    plan,
    status,
    current_period_start,
    current_period_end,
    trial_ends_at,
    renews_into_plan,
    ai_credit_allowance,
    unlimited_cases,
    source_event_id,
    created_at,
    updated_at
  ) values (
    p_user_id,
    'revenuecat',
    p_provider_customer_id,
    p_entitlement_id,
    p_plan,
    p_status,
    v_period_start,
    v_period_end,
    p_trial_ends_at,
    p_renews_into_plan,
    v_allowance,
    v_unlimited_cases,
    p_source_event_id,
    now(),
    now()
  )
  on conflict (provider, user_id) do update set
    provider_customer_id = excluded.provider_customer_id,
    entitlement_id = excluded.entitlement_id,
    plan = excluded.plan,
    status = excluded.status,
    current_period_start = excluded.current_period_start,
    current_period_end = excluded.current_period_end,
    trial_ends_at = excluded.trial_ends_at,
    renews_into_plan = excluded.renews_into_plan,
    ai_credit_allowance = excluded.ai_credit_allowance,
    unlimited_cases = excluded.unlimited_cases,
    source_event_id = excluded.source_event_id,
    updated_at = now()
  returning id into v_account_id;

  if v_allowance <= 0 then
    update public.ai_credit_balances
    set subscription_account_id = v_account_id,
        period_start = v_period_start,
        period_end = v_period_end,
        credits_granted = 0,
        credits_reserved = 0,
        credits_used = 0,
        updated_at = now()
    where user_id = p_user_id;

    return v_account_id;
  end if;

  select period_start, period_end
    into v_existing_period_start, v_existing_period_end
  from public.ai_credit_balances
  where user_id = p_user_id;

  v_period_changed := v_existing_period_start is distinct from v_period_start
    or v_existing_period_end is distinct from v_period_end;

  insert into public.ai_credit_balances (
    user_id,
    subscription_account_id,
    period_start,
    period_end,
    credits_granted,
    credits_reserved,
    credits_used,
    updated_at
  ) values (
    p_user_id,
    v_account_id,
    v_period_start,
    v_period_end,
    v_allowance,
    0,
    0,
    now()
  )
  on conflict (user_id) do update set
    subscription_account_id = excluded.subscription_account_id,
    period_start = excluded.period_start,
    period_end = excluded.period_end,
    credits_granted = excluded.credits_granted,
    credits_reserved = case
      when v_period_changed then 0
      else least(
        public.ai_credit_balances.credits_reserved,
        greatest(
          0,
          excluded.credits_granted - least(public.ai_credit_balances.credits_used, excluded.credits_granted)
        )
      )
    end,
    credits_used = case when v_period_changed then 0 else least(public.ai_credit_balances.credits_used, excluded.credits_granted) end,
    updated_at = now();

  return v_account_id;
end;
$$;

revoke all on function public.proofkit_sync_subscription_account(uuid, text, text, text, text, timestamptz, timestamptz, timestamptz, text, text) from public, anon, authenticated;
grant execute on function public.proofkit_sync_subscription_account(uuid, text, text, text, text, timestamptz, timestamptz, timestamptz, text, text) to service_role;
