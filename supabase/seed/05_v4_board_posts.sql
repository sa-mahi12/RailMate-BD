-- P19 DRAFT — Journey Board demo posts (V4 seed prep).
-- STATUS: DRAFT / NOT APPLIED. DO NOT apply to any hosted project as-is.
-- Coordinator adapts and applies under the P33 QA/apply step only.
--
-- DEMONSTRATION ONLY — synthetic travel tips, NOT real timetable,
-- fare, railway-service or operational information.
--
-- Source of truth (content): pack data file
--   data/journey_board_seed_v4.json  (40 entries, verbatim bodies below).
-- Schema seam (columns): supabase/migrations/20260927000001_initial_schema.sql
--   public.posts(id uuid pk, user_id uuid NOT NULL ref profiles(id),
--     body text 1..2000, image_path text NULL, created_at timestamptz).
-- App seam (write path): lib/features/board/post/post.dart
--   Post.toInsertMap() -> {user_id, body, [image_path]} (server sets id/created_at).
--
-- IDEMPOTENCY / SAFETY DESIGN
-- - This file writes ONLY to a TEMPORARY staging table inside one
--   transaction that ends with ROLLBACK, so executing it changes nothing.
-- - There is deliberately NO live `insert into public.posts` statement:
--   the final apply is a commented guarded template for P33 (see §4).
-- - No credentials, no user data, no RLS change, no lib edits.
-- - Re-runnable: temp staging is fresh per session; seed_key is its PK.
--
-- DEVIATIONS FROM THE PACK JSON SOURCE OF TRUTH (bodies kept verbatim)
-- - D1 timestamps: JSON relative_hours_ago spans 0.25h..96h (~last 4 days)
--   with repeated offsets, NOT a 14-day spread. Draft preserves the JSON
--   values verbatim; an optional stagger snippet is provided (§5) if the
--   coordinator wants a wider demo spread at apply time.
-- - D2 images: JSON image_asset values (demo_station_card_*.png) are local
--   asset labels, NOT Supabase Storage object paths. Draft stages them as
--   labels and maps image_path to NULL; real bytes go to the protected
--   bucket with Storage policy review in P33.
-- - D3 authors: JSON author_alias ("... Demo") is a display label, NOT an
--   auth user. posts.user_id is NOT NULL FK to profiles(id), so the
--   coordinator must bind ONE demo/seed profile id at apply time (§4).
-- - D4 idempotency: the applied posts table has no seed_key/is_demo column
--   (worker must not alter schema), so the P33 apply dedupes on body
--   equality via WHERE NOT EXISTS (see template).
--
-- CONTENT-SAFETY NOTES (reviewed 2026-10-02, Worker E)
-- - 40 posts, all English, all generic travel/demo-hygiene tips.
-- - No real persons (aliases are openly fictional "... Demo" labels).
-- - No phone numbers, emails, addresses, credentials or API keys
--   (v4-post-23 explicitly warns NEVER to share an OpenRouter key).
-- - No hate, politics, religion, or official/operational claims; several
--   posts self-declare demo/synthetic status (v4-post-22/28/29/32).
-- - Longest body < 300 chars (limit 2000); no lines exceed 500 chars.

begin;

-- §1 Staging table: session-local, dropped on commit; ROLLBACK below
-- guarantees zero durable writes even if this file is executed.
create temporary table v4_board_seed_stage (
  seed_key text primary key,
  author_alias text not null,
  body text not null check (char_length(body) between 1 and 2000),
  relative_hours_ago numeric not null check (relative_hours_ago >= 0),
  image_asset text
) on commit drop;

-- §2 Staged rows: bodies verbatim from data/journey_board_seed_v4.json.
insert into v4_board_seed_stage
  (seed_key, author_alias, body, relative_hours_ago, image_asset)
values
  ('v4-post-01', 'Ayesha Demo', 'Morning departures can get busy around station entrances. Arrive early enough to find your platform without rushing.', 0.25, 'demo_station_card_1.png'),
  ('v4-post-02', 'Rafi Demo', 'When booking for family members, review every passenger name and seat assignment together before confirming.', 1, null),
  ('v4-post-03', 'Nabila Demo', 'Keep your ticket reference somewhere easy to reach before you enter the station.', 2, null),
  ('v4-post-04', 'Tanvir Demo', 'For an overnight journey, carry water, keep valuables close, and set a reminder before your stop.', 3, null),
  ('v4-post-05', 'Samiha Demo', 'If rain is expected, give yourself extra travel time to reach the station and protect electronics.', 5, 'demo_station_card_5.png'),
  ('v4-post-06', 'Farhan Demo', 'Agree on a simple meeting point before travelling with a group so nobody gets separated near the exit.', 8, null),
  ('v4-post-07', 'Mahi Demo', 'Use the seat map to keep children or elderly family members close to the rest of your group.', 12, null),
  ('v4-post-08', 'Arif Demo', 'Double-check your journey date before confirming. A correct route on the wrong day is still the wrong booking.', 18, null),
  ('v4-post-09', 'Jannat Demo', 'Take a screenshot of important travel information only as a backup; use the current booking screen for the latest demo state.', 24, 'demo_station_card_1.png'),
  ('v4-post-10', 'Raihan Demo', 'Keep luggage labels simple and avoid placing sensitive personal details on the outside of a bag.', 30, null),
  ('v4-post-11', 'Ayesha Demo', 'Before a long trip, charge your phone and carry a small power bank if you have one.', 42, null),
  ('v4-post-12', 'Rafi Demo', 'Station Guide is useful when you want a quick map view before leaving for the station.', 55, null),
  ('v4-post-13', 'Nabila Demo', 'Choose a seat only after everyone in your group confirms the passenger list.', 72, 'demo_station_card_5.png'),
  ('v4-post-14', 'Tanvir Demo', 'If a seat becomes unavailable while you are booking, return to the seat map and choose another one rather than repeatedly retrying.', 96, null),
  ('v4-post-15', 'Samiha Demo', 'Use Journey Board for practical station and travel tips rather than sharing private booking details.', 0.25, null),
  ('v4-post-16', 'Farhan Demo', 'Keep your QR ticket brightness high enough to scan clearly during a demonstration.', 1, null),
  ('v4-post-17', 'Mahi Demo', 'If you cancel a demo booking, revisit the seat map to see the released seat become available again.', 2, 'demo_station_card_1.png'),
  ('v4-post-18', 'Arif Demo', 'A short checklist before leaving home: ticket, phone, charger, water, wallet, and any necessary medicine.', 3, null),
  ('v4-post-19', 'Jannat Demo', 'Travelling with luggage is easier when your group agrees who is responsible for each bag.', 5, null),
  ('v4-post-20', 'Raihan Demo', 'Use recent searches to quickly repeat a route you checked earlier without re-entering both stations.', 8, null),
  ('v4-post-21', 'Ayesha Demo', 'On a busy day, consider a service with better seat availability even if it departs a little later.', 12, 'demo_station_card_5.png'),
  ('v4-post-22', 'Rafi Demo', 'Smart demo ranking considers fare, duration, departure time and remaining demo seat availability.', 18, null),
  ('v4-post-23', 'Nabila Demo', 'Do not share an OpenRouter API key inside a Journey Board post. Keep it only in AI Settings.', 24, null),
  ('v4-post-24', 'Tanvir Demo', 'After uploading a station photo, check the preview before publishing your Journey Board post.', 30, null),
  ('v4-post-25', 'Samiha Demo', 'If your connection drops during a search, use Retry rather than assuming there are no trains.', 42, 'demo_station_card_1.png'),
  ('v4-post-26', 'Farhan Demo', 'Check the Bookings tab after confirmation to make sure the new demonstration booking appears there.', 55, null),
  ('v4-post-27', 'Mahi Demo', 'Cancelled demonstration tickets are kept in history so you can explain the full lifecycle during a demo.', 72, null),
  ('v4-post-28', 'Arif Demo', 'Ratings are useful for demonstrating realtime database interaction; they are not official railway service scores.', 96, null),
  ('v4-post-29', 'Jannat Demo', 'Try searching the same corridor on two different dates to see how synthetic seat occupancy changes.', 0.25, 'demo_station_card_5.png'),
  ('v4-post-30', 'Raihan Demo', 'Popular demo routes are shortcuts; you can always choose stations manually instead.', 1, null),
  ('v4-post-31', 'Ayesha Demo', 'Use the Profile tab to verify which account is currently signed in before showing account-specific bookings.', 2, null),
  ('v4-post-32', 'Rafi Demo', 'During a class presentation, explain that fares and schedules are synthetic demonstration data.', 3, null),
  ('v4-post-33', 'Nabila Demo', 'Real-time comments are easiest to demonstrate with two phones or one phone plus another client session.', 5, 'demo_station_card_1.png'),
  ('v4-post-34', 'Tanvir Demo', 'If a booking conflict occurs, RailMate should show an honest seat-unavailable error instead of creating a partial booking.', 8, null),
  ('v4-post-35', 'Samiha Demo', 'A good demo sequence is search, seats, passengers, payment simulation, ticket, history, then cancellation.', 12, null),
  ('v4-post-36', 'Farhan Demo', 'Use the map inside Station Guide to explain the embedded web requirement without leaving the app.', 18, null),
  ('v4-post-37', 'Mahi Demo', 'AI Improve Wording should only run after the user explicitly asks for it and provides their own key.', 24, 'demo_station_card_5.png'),
  ('v4-post-38', 'Arif Demo', 'An empty Board is not a good presentation state, so sample tips should exist before the viva.', 30, null),
  ('v4-post-39', 'Jannat Demo', 'Small interface animations should help the user understand state changes, not slow the booking process.', 42, null),
  ('v4-post-40', 'Raihan Demo', 'A release APK is better for screenshots because it removes the debug banner and better represents the final app.', 55, null)
on conflict (seed_key) do nothing;

-- §3 Self-checks (read-only; safe to run — transaction rolls back below).
-- Expect: post_count = 40, image_posts = 10, max_body_len <= 2000,
-- max_hours_ago = 96, dup_offsets > 0 documents deviation D1.
select count(*) as post_count from v4_board_seed_stage;
select count(*) as image_posts from v4_board_seed_stage where image_asset is not null;
select max(char_length(body)) as max_body_len from v4_board_seed_stage;
select max(relative_hours_ago) as max_hours_ago from v4_board_seed_stage;
select relative_hours_ago, count(*) as n
  from v4_board_seed_stage
  group by relative_hours_ago having count(*) > 1
  order by relative_hours_ago;

-- §4 P33 APPLY TEMPLATE (commented — coordinator only, staging review first).
-- Prerequisites: a demo/seed profile id exists (auth user + public.profiles
-- row, created via the owner/admin process — NEVER committed here); Storage
-- bucket policy for post images reviewed; backup taken.
-- The guarded insert below is idempotent on body equality (no seed_key
-- column exists on public.posts) and sets created_at spread over the last
-- ~4 days per the JSON offsets. image_path stays NULL until real image
-- bytes are uploaded (deviation D2).
--
-- -- :demo_user_id := '<seed-profile-uuid>';  -- coordinator fills in
-- insert into public.posts (user_id, body, image_path, created_at)
-- select
--   :demo_user_id,
--   s.body,
--   null,
--   now() - (s.relative_hours_ago || ' hours')::interval
-- from v4_board_seed_stage s
-- where not exists (
--   select 1 from public.posts p where p.body = s.body
-- );

-- §5 OPTIONAL 14-day stagger (commented alternative for §4 created_at).
-- If the viva demo wants the "varied over last 14 days" spread instead of
-- the verbatim 0.25h..96h offsets, the coordinator may replace the
-- created_at expression with:
--   now() - ((row_number() over (order by s.seed_key) * 8) || ' hours')::interval
-- which spreads 40 posts ~8h apart over ~13.3 days, newest seed_key first
-- reversed as needed. This DEVIATES from the JSON offsets — record the
-- choice in DECISIONS.md.

-- §6 ENGAGEMENT SEED PLAN (comments/reactions/ratings — P33 follow-up).
-- Post ids are unknown until §4 runs, so engagement is specified here as a
-- distribution for the coordinator to apply with body-matched lookups
-- (insert ... select id from public.posts where body = '...'), NOT as live
-- statements. Suggested distribution (supports scenario matrix: comments,
-- rating, reactions, pagination second page):
-- - HIGH (image posts, newest): v4-post-01: 6 LIKE / 1 DISLIKE, 5 ratings
--   (5,4,5,4,4), 3 comments; v4-post-09: 4 LIKE / 1 DISLIKE, 4 ratings
--   (5,4,4,3), 2 comments; v4-post-17: 3 LIKE, 3 ratings (5,4,5), 2 comments.
-- - MEDIUM: v4-post-05: 4 LIKE, 3 ratings (4,4,5), 1 comment;
--   v4-post-23 (BYOK hygiene): 5 LIKE, 4 ratings (5,5,4,4), 2 comments;
--   v4-post-28 (honesty note): 4 LIKE, 3 ratings (5,4,4), 1 comment.
-- - LOW (long tail): v4-post-14/22/32/34: 1-2 LIKE each, 1-2 ratings each,
--   0-1 comments each. All other posts: no engagement (honest empty state
--   for pagination page 2+ and zero-count UI paths).
-- Guarded templates (coordinator adapts; second+ demo users required for
-- multi-user reactions — one row per (post_id, user_id)):
-- -- insert into public.post_reactions (post_id, user_id, reaction)
-- -- select p.id, :demo_user_b, 'LIKE' from public.posts p
-- -- where p.body = '<verbatim body of v4-post-01>'
-- -- on conflict (post_id, user_id) do nothing;
-- -- insert into public.post_ratings (post_id, user_id, stars)
-- -- select p.id, :demo_user_b, 5 from public.posts p
-- -- where p.body = '<verbatim body of v4-post-01>'
-- -- on conflict (post_id, user_id) do nothing;
-- -- insert into public.post_comments (post_id, user_id, body)
-- -- select p.id, :demo_user_b, '<safe generic demo comment>'
-- -- from public.posts p
-- -- where p.body = '<verbatim body of v4-post-01>'
-- --   and not exists (select 1 from public.post_comments c
-- --                   where c.post_id = p.id and c.body = '<same comment>');
-- Comment bodies at apply time must follow the same safety rules as posts
-- (English, generic, no real persons/phones/claims) and stay within 500
-- chars (post_comments body check 1..500).

rollback;
