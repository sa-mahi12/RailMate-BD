-- New-user bootstrap (supersedes 20261009000001_username_claim_trigger.sql).
--
-- What went wrong: the claim-only trigger inserted into public.usernames,
-- whose user_id has a FOREIGN KEY to public.profiles(id) — but nothing ever
-- creates profile rows (no trigger, no app code). Every signup therefore
-- died with "Database error saving new user" (proven live on the emulator
-- with the release build, 2026-10-13).
--
-- This trigger does the whole bootstrap in the signup transaction, in
-- dependency order, and can NEVER fail a signup:
--   1. profile row (id, display_name from metadata full_name or ''),
--      ON CONFLICT DO NOTHING;
--   2. username claim (valid handles only), ON CONFLICT DO NOTHING;
--   3. a blanket EXCEPTION handler returns NEW so even an unforeseen
--      failure (e.g. a future constraint) degrades to metadata-only
--      instead of aborting the signup.
-- RLS is irrelevant here (security definer, owner postgres). The app reads
-- its own profile through the existing profiles_select_own policy.
drop trigger if exists trg_claim_username on auth.users;
drop function if exists public.claim_username_from_signup();

create or replace function public.bootstrap_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_username text;
  v_name text;
begin
  v_name := nullif(
    trim(both from coalesce(new.raw_user_meta_data ->> 'full_name', '')),
    ''
  );
  insert into public.profiles (id, display_name)
  values (new.id, coalesce(v_name, ''))
  on conflict (id) do nothing;

  v_username := lower(
    trim(both from coalesce(new.raw_user_meta_data ->> 'username', ''))
  );
  -- Mirror the app's shared format rules; anything else stays
  -- metadata-only rather than failing the signup.
  if v_username ~ '^[a-z][a-z0-9_]{2,19}$' then
    insert into public.usernames (username, user_id)
    values (v_username, new.id)
    on conflict (username) do nothing;
  end if;
  return new;
exception
  when others then
    -- Bootstrap must never break registration. The account exists with or
    -- without its profile/username rows (both are re-derivable).
    return new;
end;
$$;

comment on function public.bootstrap_new_user() is
  'Signup bootstrap: profile row + username claim in dependency order. '
  'Best-effort by design; never raises, never fails a signup.';

drop trigger if exists trg_bootstrap_new_user on auth.users;

create trigger trg_bootstrap_new_user
after insert on auth.users
for each row
execute function public.bootstrap_new_user();
