-- Remove the AI credit metering system. AI access is now gated only by an
-- active subscription (checked by ai-proxy against subscription_accounts);
-- per-request credit accounting, reservations, and the usage ledger are gone.
-- The subscription system (subscription_accounts, RevenueCat webhook sync,
-- purchase-entitlements) stays.

-- 1. Recreate the subscription sync RPC without any credit bookkeeping.
--    Same signature so the revenuecat-webhook function keeps working unchanged.
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
  v_unlimited_cases boolean := false;
  v_period_start timestamptz := coalesce(p_current_period_start, now());
  v_period_end timestamptz := p_current_period_end;
begin
  if p_user_id is null then
    raise exception 'proofkit_sync_subscription_account requires a user id';
  end if;

  if p_plan = 'trial_weekly_intro' or p_status = 'trialing' then
    v_unlimited_cases := true;
    v_period_end := coalesce(v_period_end, now() + interval '7 days');
  elsif p_plan = 'weekly_pro' then
    v_unlimited_cases := true;
    v_period_end := coalesce(v_period_end, now() + interval '7 days');
  elsif p_plan = 'monthly_pro' then
    v_unlimited_cases := true;
    v_period_end := coalesce(v_period_end, now() + interval '1 month');
  else
    v_unlimited_cases := false;
    v_period_end := coalesce(v_period_end, now() + interval '1 second');
  end if;

  if p_status in ('expired','billing_retry','revoked_or_refunded') then
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
    unlimited_cases = excluded.unlimited_cases,
    source_event_id = excluded.source_event_id,
    updated_at = now()
  returning id into v_account_id;

  return v_account_id;
end;
$$;

revoke all on function public.proofkit_sync_subscription_account(uuid, text, text, text, text, timestamptz, timestamptz, timestamptz, text, text) from public, anon, authenticated;
grant execute on function public.proofkit_sync_subscription_account(uuid, text, text, text, text, timestamptz, timestamptz, timestamptz, text, text) to service_role;

-- 2. Drop the credit RPCs.
drop function if exists public.proofkit_get_ai_credit_balance(uuid);
drop function if exists public.proofkit_reserve_ai_credits(uuid, text, uuid, text);
drop function if exists public.proofkit_finalize_ai_usage(uuid, integer, integer, numeric, numeric, text, text, text);
drop function if exists public.proofkit_refund_ai_reservation(uuid, text);

-- 3. Drop the credit tables (usage ledger included — history is intentionally discarded).
drop table if exists public.ai_usage_ledger cascade;
drop table if exists public.ai_credit_balances cascade;
drop table if exists public.ai_feature_pricing cascade;

-- 4. Drop the per-plan credit allowance column; plans no longer carry credits.
alter table public.subscription_accounts drop column if exists ai_credit_allowance;
