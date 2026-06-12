-- Storage RLS was comparing split_part(name, '/', 1) (string) to events.id::text
-- (lowercase string from Postgres). Swift's UUID.uuidString returns UPPERCASE,
-- which broke the comparison and rejected all uploads from the iPad.
--
-- Rewriting to cast the path segment to UUID and compare to events.id directly —
-- case-insensitive by virtue of being a UUID-typed compare. Falls back to RLS
-- denial if the path's first segment isn't a valid UUID, which is the desired
-- behavior anyway.

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
        and e.id = (storage.foldername(name))[1]::uuid
    )
  );

create policy "owner writes photos bucket"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'photos'
    and exists (
      select 1 from public.events e
      where e.owner_id = auth.uid()
        and e.id = (storage.foldername(name))[1]::uuid
    )
  );

create policy "owner reads composites bucket"
  on storage.objects for select to authenticated
  using (
    bucket_id = 'composites'
    and exists (
      select 1 from public.events e
      where e.owner_id = auth.uid()
        and e.id = (storage.foldername(name))[1]::uuid
    )
  );

create policy "owner writes composites bucket"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'composites'
    and exists (
      select 1 from public.events e
      where e.owner_id = auth.uid()
        and e.id = (storage.foldername(name))[1]::uuid
    )
  );
