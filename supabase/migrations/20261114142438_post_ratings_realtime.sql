-- Realtime publication for 1-5 star ratings (R-07, 2026-11-14).
--
-- Observed before this migration: `supabase_realtime` covered `public.posts`,
-- `public.post_comments` and `public.post_reactions` only, so the Journey
-- Board updated comments/reactions live but a star rating cast on another
-- client never reached a card without a manual refresh.
--
-- Additive and idempotent: the table is added only when absent, and no row is
-- read, written or deleted. Reverse with
-- `alter publication supabase_realtime drop table public.post_ratings`.
--
-- `post_ratings` has a composite primary key (`post_id`, `user_id`) and the
-- default replica identity, so DELETE payloads still carry `post_id` and the
-- shell can route the event to the owning card. RLS (`ratings_read`,
-- `ratings_insert_own`, `ratings_update_own`, `ratings_delete_own`) is
-- unchanged: realtime only mirrors rows the subscriber is already allowed to
-- read, and no policy is widened to make delivery work.

do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'post_ratings'
  ) then
    alter publication supabase_realtime add table public.post_ratings;
  end if;
end $$;
