-- Address Supabase performance-advisor findings after the AI credit schema.
-- Access semantics are unchanged: users can still only read/update their own
-- profile row, and the new balance FK index only improves joins/deletes.

create index if not exists ai_credit_balances_subscription_account_idx
  on public.ai_credit_balances(subscription_account_id)
  where subscription_account_id is not null;

drop policy if exists "profiles_select_own" on public.profiles;
create policy "profiles_select_own"
  on public.profiles
  for select
  to authenticated
  using (id = (select auth.uid()));

drop policy if exists "profiles_update_own" on public.profiles;
create policy "profiles_update_own"
  on public.profiles
  for update
  to authenticated
  using (id = (select auth.uid()))
  with check (id = (select auth.uid()));
