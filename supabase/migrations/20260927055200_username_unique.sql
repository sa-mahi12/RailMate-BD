-- B02 — username server uniqueness (DRAFT / NOT APPLIED).
-- Coordinator applies after review; workers never push or migrate.
-- Applies cleanly AFTER 20260927000001_initial_schema.sql and
-- 20260927000002_rls.sql (all statements are IF NOT EXISTS / DO-guarded or
-- CREATE OR REPLACE, so re-running is safe).
-- Do NOT apply to a populated project without backup + approval.
--
-- Contract (R-04): one normalized username per profile. Normalization is
-- lowercase ASCII + trim; invalid values are rejected by CHECK; concurrent
-- claims of the same normalized value yield exactly one success via the
-- existing PRIMARY KEY plus the expression UNIQUE index below.

-- 1. Normalize on write: trim surrounding whitespace, lowercase.
create or replace function public.normalize_username()
returns trigger
language plpgsql
as $$
begin
  new.username := lower(btrim(new.username, E' \t\n\r\f\v'));
  return new;
end;
$$;

drop trigger if exists usernames_normalize_trigger on public.usernames;
create trigger usernames_normalize_trigger
  before insert or update of username on public.usernames
  for each row execute function public.normalize_username();

-- 2. Reject invalid values: 3-20 chars, lowercase letters/digits/underscore,
-- must start with a letter. This tightens the draft inline check
-- (^[a-z0-9_]{3,20}$) to require a letter start, matching
-- lib/features/auth/username/username.dart in this packet.
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'usernames_username_valid_check'
  ) then
    alter table public.usernames
      add constraint usernames_username_valid_check
      check (username ~ '^[a-z][a-z0-9_]{2,19}$');
  end if;
end;
$$;

-- 3. UNIQUE on the normalized value: expression index guards mixed-case
-- concurrent inserts even if a writer bypassed the trigger; the PRIMARY KEY
-- covers the normalized stored form. Together they serialize conflicting
-- claims (one success, others unique-violation).
create unique index if not exists usernames_normalized_unique
  on public.usernames (lower(username));

-- 4. Documented availability query (wired in prod to
-- UsernameAvailabilityChecker via an injectable query; fake in tests):
--   select exists(
--     select 1 from public.usernames
--     where username = lower(btrim($1, E' \t\n\r\f\v'))
--   ) as taken;
-- RLS policy `usernames_read` (anon, authenticated) already permits this
-- SELECT; no policy change in this migration.
