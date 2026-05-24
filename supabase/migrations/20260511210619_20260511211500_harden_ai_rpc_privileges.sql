-- Harden RPC EXECUTE privileges for ProofKit public-schema functions.
-- Supabase grants EXECUTE broadly by default; these functions are intentionally
-- callable only by the roles listed below. This migration is conditional so it
-- can be replayed from a clean database even after later migrations replace the
-- direct authenticated AI RPC signatures with service-role-only signatures.

do $$
begin
  if to_regprocedure('public.proofkit_register_profile(text,text,text)') is not null then
    execute 'revoke all on function public.proofkit_register_profile(text, text, text) from public, anon';
    execute 'grant execute on function public.proofkit_register_profile(text, text, text) to authenticated';
  end if;

  if to_regprocedure('public.proofkit_get_ai_credit_balance()') is not null then
    execute 'revoke all on function public.proofkit_get_ai_credit_balance() from public, anon';
    execute 'grant execute on function public.proofkit_get_ai_credit_balance() to authenticated';
  end if;

  if to_regprocedure('public.proofkit_reserve_ai_credits(text,uuid,text)') is not null then
    execute 'revoke all on function public.proofkit_reserve_ai_credits(text, uuid, text) from public, anon';
    execute 'grant execute on function public.proofkit_reserve_ai_credits(text, uuid, text) to authenticated';
  end if;

  if to_regprocedure('public.proofkit_get_ai_credit_balance(uuid)') is not null then
    execute 'revoke all on function public.proofkit_get_ai_credit_balance(uuid) from public, anon, authenticated';
    execute 'grant execute on function public.proofkit_get_ai_credit_balance(uuid) to service_role';
  end if;

  if to_regprocedure('public.proofkit_reserve_ai_credits(uuid,text,uuid,text)') is not null then
    execute 'revoke all on function public.proofkit_reserve_ai_credits(uuid, text, uuid, text) from public, anon, authenticated';
    execute 'grant execute on function public.proofkit_reserve_ai_credits(uuid, text, uuid, text) to service_role';
  end if;

  if to_regprocedure('public.proofkit_finalize_ai_usage(uuid,integer,integer,numeric,numeric,text,text,text)') is not null then
    execute 'revoke all on function public.proofkit_finalize_ai_usage(uuid, integer, integer, numeric, numeric, text, text, text) from public, anon, authenticated';
    execute 'grant execute on function public.proofkit_finalize_ai_usage(uuid, integer, integer, numeric, numeric, text, text, text) to service_role';
  end if;

  if to_regprocedure('public.proofkit_refund_ai_reservation(uuid,text)') is not null then
    execute 'revoke all on function public.proofkit_refund_ai_reservation(uuid, text) from public, anon, authenticated';
    execute 'grant execute on function public.proofkit_refund_ai_reservation(uuid, text) to service_role';
  end if;

  if to_regprocedure('public.proofkit_sync_subscription_account(uuid,text,text,text,text,timestamp with time zone,timestamp with time zone,timestamp with time zone,text,text)') is not null then
    execute 'revoke all on function public.proofkit_sync_subscription_account(uuid, text, text, text, text, timestamptz, timestamptz, timestamptz, text, text) from public, anon, authenticated';
    execute 'grant execute on function public.proofkit_sync_subscription_account(uuid, text, text, text, text, timestamptz, timestamptz, timestamptz, text, text) to service_role';
  end if;
end;
$$;
