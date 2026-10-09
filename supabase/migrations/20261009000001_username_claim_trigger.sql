-- Username claim on signup (consumer-readiness follow-up, coordinator).
--
-- Gap found by source audit: registration stores the username only in
-- auth user-metadata, so `public.usernames` stayed empty forever and the
-- register screen's live availability check always read "Available".
--
-- This trigger claims the handle into `public.usernames` in the signup
-- transaction itself (security definer, so RLS is irrelevant here). It is
-- deliberately best-effort and can NEVER break a signup:
--   * empty/invalid handles are skipped (the metadata still holds them);
--   * a taken handle hits ON CONFLICT DO NOTHING and stays metadata-only.
-- The live check plus the primary-key constraint remain the arbiters for
-- the normal case; races resolve to metadata-only, which the profile
-- already displays from metadata.
create or replace function public.claim_username_from_signup()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_username text;
begin
  v_username := lower(
    trim(both from coalesce(new.raw_user_meta_data ->> 'username', ''))
  );
  -- Mirror the app's shared format rules (username.dart): 3-20 chars,
  -- lowercase letters/digits/underscore, letter first. Anything else is
  -- skipped rather than failing the signup.
  if v_username !~ '^[a-z][a-z0-9_]{2,19}$' then
    return new;
  end if;
  insert into public.usernames (username, user_id)
  values (v_username, new.id)
  on conflict (username) do nothing;
  return new;
end;
$$;

comment on function public.claim_username_from_signup() is
  'Claims the signup metadata username into public.usernames. '
  'Best-effort: invalid or taken handles are skipped, never failing signup.';

drop trigger if exists trg_claim_username on auth.users;

create trigger trg_claim_username
after insert on auth.users
for each row
execute function public.claim_username_from_signup();
