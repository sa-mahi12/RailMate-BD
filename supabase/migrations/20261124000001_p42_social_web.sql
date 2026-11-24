-- P42 — real social sharing on the web (2026-11-24)
--
-- Additive, backward-compatible schema for the public GitHub Pages viewer and
-- the multi-attachment Journey Board composer. Nothing here rewrites or drops
-- existing rows: legacy `public.posts.image_path` keeps working and is
-- mirrored into `public.post_attachments` once.
--
-- Objects added:
--   * public.public_profile_cards  — narrow, read-only author identity view.
--   * public.post_attachments      — 0..10 typed attachments per post.
--   * public.public_post_stats     — read-only engagement aggregates.
--   * public.post_reports          — reports against a post.
--   * public.user_reports          — reports against a public profile.
--   * rate-limit triggers for posts/comments.
--   * storage bucket limits on `post-media` (size + MIME allowlist).
--
-- Security posture: `public.profiles` stays own-row-only. The public view
-- exposes only id/username/display_name/joined_at/post_count, never email,
-- phone, Telegram, auth metadata or booking/passenger data. Attachment rows
-- are public-read (the board is public) and owner-write only, enforced both by
-- RLS and by a trigger that requires the attachment owner to own the parent
-- post. External links must be HTTPS; uploaded files must carry a storage path.
-- No arbitrary HTML/iframe content is ever stored; the clients build markup
-- from validated fields only.
--
-- Reverse (manual, only if needed):
--   drop trigger if exists post_attachments_owner_guard on public.post_attachments;
--   drop trigger if exists post_attachments_limit on public.post_attachments;
--   drop trigger if exists posts_rate_limit on public.posts;
--   drop trigger if exists post_comments_rate_limit on public.post_comments;
--   drop function if exists public.guard_post_attachment();
--   drop function if exists public.limit_post_attachments();
--   drop function if exists public.enforce_board_rate_limit();
--   drop view if exists public.public_post_stats;
--   drop view if exists public.public_profile_cards;
--   drop table if exists public.user_reports;
--   drop table if exists public.post_reports;
--   drop table if exists public.post_attachments;
--   alter publication supabase_realtime drop table public.post_attachments;

begin;

-- ---------------------------------------------------------------------------
-- 1. Public author identity (narrow view; base table RLS unchanged)
-- ---------------------------------------------------------------------------

create or replace view public.public_profile_cards
with (security_invoker = false) as
select
  p.id,
  u.username,
  p.display_name,
  p.created_at as joined_at,
  (
    select count(*)
    from public.posts po
    where po.user_id = p.id
  ) as post_count
from public.profiles p
left join public.usernames u on u.user_id = p.id;

comment on view public.public_profile_cards is
  'Safe public author identity for the Journey Board and public website. '
  'Never add email, phone, Telegram, auth metadata or booking fields here.';

revoke all on public.public_profile_cards from public;
grant select on public.public_profile_cards to anon, authenticated;

-- ---------------------------------------------------------------------------
-- 2. Attachments
-- ---------------------------------------------------------------------------

create table if not exists public.post_attachments (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.posts(id) on delete cascade,
  owner_id uuid not null references public.profiles(id) on delete cascade,
  kind text not null check (kind in ('image', 'video', 'file', 'link')),
  storage_path text,
  external_url text,
  mime_type text,
  original_filename text,
  file_size_bytes bigint,
  display_order integer not null default 0,
  created_at timestamptz not null default now(),
  constraint post_attachments_target_chk check (
    (kind = 'link' and storage_path is null and external_url is not null)
    or (kind <> 'link' and storage_path is not null and external_url is null)
  ),
  constraint post_attachments_url_chk check (
    external_url is null
    or (
      external_url ~ '^https://[^[:space:]]+$'
      and char_length(external_url) <= 2048
    )
  ),
  constraint post_attachments_path_chk check (
    storage_path is null
    or (
      storage_path ~ '^[0-9a-fA-F-]{36}/'
      and position('..' in storage_path) = 0
      and char_length(storage_path) <= 320
    )
  ),
  constraint post_attachments_filename_chk check (
    original_filename is null or char_length(original_filename) <= 200
  ),
  constraint post_attachments_mime_chk check (
    mime_type is null or char_length(mime_type) <= 120
  ),
  constraint post_attachments_size_chk check (
    file_size_bytes is null
    or (file_size_bytes >= 0 and file_size_bytes <= 26214400)
  ),
  constraint post_attachments_order_chk check (
    display_order >= 0 and display_order <= 50
  )
);

-- Idempotent backfill key: one attachment row per (post, storage object).
create unique index if not exists post_attachments_post_path_uidx
  on public.post_attachments (post_id, storage_path)
  where storage_path is not null;

create index if not exists post_attachments_post_order_idx
  on public.post_attachments (post_id, display_order, created_at);

comment on table public.post_attachments is
  'Typed Journey Board attachments. Uploaded media lives in the public '
  '`post-media` Storage bucket; links are HTTPS-only and never fetched '
  'server-side. Owner must match the parent post owner (trigger + RLS).';

alter table public.post_attachments enable row level security;

drop policy if exists attachments_read on public.post_attachments;
create policy attachments_read on public.post_attachments
  for select to anon, authenticated using (true);

drop policy if exists attachments_insert_own on public.post_attachments;
create policy attachments_insert_own on public.post_attachments
  for insert to authenticated
  with check (
    owner_id = (select auth.uid())
    and exists (
      select 1
      from public.posts p
      where p.id = post_id and p.user_id = (select auth.uid())
    )
  );

drop policy if exists attachments_delete_own on public.post_attachments;
create policy attachments_delete_own on public.post_attachments
  for delete to authenticated
  using (owner_id = (select auth.uid()));

drop policy if exists attachments_update_own on public.post_attachments;
create policy attachments_update_own on public.post_attachments
  for update to authenticated
  using (owner_id = (select auth.uid()))
  with check (owner_id = (select auth.uid()));

grant select on public.post_attachments to anon, authenticated;
grant insert, update, delete on public.post_attachments to authenticated;

-- Owner must own the parent post; max 10 attachments per post.
create or replace function public.guard_post_attachment()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_owner uuid;
begin
  select p.user_id into v_owner from public.posts p where p.id = new.post_id;
  if v_owner is null or v_owner <> new.owner_id then
    raise exception 'ATTACHMENT_OWNER_MISMATCH'
      using errcode = 'P0001';
  end if;
  return new;
end;
$function$;

drop trigger if exists post_attachments_owner_guard on public.post_attachments;
create trigger post_attachments_owner_guard
  before insert or update on public.post_attachments
  for each row execute function public.guard_post_attachment();

create or replace function public.limit_post_attachments()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_count integer;
begin
  select count(*) into v_count
  from public.post_attachments a
  where a.post_id = new.post_id;
  if v_count >= 10 then
    raise exception 'ATTACHMENT_LIMIT_REACHED'
      using errcode = 'P0001';
  end if;
  return new;
end;
$function$;

drop trigger if exists post_attachments_limit on public.post_attachments;
create trigger post_attachments_limit
  before insert on public.post_attachments
  for each row execute function public.limit_post_attachments();

-- Mirror legacy single-image rows once. `on conflict do nothing` uses the
-- partial unique index above, so a re-run never duplicates an attachment and
-- never touches the Storage object.
insert into public.post_attachments
  (post_id, owner_id, kind, storage_path, display_order)
select p.id, p.user_id, 'image', p.image_path, 0
from public.posts p
where p.image_path is not null
  and p.image_path <> ''
on conflict do nothing;

-- Cross-client attachment inserts (video/image/doc cards appear live).
do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'post_attachments'
  ) then
    execute 'alter publication supabase_realtime add table public.post_attachments';
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- 3. Read-only engagement aggregates for the public website
-- ---------------------------------------------------------------------------

create or replace view public.public_post_stats
with (security_invoker = false) as
select
  p.id as post_id,
  (
    select count(*) from public.post_reactions r
    where r.post_id = p.id and r.reaction = 'LIKE'
  ) as like_count,
  (
    select count(*) from public.post_reactions r
    where r.post_id = p.id and r.reaction = 'DISLIKE'
  ) as dislike_count,
  (
    select count(*) from public.post_ratings rt
    where rt.post_id = p.id
  ) as rating_count,
  (
    select round(avg(rt.stars)::numeric, 2) from public.post_ratings rt
    where rt.post_id = p.id
  ) as rating_average,
  (
    select count(*) from public.post_comments c
    where c.post_id = p.id
  ) as comment_count
from public.posts p;

comment on view public.public_post_stats is
  'Aggregate engagement (likes, dislikes, star average/count, comments) for '
  'one post. Read-only; personal reputation is never derived from this.';

revoke all on public.public_post_stats from public;
grant select on public.public_post_stats to anon, authenticated;

-- ---------------------------------------------------------------------------
-- 4. Reporting (post + user)
-- ---------------------------------------------------------------------------

create table if not exists public.post_reports (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.posts(id) on delete cascade,
  reporter_id uuid not null references public.profiles(id) on delete cascade,
  reason text not null check (
    reason in ('spam', 'harassment', 'misinformation', 'unsafe_media', 'other')
  ),
  details text,
  status text not null default 'open' check (
    status in ('open', 'reviewed', 'dismissed')
  ),
  created_at timestamptz not null default now(),
  constraint post_reports_details_chk check (
    details is null or char_length(details) <= 500
  ),
  constraint post_reports_one_per_reporter unique (post_id, reporter_id)
);

create table if not exists public.user_reports (
  id uuid primary key default gen_random_uuid(),
  reported_user_id uuid not null references public.profiles(id) on delete cascade,
  reporter_id uuid not null references public.profiles(id) on delete cascade,
  reason text not null check (
    reason in ('spam', 'harassment', 'impersonation', 'other')
  ),
  details text,
  status text not null default 'open' check (
    status in ('open', 'reviewed', 'dismissed')
  ),
  created_at timestamptz not null default now(),
  constraint user_reports_details_chk check (
    details is null or char_length(details) <= 500
  ),
  constraint user_reports_no_self check (reporter_id <> reported_user_id),
  constraint user_reports_one_per_reporter unique (reported_user_id, reporter_id)
);

alter table public.post_reports enable row level security;
alter table public.user_reports enable row level security;

drop policy if exists post_reports_insert_own on public.post_reports;
create policy post_reports_insert_own on public.post_reports
  for insert to authenticated
  with check (reporter_id = (select auth.uid()));

drop policy if exists post_reports_read_own on public.post_reports;
create policy post_reports_read_own on public.post_reports
  for select to authenticated
  using (reporter_id = (select auth.uid()));

drop policy if exists user_reports_insert_own on public.user_reports;
create policy user_reports_insert_own on public.user_reports
  for insert to authenticated
  with check (
    reporter_id = (select auth.uid())
    and reported_user_id <> (select auth.uid())
  );

drop policy if exists user_reports_read_own on public.user_reports;
create policy user_reports_read_own on public.user_reports
  for select to authenticated
  using (reporter_id = (select auth.uid()));

grant select, insert on public.post_reports to authenticated;
grant select, insert on public.user_reports to authenticated;

comment on table public.post_reports is
  'User-submitted post reports. Reporters see only their own rows; review is '
  'an owner/admin procedure documented in docs/moderation/p42-moderation.md.';

-- ---------------------------------------------------------------------------
-- 5. Basic board rate limits (abuse guard, not a moderation suite)
-- ---------------------------------------------------------------------------

create or replace function public.enforce_board_rate_limit()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_window interval := interval '10 minutes';
  v_limit integer;
  v_count integer;
begin
  if tg_table_name = 'posts' then
    v_limit := 10;
  elsif tg_table_name = 'post_comments' then
    v_limit := 30;
  else
    return new;
  end if;

  execute format(
    'select count(*) from public.%I where user_id = $1 and created_at > now() - $2',
    tg_table_name
  )
  into v_count
  using new.user_id, v_window;

  if v_count >= v_limit then
    raise exception 'RATE_LIMITED'
      using errcode = 'P0001',
            hint = format('Wait a few minutes before adding more (limit %s per 10 minutes).', v_limit);
  end if;
  return new;
end;
$function$;

drop trigger if exists posts_rate_limit on public.posts;
create trigger posts_rate_limit
  before insert on public.posts
  for each row execute function public.enforce_board_rate_limit();

drop trigger if exists post_comments_rate_limit on public.post_comments;
create trigger post_comments_rate_limit
  before insert on public.post_comments
  for each row execute function public.enforce_board_rate_limit();

-- ---------------------------------------------------------------------------
-- 6. Storage bucket limits for `post-media`
-- ---------------------------------------------------------------------------
-- The bucket already exists (observed public=true on the hosted project).
-- Limits are applied to the bucket itself so a client cannot bypass them:
-- 25 MiB per object, allowlisted public-post media only. Policies
-- (public read, owner-folder write/delete) are unchanged.

update storage.buckets
set file_size_limit = 26214400,
    allowed_mime_types = array[
      'image/jpeg',
      'image/png',
      'image/webp',
      'image/gif',
      'video/mp4',
      'video/webm',
      'audio/mpeg',
      'audio/mp4',
      'application/pdf',
      'text/plain',
      'text/csv',
      'application/zip',
      'application/msword',
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'application/vnd.ms-powerpoint',
      'application/vnd.openxmlformats-officedocument.presentationml.presentation'
    ]
where id = 'post-media';

commit;
