-- Proofly backend RPC smoke for a real Supabase project when no separate test
-- environment exists.
--
-- Run through Supabase SQL editor or Supabase MCP execute_sql. The script uses
-- fixed synthetic auth user IDs, stores no fixture OCR/prompt/output text, and
-- deletes the synthetic users at the end. Foreign-key cascades remove related
-- subscription, balance, and ledger rows. If an assertion fails, the exception
-- handler still deletes the fixed synthetic users before re-raising.

do $$
declare
  v_trial uuid := '00000000-0000-4000-8000-00000000e201'::uuid;
  v_weekly uuid := '00000000-0000-4000-8000-00000000e202'::uuid;
  v_monthly uuid := '00000000-0000-4000-8000-00000000e203'::uuid;
  v_inactive uuid := '00000000-0000-4000-8000-00000000e204'::uuid;
  v_blocked uuid := '00000000-0000-4000-8000-00000000e205'::uuid;
  v_user_ids uuid[] := array[v_trial, v_weekly, v_monthly, v_inactive, v_blocked];
  v_account public.subscription_accounts%rowtype;
  v_balance public.ai_credit_balances%rowtype;
  v_reserve record;
  v_duplicate record;
  v_ledger public.ai_usage_ledger%rowtype;
  v_error text;
  v_run text := 'proofly_backend_rpc_smoke';
begin
  delete from auth.users where id = any(v_user_ids);

  insert into auth.users (
    id,
    aud,
    role,
    email,
    encrypted_password,
    email_confirmed_at,
    raw_app_meta_data,
    raw_user_meta_data,
    created_at,
    updated_at
  )
  select
    user_id,
    'authenticated',
    'authenticated',
    'proofly-e2e-' || right(user_id::text, 4) || '@synthetic.invalid',
    '',
    now(),
    '{"provider":"email","providers":["email"]}'::jsonb,
    jsonb_build_object('proofly_e2e', true, 'run_id', v_run),
    now(),
    now()
  from unnest(v_user_ids) as user_id;

  perform public.proofkit_sync_subscription_account(
    v_trial,
    'synthetic-customer-trial',
    'pro',
    'trial_weekly_intro',
    'trialing',
    now(),
    now() + interval '7 days',
    now() + interval '7 days',
    'weekly_pro',
    v_run || '-trial'
  );

  select * into v_account from public.subscription_accounts where user_id = v_trial;
  if v_account.plan <> 'trial_weekly_intro'
    or v_account.status <> 'trialing'
    or v_account.renews_into_plan <> 'weekly_pro'
    or v_account.unlimited_cases is not true
    or v_account.ai_credit_allowance <> 3 then
    raise exception 'trial account assertion failed: %', row_to_json(v_account);
  end if;

  select * into v_balance from public.ai_credit_balances where user_id = v_trial;
  if v_balance.credits_granted <> 3 or v_balance.credits_remaining <> 3 then
    raise exception 'trial balance assertion failed: %', row_to_json(v_balance);
  end if;

  perform public.proofkit_sync_subscription_account(v_weekly, 'synthetic-customer-weekly', 'pro', 'weekly_pro', 'active_weekly', now(), now() + interval '7 days', null, null, v_run || '-weekly');
  select * into v_balance from public.ai_credit_balances where user_id = v_weekly;
  if v_balance.credits_granted <> 15 or v_balance.credits_remaining <> 15 then
    raise exception 'weekly balance assertion failed: %', row_to_json(v_balance);
  end if;

  perform public.proofkit_sync_subscription_account(v_monthly, 'synthetic-customer-monthly', 'pro', 'monthly_pro', 'active_monthly', now(), now() + interval '1 month', null, null, v_run || '-monthly');
  select * into v_balance from public.ai_credit_balances where user_id = v_monthly;
  if v_balance.credits_granted <> 75 or v_balance.credits_remaining <> 75 then
    raise exception 'monthly balance assertion failed: %', row_to_json(v_balance);
  end if;

  perform public.proofkit_sync_subscription_account(v_inactive, 'synthetic-customer-inactive', 'pro', 'weekly_pro', 'expired', now(), now() + interval '1 second', null, null, v_run || '-expired');
  select * into v_balance from public.ai_credit_balances where user_id = v_inactive;
  if v_balance.credits_granted <> 0 or v_balance.credits_reserved <> 0 or v_balance.credits_used <> 0 then
    raise exception 'inactive balance assertion failed: %', row_to_json(v_balance);
  end if;

  begin
    perform * from public.proofkit_reserve_ai_credits(v_inactive, 'rewrite_note', gen_random_uuid(), v_run || '-inactive-reserve');
    raise exception 'inactive reserve unexpectedly succeeded';
  exception when others then
    v_error := sqlerrm;
    if v_error not like '%no_active_ai_entitlement%'
      and v_error not like '%ai_credit_period_inactive%'
      and v_error not like '%insufficient_ai_credits%' then
      raise exception 'inactive reserve failed with unexpected error: %', v_error;
    end if;
  end;

  select * into v_reserve from public.proofkit_reserve_ai_credits(v_trial, 'rewrite_note', gen_random_uuid(), v_run || '-reserve-rewrite');
  if v_reserve.credits_reserved <> 1 or v_reserve.remaining_credits <> 2 then
    raise exception 'rewrite reserve assertion failed: %', row_to_json(v_reserve);
  end if;

  select * into v_duplicate from public.proofkit_reserve_ai_credits(v_trial, 'rewrite_note', gen_random_uuid(), v_run || '-reserve-rewrite');
  if v_duplicate.ledger_id <> v_reserve.ledger_id then
    raise exception 'idempotent duplicate did not return same ledger';
  end if;

  select * into v_balance from public.ai_credit_balances where user_id = v_trial;
  if v_balance.credits_reserved <> 1 or v_balance.credits_remaining <> 2 then
    raise exception 'duplicate changed balance unexpectedly: %', row_to_json(v_balance);
  end if;

  select * into v_reserve from public.proofkit_reserve_ai_credits(v_trial, 'timeline_summary', gen_random_uuid(), v_run || '-reserve-timeline');
  if v_reserve.credits_reserved <> 2 or v_reserve.remaining_credits <> 0 then
    raise exception 'timeline reserve assertion failed: %', row_to_json(v_reserve);
  end if;

  perform public.proofkit_sync_subscription_account(v_blocked, 'synthetic-customer-blocked', 'pro', 'trial_weekly_intro', 'trialing', now(), now() + interval '7 days', now() + interval '7 days', 'weekly_pro', v_run || '-blocked');

  begin
    perform * from public.proofkit_reserve_ai_credits(v_blocked, 'packet_polish', gen_random_uuid(), v_run || '-packet-block');
    raise exception 'packet_polish unexpectedly reserved for trial';
  exception when others then
    if sqlerrm not like '%insufficient_ai_credits%' then
      raise exception 'packet_polish block unexpected error: %', sqlerrm;
    end if;
  end;

  begin
    perform * from public.proofkit_reserve_ai_credits(v_blocked, 'deep_review', gen_random_uuid(), v_run || '-deep-block');
    raise exception 'deep_review unexpectedly reserved for trial';
  exception when others then
    if sqlerrm not like '%insufficient_ai_credits%' then
      raise exception 'deep_review block unexpected error: %', sqlerrm;
    end if;
  end;

  begin
    perform * from public.proofkit_reserve_ai_credits(v_blocked, 'ask_ai_short', gen_random_uuid(), v_run || '-ask-short-disabled');
    raise exception 'ask_ai_short unexpectedly reserved';
  exception when others then
    if sqlerrm not like '%ai_feature_disabled%' then
      raise exception 'ask_ai_short unexpected error: %', sqlerrm;
    end if;
  end;

  begin
    perform * from public.proofkit_reserve_ai_credits(v_blocked, 'ask_ai_case', gen_random_uuid(), v_run || '-ask-case-disabled');
    raise exception 'ask_ai_case unexpectedly reserved';
  exception when others then
    if sqlerrm not like '%ai_feature_disabled%' then
      raise exception 'ask_ai_case unexpected error: %', sqlerrm;
    end if;
  end;

  select * into v_reserve from public.proofkit_reserve_ai_credits(v_weekly, 'rewrite_note', gen_random_uuid(), v_run || '-finalize');
  perform public.proofkit_finalize_ai_usage(v_reserve.ledger_id, 121, 37, 0.000077, null, repeat('a', 64), repeat('b', 64), 'proofly-e2e-mock-haiku');
  select * into v_ledger from public.ai_usage_ledger where id = v_reserve.ledger_id;
  if v_ledger.status <> 'succeeded'
    or v_ledger.credits_charged <> 1
    or v_ledger.input_tokens <> 121
    or v_ledger.output_tokens <> 37
    or v_ledger.model <> 'proofly-e2e-mock-haiku'
    or v_ledger.request_hash is null
    or v_ledger.response_hash is null then
    raise exception 'finalized ledger assertion failed: %', row_to_json(v_ledger);
  end if;

  select * into v_balance from public.ai_credit_balances where user_id = v_weekly;
  if v_balance.credits_reserved <> 0 or v_balance.credits_used <> 1 or v_balance.credits_remaining <> 14 then
    raise exception 'finalized balance assertion failed: %', row_to_json(v_balance);
  end if;

  select * into v_reserve from public.proofkit_reserve_ai_credits(v_weekly, 'timeline_summary', gen_random_uuid(), v_run || '-refund');
  perform public.proofkit_refund_ai_reservation(v_reserve.ledger_id, 'provider_503');
  select * into v_ledger from public.ai_usage_ledger where id = v_reserve.ledger_id;
  if v_ledger.status <> 'failed' or v_ledger.credits_charged <> 0 or v_ledger.error_code <> 'provider_503' then
    raise exception 'refunded ledger assertion failed: %', row_to_json(v_ledger);
  end if;

  select * into v_balance from public.ai_credit_balances where user_id = v_weekly;
  if v_balance.credits_reserved <> 0 or v_balance.credits_used <> 1 or v_balance.credits_remaining <> 14 then
    raise exception 'refunded balance assertion failed: %', row_to_json(v_balance);
  end if;

  select * into v_duplicate from public.proofkit_reserve_ai_credits(v_weekly, 'timeline_summary', gen_random_uuid(), v_run || '-refund');
  if v_duplicate.ledger_id <> v_reserve.ledger_id then
    raise exception 'failed idempotency key did not return existing ledger';
  end if;

  if exists (
    select 1
    from public.ai_feature_pricing
    where (feature = 'rewrite_note' and (credit_cost <> 1 or max_output_tokens <> 450 or enabled is not true))
       or (feature = 'timeline_summary' and (credit_cost <> 2 or max_output_tokens <> 850 or enabled is not true))
       or (feature = 'packet_polish' and (credit_cost <> 4 or max_output_tokens <> 1700 or enabled is not true))
       or (feature = 'deep_review' and (credit_cost <> 10 or max_output_tokens <> 2400 or enabled is not true))
       or (feature = 'ask_ai_short' and (credit_cost <> 1 or max_output_tokens <> 450 or enabled is not false))
       or (feature = 'ask_ai_case' and (credit_cost <> 3 or max_output_tokens <> 900 or enabled is not false))
  ) then
    raise exception 'pricing table assertion failed';
  end if;

  if exists (
    select 1
    from public.ai_usage_ledger
    where user_id = any(v_user_ids)
      and row_to_json(ai_usage_ledger)::text ~ '(SYNTH_|synthetic_apartment|/private/var/mobile|\.jpg|\.pdf|window leak|fake lab report|freelance invoice|AI output)'
  ) then
    raise exception 'privacy leak assertion failed for ai_usage_ledger';
  end if;

  delete from auth.users where id = any(v_user_ids);
exception when others then
  delete from auth.users where id = any(v_user_ids);
  raise;
end $$;

select
  'proofly_backend_rpc_smoke_passed' as result,
  now() as verified_at,
  (select count(*) from public.ai_feature_pricing) as pricing_rows,
  (
    select count(*)
    from public.subscription_accounts
    where user_id in (
      '00000000-0000-4000-8000-00000000e201',
      '00000000-0000-4000-8000-00000000e202',
      '00000000-0000-4000-8000-00000000e203',
      '00000000-0000-4000-8000-00000000e204',
      '00000000-0000-4000-8000-00000000e205'
    )
  ) as leftover_subscription_rows,
  (
    select count(*)
    from public.ai_usage_ledger
    where user_id in (
      '00000000-0000-4000-8000-00000000e201',
      '00000000-0000-4000-8000-00000000e202',
      '00000000-0000-4000-8000-00000000e203',
      '00000000-0000-4000-8000-00000000e204',
      '00000000-0000-4000-8000-00000000e205'
    )
  ) as leftover_ledger_rows;
