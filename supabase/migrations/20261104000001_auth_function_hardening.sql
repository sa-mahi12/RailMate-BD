-- 2026-11-04 auth-function hardening (Supabase advisors 0011/0028/0029).
--
-- Observed on the hosted RailMate project 2026-11-04:
--   * 0011 `public.normalize_username` has a role-mutable `search_path`.
--   * 0028/0029 `public.bootstrap_new_user` is SECURITY DEFINER and was
--     EXECUTE-able by `anon`/`authenticated`/PUBLIC through
--     `/rest/v1/rpc/bootstrap_new_user`.
--
-- Both functions exist only to run as triggers on `auth.users` /
-- `public.usernames`. PostgreSQL does not check EXECUTE privilege on a
-- trigger function when the trigger fires, so revoking EXECUTE from the
-- client roles does not affect signup or username normalisation; it only
-- removes the pointless RPC surface. Verified after applying: an admin-created
-- user still produced its profile + username rows, and the anon RPC call was
-- rejected.
--
-- Additive and reversible: re-grant EXECUTE to restore the previous state.

-- 1. Pin the search path. The body only uses pg_catalog built-ins
--    (`lower`, `btrim`), which resolve without a search path.
create or replace function public.normalize_username()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.username := pg_catalog.lower(
    pg_catalog.btrim(new.username, E' \t\n\r\f\v')
  );
  return new;
end;
$$;

comment on function public.normalize_username() is
  'Trigger-only username normaliser (trim + lowercase). search_path pinned; '
  'not callable by client roles.';

-- 2. Remove the client-callable surface from the signup bootstrap trigger.
revoke execute on function public.bootstrap_new_user() from public;
revoke execute on function public.bootstrap_new_user() from anon;
revoke execute on function public.bootstrap_new_user() from authenticated;

comment on function public.bootstrap_new_user() is
  'Signup bootstrap trigger: profile row + username claim in dependency order. '
  'Best-effort by design; never raises, never fails a signup. Trigger-only: '
  'EXECUTE revoked from PUBLIC/anon/authenticated (advisors 0028/0029).';
