-- Add user-provided onboarding names to profiles without touching local data.
-- Existing rows are preserved; the new column is nullable and filled only when
-- the app submits a non-empty name during onboarding/profile registration.

alter table public.profiles
  add column if not exists display_name text;

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
  v_display_name text := nullif(btrim(regexp_replace(coalesce(p_display_name, ''), '\s+', ' ', 'g')), '');
  v_profile_display_name text;
begin
  if v_user_id is null then
    raise exception 'proofkit_register_profile requires an authenticated user';
  end if;

  if v_display_name is not null and char_length(v_display_name) > 80 then
    v_display_name := btrim(left(v_display_name, 80));
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
      onboarding_category = coalesce(onboarding_category, nullif(p_onboarding_category, '')),
      display_name = coalesce(nullif(display_name, ''), v_display_name),
      has_registered_before = true,
      last_seen_at = now(),
      updated_at = now()
    where id = v_user_id
    returning display_name into v_profile_display_name;

    return query select false, true, v_profile_display_name;
  else
    insert into public.profiles (
      id,
      email,
      onboarding_category,
      display_name,
      has_registered_before,
      registered_at,
      last_seen_at,
      created_at,
      updated_at
    ) values (
      v_user_id,
      nullif(p_email, ''),
      nullif(p_onboarding_category, ''),
      v_display_name,
      true,
      now(),
      now(),
      now(),
      now()
    )
    returning display_name into v_profile_display_name;

    return query select true, false, v_profile_display_name;
  end if;
end;
$$;

grant execute on function public.proofkit_register_profile(text, text, text) to authenticated;
