-- Server-authoritative Proofly subscription and AI credit infrastructure.
-- Privacy rule: these tables store entitlement, usage status, token counts, cost
-- estimates, and hashes only. They must never store OCR text, screenshots,
-- filenames, case titles, user notes, prompt bodies, or AI outputs.

create extension if not exists pgcrypto with schema extensions;

create table if not exists public.subscription_accounts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  provider text not null default 'revenuecat',
  provider_customer_id text,
  entitlement_id text,
  plan text not null check (plan in ('trial_weekly_intro','weekly_pro','monthly_pro','none')),
  status text not null check (status in ('trialing','active_weekly','active_monthly','expired','cancelled','billing_retry','revoked_or_refunded')),
  current_period_start timestamptz,
  current_period_end timestamptz,
  trial_ends_at timestamptz,
  renews_into_plan text check (renews_into_plan in ('weekly_pro','monthly_pro')),
  ai_credit_allowance integer not null default 0 check (ai_credit_allowance >= 0),
  unlimited_cases boolean not null default false,
  source_event_id text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists subscription_accounts_provider_user_idx
  on public.subscription_accounts(provider, user_id);
create index if not exists subscription_accounts_user_status_idx
  on public.subscription_accounts(user_id, status, current_period_end desc);
create index if not exists subscription_accounts_source_event_idx
  on public.subscription_accounts(source_event_id)
  where source_event_id is not null;

create table if not exists public.ai_credit_balances (
  user_id uuid primary key references auth.users(id) on delete cascade,
  subscription_account_id uuid references public.subscription_accounts(id) on delete set null,
  period_start timestamptz not null,
  period_end timestamptz not null,
  credits_granted integer not null default 0 check (credits_granted >= 0),
  credits_reserved integer not null default 0 check (credits_reserved >= 0),
  credits_used integer not null default 0 check (credits_used >= 0),
  credits_remaining integer generated always as (credits_granted - credits_reserved - credits_used) stored,
  updated_at timestamptz not null default now(),
  constraint ai_credit_balances_nonnegative_remaining check (credits_granted - credits_reserved - credits_used >= 0),
  constraint ai_credit_balances_period_order check (period_end > period_start)
);

create table if not exists public.ai_usage_ledger (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  case_id uuid,
  feature text not null check (feature in ('timeline_summary','packet_polish','deep_review','ask_ai_short','ask_ai_case','rewrite_note')),
  provider text not null default 'anthropic',
  model text not null,
  status text not null check (status in ('pending','succeeded','failed','refunded','cancelled')),
  credits_reserved integer not null default 0 check (credits_reserved >= 0),
  credits_charged integer not null default 0 check (credits_charged >= 0),
  input_tokens integer check (input_tokens is null or input_tokens >= 0),
  output_tokens integer check (output_tokens is null or output_tokens >= 0),
  estimated_cost_usd numeric(10,6),
  actual_cost_usd numeric(10,6),
  request_hash text,
  response_hash text,
  idempotency_key text,
  error_code text,
  created_at timestamptz not null default now(),
  completed_at timestamptz,
  reservation_expires_at timestamptz
);

create index if not exists ai_usage_ledger_user_created_idx
  on public.ai_usage_ledger(user_id, created_at desc);
create index if not exists ai_usage_ledger_user_feature_created_idx
  on public.ai_usage_ledger(user_id, feature, created_at desc);
create unique index if not exists ai_usage_ledger_user_idempotency_idx
  on public.ai_usage_ledger(user_id, idempotency_key)
  where idempotency_key is not null;

create table if not exists public.ai_feature_pricing (
  feature text primary key check (feature in ('timeline_summary','packet_polish','deep_review','ask_ai_short','ask_ai_case','rewrite_note')),
  credit_cost integer not null check (credit_cost > 0),
  model_tier text not null check (model_tier in ('haiku','premium')),
  max_input_tokens integer not null check (max_input_tokens > 0),
  max_output_tokens integer not null check (max_output_tokens > 0),
  enabled boolean not null default true,
  updated_at timestamptz not null default now()
);

insert into public.ai_feature_pricing(feature, credit_cost, model_tier, max_input_tokens, max_output_tokens, enabled)
values
  ('timeline_summary', 2, 'haiku', 12000, 1200, true),
  ('packet_polish', 4, 'haiku', 20000, 1800, true),
  ('deep_review', 10, 'haiku', 60000, 2500, true),
  ('ask_ai_short', 1, 'haiku', 3000, 800, false),
  ('ask_ai_case', 3, 'haiku', 10000, 1000, false),
  ('rewrite_note', 1, 'haiku', 3000, 800, true)
on conflict (feature) do update set
  credit_cost = excluded.credit_cost,
  model_tier = excluded.model_tier,
  max_input_tokens = excluded.max_input_tokens,
  max_output_tokens = excluded.max_output_tokens,
  enabled = excluded.enabled,
  updated_at = now();

alter table public.subscription_accounts enable row level security;
alter table public.ai_credit_balances enable row level security;
alter table public.ai_usage_ledger enable row level security;
alter table public.ai_feature_pricing enable row level security;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'subscription_accounts' and policyname = 'subscription_accounts_select_own'
  ) then
    create policy "subscription_accounts_select_own"
      on public.subscription_accounts
      for select
      to authenticated
      using (user_id = (select auth.uid()));
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'ai_credit_balances' and policyname = 'ai_credit_balances_select_own'
  ) then
    create policy "ai_credit_balances_select_own"
      on public.ai_credit_balances
      for select
      to authenticated
      using (user_id = (select auth.uid()));
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'ai_usage_ledger' and policyname = 'ai_usage_ledger_select_own'
  ) then
    create policy "ai_usage_ledger_select_own"
      on public.ai_usage_ledger
      for select
      to authenticated
      using (user_id = (select auth.uid()));
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'ai_feature_pricing' and policyname = 'ai_feature_pricing_select_authenticated'
  ) then
    create policy "ai_feature_pricing_select_authenticated"
      on public.ai_feature_pricing
      for select
      to authenticated
      using (true);
  end if;
end;
$$;

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

create or replace function public.proofkit_finalize_ai_usage(
  p_ledger_id uuid,
  p_input_tokens integer default null,
  p_output_tokens integer default null,
  p_estimated_cost_usd numeric default null,
  p_actual_cost_usd numeric default null,
  p_request_hash text default null,
  p_response_hash text default null,
  p_model text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ledger public.ai_usage_ledger%rowtype;
begin
  select * into v_ledger
  from public.ai_usage_ledger
  where id = p_ledger_id
  for update;

  if not found then
    raise exception 'ai_ledger_not_found';
  end if;

  if v_ledger.status <> 'pending' then
    return;
  end if;

  update public.ai_credit_balances
  set credits_reserved = greatest(0, credits_reserved - v_ledger.credits_reserved),
      credits_used = credits_used + v_ledger.credits_reserved,
      updated_at = now()
  where user_id = v_ledger.user_id;

  update public.ai_usage_ledger
  set status = 'succeeded',
      credits_charged = v_ledger.credits_reserved,
      input_tokens = p_input_tokens,
      output_tokens = p_output_tokens,
      estimated_cost_usd = p_estimated_cost_usd,
      actual_cost_usd = p_actual_cost_usd,
      request_hash = p_request_hash,
      response_hash = p_response_hash,
      model = coalesce(nullif(p_model, ''), model),
      completed_at = now()
  where id = p_ledger_id;
end;
$$;

create or replace function public.proofkit_refund_ai_reservation(
  p_ledger_id uuid,
  p_error_code text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ledger public.ai_usage_ledger%rowtype;
begin
  select * into v_ledger
  from public.ai_usage_ledger
  where id = p_ledger_id
  for update;

  if not found then
    return;
  end if;

  if v_ledger.status <> 'pending' then
    return;
  end if;

  update public.ai_credit_balances
  set credits_reserved = greatest(0, credits_reserved - v_ledger.credits_reserved),
      updated_at = now()
  where user_id = v_ledger.user_id;

  update public.ai_usage_ledger
  set status = 'failed',
      credits_charged = 0,
      error_code = left(coalesce(p_error_code, 'provider_failed'), 200),
      completed_at = now()
  where id = p_ledger_id;
end;
$$;

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

revoke all on function public.proofkit_finalize_ai_usage(uuid, integer, integer, numeric, numeric, text, text, text) from public, anon, authenticated;
revoke all on function public.proofkit_refund_ai_reservation(uuid, text) from public, anon, authenticated;
revoke all on function public.proofkit_sync_subscription_account(uuid, text, text, text, text, timestamptz, timestamptz, timestamptz, text, text) from public, anon, authenticated;
revoke all on function public.proofkit_get_ai_credit_balance(uuid) from public, anon, authenticated;
revoke all on function public.proofkit_reserve_ai_credits(uuid, text, uuid, text) from public, anon, authenticated;

grant execute on function public.proofkit_get_ai_credit_balance(uuid) to service_role;
grant execute on function public.proofkit_reserve_ai_credits(uuid, text, uuid, text) to service_role;
grant execute on function public.proofkit_finalize_ai_usage(uuid, integer, integer, numeric, numeric, text, text, text) to service_role;
grant execute on function public.proofkit_refund_ai_reservation(uuid, text) to service_role;
grant execute on function public.proofkit_sync_subscription_account(uuid, text, text, text, text, timestamptz, timestamptz, timestamptz, text, text) to service_role;
