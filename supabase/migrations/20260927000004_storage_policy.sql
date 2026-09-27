-- DRAFT / NOT APPLIED. Must first create bucket `post-media` in hosted Supabase storage.
-- Keep files path-prefix owned by authenticated user, e.g. '<uid>/<random-uuid>.jpg'.
create policy post_media_read on storage.objects for select to anon,authenticated
  using (bucket_id='post-media');
create policy post_media_upload_own on storage.objects for insert to authenticated
  with check (bucket_id='post-media' and (storage.foldername(name))[1] = (select auth.uid())::text);
create policy post_media_delete_own on storage.objects for delete to authenticated
  using (bucket_id='post-media' and (storage.foldername(name))[1] = (select auth.uid())::text);
-- Set bucket size/MIME constraints through dashboard and verify against actual client upload behavior.
-- Do not open up passenger/booking information through the public media bucket.
