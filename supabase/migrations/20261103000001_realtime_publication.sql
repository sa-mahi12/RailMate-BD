-- Realtime publication for the Journey Board (teacher final gate, 2026-11-03).
--
-- Observed on the hosted project before this migration: `pg_publication_tables`
-- listed ONLY the internal `realtime.messages_*` tables, so Postgres Changes
-- delivered nothing for `public.posts` / `public.post_comments` /
-- `public.post_reactions`. The app's channels were therefore silent even
-- though the client code subscribed correctly.
--
-- Additive and idempotent: tables are added only when absent, and no row is
-- read, written or deleted. Reverse with `alter publication supabase_realtime
-- drop table public.<name>` if needed.
--
-- Apply order matters for production: this is a schema/config change, so it
-- is committed here (repo is the source of truth) and applied hosted via the
-- dashboard/SQL editor with owner approval.

do $$
declare
  t text;
begin
  foreach t in array array[
    'public.posts',
    'public.post_comments',
    'public.post_reactions'
  ] loop
    if not exists (
      select 1
      from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname || '.' || tablename = t
    ) then
      execute format('alter publication supabase_realtime add table %s', t);
    end if;
  end loop;
end $$;
