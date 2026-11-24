-- P42 hardening — review follow-up (2026-11-25)
--
-- The first P42 migration (20261124000001_p42_social_web.sql) is already
-- applied to the hosted project. A read-only review of that live schema found
-- four gaps that are fixed here without changing any client:
--
--   1. IMPORTANT: `storage_path` only had to *look* like `<uuid>/...`. Nothing
--      tied that uuid to the row's owner, so a signed-in user could reference
--      another user's object in their own attachment row (their post would
--      display that object, and a later cleanup keyed on the path would target
--      a foreign file). The prefix must now equal `owner_id`.
--   2. The 10-attachment cap fired only on INSERT, so rows could be moved
--      between the author's own posts (or raced in parallel) past the cap.
--      The cap now also covers UPDATE when `post_id` changes, and counts the
--      target post only.
--   3. Rate limits counted rows whose `created_at` the client can write, so a
--      backdated insert bypassed them. `created_at` is stamped from the server
--      clock on insert for `posts` and `post_comments`.
--   4. The app reports with an upsert (a second report on the same target
--      updates the first), but only INSERT/SELECT were granted and no UPDATE
--      policy existed, so a repeat report errored instead of updating. An
--      own-row UPDATE policy + grant now matches the client. A post author can
--      also no longer report their own post (matching `user_reports_no_self`).
--
-- Everything is additive and idempotent. No row is deleted, no policy is
-- loosened, and the public read surfaces are unchanged.

begin;

-- ---------------------------------------------------------------------------
-- 1. Attachment path prefix must be the owner id
-- ---------------------------------------------------------------------------
-- Added NOT VALID first so a legacy row with an unexpected prefix cannot block
-- this migration; validate then fails loudly if any existing row is wrong.

alter table public.post_attachments
  add constraint post_attachments_path_owner_chk
  check (
    storage_path is null
    or split_part(storage_path, '/', 1) = owner_id::text
  ) not valid;

alter table public.post_attachments
  validate constraint post_attachments_path_owner_chk;

comment on constraint post_attachments_path_owner_chk on public.post_attachments is
  'P42: an attachment may only reference an object inside its own owner folder.';

-- ---------------------------------------------------------------------------
-- 2. Ten-attachment cap also applies when a row moves to another post
-- ---------------------------------------------------------------------------

create or replace function public.limit_post_attachments()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_count integer;
begin
  -- Reordering or relabelling an existing row never changes the count.
  if tg_op = 'UPDATE' and new.post_id is not distinct from old.post_id then
    return new;
  end if;

  select count(*) into v_count
  from public.post_attachments a
  where a.post_id = new.post_id
    and a.id is distinct from new.id;

  if v_count >= 10 then
    raise exception 'ATTACHMENT_LIMIT_REACHED'
      using errcode = 'P0001';
  end if;
  return new;
end;
$function$;

drop trigger if exists post_attachments_limit on public.post_attachments;
create trigger post_attachments_limit
  before insert or update on public.post_attachments
  for each row execute function public.limit_post_attachments();

-- ---------------------------------------------------------------------------
-- 3. Board timestamps come from the server clock
-- ---------------------------------------------------------------------------

create or replace function public.stamp_board_created_at()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
begin
  new.created_at := now();
  return new;
end;
$function$;

drop trigger if exists posts_server_created_at on public.posts;
create trigger posts_server_created_at
  before insert on public.posts
  for each row execute function public.stamp_board_created_at();

drop trigger if exists post_comments_server_created_at on public.post_comments;
create trigger post_comments_server_created_at
  before insert on public.post_comments
  for each row execute function public.stamp_board_created_at();

-- ---------------------------------------------------------------------------
-- 4. A repeat report updates the reporter's own row; the author cannot
--    report their own post
-- ---------------------------------------------------------------------------

drop policy if exists post_reports_update_own on public.post_reports;
create policy post_reports_update_own on public.post_reports
  for update to authenticated
  using (reporter_id = (select auth.uid()))
  with check (reporter_id = (select auth.uid()));

drop policy if exists user_reports_update_own on public.user_reports;
create policy user_reports_update_own on public.user_reports
  for update to authenticated
  using (reporter_id = (select auth.uid()))
  with check (reporter_id = (select auth.uid()));

grant update on public.post_reports to authenticated;
grant update on public.user_reports to authenticated;

create or replace function public.guard_post_report()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_author uuid;
begin
  select p.user_id into v_author from public.posts p where p.id = new.post_id;
  if v_author is not null and v_author = new.reporter_id then
    raise exception 'POST_SELF_REPORT'
      using errcode = 'P0001';
  end if;
  return new;
end;
$function$;

drop trigger if exists post_reports_no_self on public.post_reports;
create trigger post_reports_no_self
  before insert or update on public.post_reports
  for each row execute function public.guard_post_report();

commit;
