-- DRAFT / NOT APPLIED. Execute in staged review only, after schema and permission inventory.
-- Every exposed table gets explicit RLS. Tested policy needs two authenticated users + anon.
alter table public.profiles enable row level security;
alter table public.usernames enable row level security;
alter table public.stations enable row level security;
alter table public.trips enable row level security;
alter table public.trip_seats enable row level security;
alter table public.bookings enable row level security;
alter table public.booking_passengers enable row level security;
alter table public.booking_seats enable row level security;
alter table public.posts enable row level security;
alter table public.post_comments enable row level security;
alter table public.post_reactions enable row level security;
alter table public.post_ratings enable row level security;

create policy profiles_select_own on public.profiles for select to authenticated using ((select auth.uid()) = id);
create policy profiles_insert_own on public.profiles for insert to authenticated with check ((select auth.uid()) = id);
create policy profiles_update_own on public.profiles for update to authenticated using ((select auth.uid()) = id) with check ((select auth.uid()) = id);
-- Usernames are a public directory of *names* plus owner UUID; never join it to private email/phone/passenger fields.
create policy usernames_read on public.usernames for select to anon,authenticated using (true);
create policy usernames_claim on public.usernames for insert to authenticated with check ((select auth.uid()) = user_id);
create policy usernames_release on public.usernames for delete to authenticated using ((select auth.uid()) = user_id);
create policy stations_public_read on public.stations for select to anon,authenticated using (true);
create policy trips_public_read on public.trips for select to anon,authenticated using (active);
create policy seats_public_read on public.trip_seats for select to anon,authenticated using (true);
create policy bookings_owner_read on public.bookings for select to authenticated using ((select auth.uid()) = user_id);
create policy passengers_owner_read on public.booking_passengers for select to authenticated using (
  exists (select 1 from public.bookings b where b.id=booking_id and b.user_id=(select auth.uid())));
create policy booked_seats_owner_read on public.booking_seats for select to authenticated using (
  exists (select 1 from public.bookings b where b.id=booking_id and b.user_id=(select auth.uid())));
-- No direct booking INSERT/UPDATE/DELETE policy for authenticated or anon; only server service-role function.
create policy posts_read on public.posts for select to anon,authenticated using (true);
create policy posts_insert_own on public.posts for insert to authenticated with check ((select auth.uid()) = user_id);
create policy posts_edit_own on public.posts for update to authenticated using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy posts_delete_own on public.posts for delete to authenticated using ((select auth.uid()) = user_id);
create policy comments_read on public.post_comments for select to anon,authenticated using (true);
create policy comments_insert_own on public.post_comments for insert to authenticated with check ((select auth.uid()) = user_id);
create policy comments_delete_own on public.post_comments for delete to authenticated using ((select auth.uid()) = user_id);
create policy reactions_read on public.post_reactions for select to anon,authenticated using (true);
create policy reactions_insert_own on public.post_reactions for insert to authenticated with check ((select auth.uid()) = user_id);
create policy reactions_update_own on public.post_reactions for update to authenticated using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy reactions_delete_own on public.post_reactions for delete to authenticated using ((select auth.uid()) = user_id);
create policy ratings_read on public.post_ratings for select to anon,authenticated using (true);
create policy ratings_insert_own on public.post_ratings for insert to authenticated with check ((select auth.uid()) = user_id);
create policy ratings_update_own on public.post_ratings for update to authenticated using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy ratings_delete_own on public.post_ratings for delete to authenticated using ((select auth.uid()) = user_id);

-- Apply least privilege grants after verifying Data API exposure settings. Explicitly revoke client booking writes.
revoke insert,update,delete on public.bookings,public.booking_passengers,public.booking_seats,public.trip_seats from anon,authenticated;
-- Storage bucket must be created and separate storage.objects policies audited before enabling photo upload.
