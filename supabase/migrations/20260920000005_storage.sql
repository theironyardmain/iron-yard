-- The Iron Yard — Storage buckets and policies (brain.md §6.5, §6.6)

-- ---------------------------------------------------------------------------
-- Buckets
-- ---------------------------------------------------------------------------
-- Receipts are private: they are financial records naming a member.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'receipts',
  'receipts',
  false,
  5242880,  -- 5 MB
  array['image/jpeg', 'image/png', 'image/webp', 'application/pdf']
)
on conflict (id) do nothing;

-- Exercise images are public: they are generic instructional content, and a
-- public bucket lets the client cache them by URL for offline viewing without
-- a signed-URL round trip (brain.md §6.6).
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'exercise-images',
  'exercise-images',
  true,
  2097152,  -- 2 MB
  array['image/jpeg', 'image/png', 'image/webp']
)
on conflict (id) do nothing;

-- Profile photos are public for the same caching reason; they carry no more
-- information than the member list a signed-in user can already read.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'profile-photos',
  'profile-photos',
  true,
  2097152,  -- 2 MB
  array['image/jpeg', 'image/png', 'image/webp']
)
on conflict (id) do nothing;

-- ---------------------------------------------------------------------------
-- receipts — admin writes, member reads their own
-- ---------------------------------------------------------------------------
-- Path convention: receipts/<member_id>/<payment_id>.<ext>
-- The first path segment is the member id, so ownership is checked without a
-- join back to payments.
drop policy if exists receipts_admin_all on storage.objects;
create policy receipts_admin_all on storage.objects
  for all to authenticated
  using (bucket_id = 'receipts' and public.is_admin())
  with check (bucket_id = 'receipts' and public.is_admin());

drop policy if exists receipts_member_read on storage.objects;
create policy receipts_member_read on storage.objects
  for select to authenticated
  using (
    bucket_id = 'receipts'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

-- ---------------------------------------------------------------------------
-- exercise-images — staff write, anyone reads
-- ---------------------------------------------------------------------------
drop policy if exists exercise_images_staff_write on storage.objects;
create policy exercise_images_staff_write on storage.objects
  for all to authenticated
  using (bucket_id = 'exercise-images' and public.is_staff())
  with check (bucket_id = 'exercise-images' and public.is_staff());

drop policy if exists exercise_images_read on storage.objects;
create policy exercise_images_read on storage.objects
  for select to public
  using (bucket_id = 'exercise-images');

-- ---------------------------------------------------------------------------
-- profile-photos — own photo, or staff
-- ---------------------------------------------------------------------------
-- Path convention: profile-photos/<profile_id>.<ext>
drop policy if exists profile_photos_write on storage.objects;
create policy profile_photos_write on storage.objects
  for all to authenticated
  using (
    bucket_id = 'profile-photos'
    and (
      public.is_staff()
      or split_part(name, '.', 1) = auth.uid()::text
    )
  )
  with check (
    bucket_id = 'profile-photos'
    and (
      public.is_staff()
      or split_part(name, '.', 1) = auth.uid()::text
    )
  );

drop policy if exists profile_photos_read on storage.objects;
create policy profile_photos_read on storage.objects
  for select to public
  using (bucket_id = 'profile-photos');
