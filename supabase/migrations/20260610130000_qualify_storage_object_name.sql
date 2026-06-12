-- The previous fix was bitten by column ambiguity: unqualified `name` inside
-- the EXISTS subquery resolved to events.name (which exists), not to the
-- storage object's name as intended. Qualifying with the schema-qualified
-- table name removes the ambiguity.

drop policy if exists "owner reads photos bucket" on storage.objects;
drop policy if exists "owner writes photos bucket" on storage.objects;
drop policy if exists "owner reads composites bucket" on storage.objects;
drop policy if exists "owner writes composites bucket" on storage.objects;

create policy "owner reads photos bucket"
  on storage.objects for select to authenticated
  using (
    bucket_id = 'photos'
    and exists (
      select 1 from public.events e
      where e.owner_id = auth.uid()
        and e.id = (storage.foldername(storage.objects.name))[1]::uuid
    )
  );

create policy "owner writes photos bucket"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'photos'
    and exists (
      select 1 from public.events e
      where e.owner_id = auth.uid()
        and e.id = (storage.foldername(storage.objects.name))[1]::uuid
    )
  );

create policy "owner reads composites bucket"
  on storage.objects for select to authenticated
  using (
    bucket_id = 'composites'
    and exists (
      select 1 from public.events e
      where e.owner_id = auth.uid()
        and e.id = (storage.foldername(storage.objects.name))[1]::uuid
    )
  );

create policy "owner writes composites bucket"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'composites'
    and exists (
      select 1 from public.events e
      where e.owner_id = auth.uid()
        and e.id = (storage.foldername(storage.objects.name))[1]::uuid
    )
  );
