-- Profiles are the server-side account registration source of truth for ProofKit.
-- The mobile app calls proofkit_register_profile after auth so existing users do
-- not get forced back through onboarding-first-case setup.

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text,
  display_name text,
  onboarding_category text,
  has_registered_before boolean not null default true,
  registered_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.profiles
  add column if not exists email text,
  add column if not exists display_name text,
  add column if not exists onboarding_category text,
  add column if not exists has_registered_before boolean not null default true,
  add column if not exists registered_at timestamptz not null default now(),
  add column if not exists last_seen_at timestamptz not null default now(),
  add column if not exists created_at timestamptz not null default now(),
  add column if not exists updated_at timestamptz not null default now();

alter table public.profiles enable row level security;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'profiles'
      and policyname = 'profiles_select_own'
  ) then
    create policy "profiles_select_own"
      on public.profiles
      for select
      to authenticated
      using (id = auth.uid());
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'profiles'
      and policyname = 'profiles_update_own'
  ) then
    create policy "profiles_update_own"
      on public.profiles
      for update
      to authenticated
      using (id = auth.uid())
      with check (id = auth.uid());
  end if;
end;
$$;

drop function if exists public.proofkit_register_profile(text, text);

create or replace function public.proofkit_register_profile(
  p_email text default null,
  p_onboarding_category text default null,
  p_display_name text default null
)
returns table (
  is_new_profile boolean,
  has_registered_before boolean,
  profile_display_name text
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_existing_profile boolean;
begin
  if v_user_id is null then
    raise exception 'proofkit_register_profile requires an authenticated user';
  end if;

  select exists(
    select 1
    from public.profiles
    where id = v_user_id
  ) into v_existing_profile;

  if v_existing_profile then
    update public.profiles
    set
      email = coalesce(nullif(p_email, ''), email),
      display_name = coalesce(nullif(p_display_name, ''), display_name),
      onboarding_category = coalesce(onboarding_category, nullif(p_onboarding_category, '')),
      has_registered_before = true,
      last_seen_at = now(),
      updated_at = now()
    where id = v_user_id;

    return query
      select false, true, p.display_name
      from public.profiles p
      where p.id = v_user_id;
  else
    insert into public.profiles (
      id,
      email,
      display_name,
      onboarding_category,
      has_registered_before,
      registered_at,
      last_seen_at,
      created_at,
      updated_at
    ) values (
      v_user_id,
      nullif(p_email, ''),
      nullif(p_display_name, ''),
      nullif(p_onboarding_category, ''),
      true,
      now(),
      now(),
      now(),
      now()
    );

    return query
      select true, false, p.display_name
      from public.profiles p
      where p.id = v_user_id;
  end if;
end;
$$;

grant execute on function public.proofkit_register_profile(text, text, text) to authenticated;
