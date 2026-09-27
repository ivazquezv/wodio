alter table public.profiles add column if not exists avatar_url text;

insert into storage.buckets (id,name,public,file_size_limit,allowed_mime_types)
values ('wodio-media','wodio-media',true,5242880,array['image/jpeg','image/png','image/webp'])
on conflict (id) do update set public=true,file_size_limit=5242880,allowed_mime_types=array['image/jpeg','image/png','image/webp'];

drop policy if exists "WodIO box admins can upload box logos" on storage.objects;
drop policy if exists "WodIO box admins can update box logos" on storage.objects;
drop policy if exists "WodIO box admins can delete box logos" on storage.objects;
drop policy if exists "WodIO users can upload own profile photo" on storage.objects;
drop policy if exists "WodIO users can update own profile photo" on storage.objects;
drop policy if exists "WodIO users can delete own profile photo" on storage.objects;

create policy "WodIO box admins can upload box logos" on storage.objects
for insert to authenticated
with check (
  bucket_id='wodio-media'
  and split_part(name,'/',1)='boxes'
  and split_part(name,'/',2)=(select private.current_box_id())::text
  and (select private.is_box_admin((select private.current_box_id())))
);

create policy "WodIO box admins can update box logos" on storage.objects
for update to authenticated
using (
  bucket_id='wodio-media'
  and split_part(name,'/',1)='boxes'
  and split_part(name,'/',2)=(select private.current_box_id())::text
  and (select private.is_box_admin((select private.current_box_id())))
)
with check (
  bucket_id='wodio-media'
  and split_part(name,'/',1)='boxes'
  and split_part(name,'/',2)=(select private.current_box_id())::text
  and (select private.is_box_admin((select private.current_box_id())))
);

create policy "WodIO box admins can delete box logos" on storage.objects
for delete to authenticated
using (
  bucket_id='wodio-media'
  and split_part(name,'/',1)='boxes'
  and split_part(name,'/',2)=(select private.current_box_id())::text
  and (select private.is_box_admin((select private.current_box_id())))
);

create policy "WodIO users can upload own profile photo" on storage.objects
for insert to authenticated
with check (
  bucket_id='wodio-media'
  and split_part(name,'/',1)='profiles'
  and split_part(name,'/',2)=(select auth.uid())::text
);

create policy "WodIO users can update own profile photo" on storage.objects
for update to authenticated
using (
  bucket_id='wodio-media'
  and split_part(name,'/',1)='profiles'
  and split_part(name,'/',2)=(select auth.uid())::text
)
with check (
  bucket_id='wodio-media'
  and split_part(name,'/',1)='profiles'
  and split_part(name,'/',2)=(select auth.uid())::text
);

create policy "WodIO users can delete own profile photo" on storage.objects
for delete to authenticated
using (
  bucket_id='wodio-media'
  and split_part(name,'/',1)='profiles'
  and split_part(name,'/',2)=(select auth.uid())::text
);

grant select, insert, update, delete on storage.objects to authenticated;
