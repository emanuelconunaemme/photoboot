-- Storage policies in the original schema only covered SELECT + INSERT.
-- Editing an event re-uploads a background to the same path which Supabase
-- handles as UPDATE on storage.objects → RLS denies without an UPDATE policy.
-- Also adds DELETE so strip cleanup (StripService.delete on the iPad) actually
-- removes the composite files instead of orphaning them.

-- Templates (open writes, matching the existing INSERT policy)
create policy "owner updates templates bucket"
  on storage.objects for update to authenticated
  using (bucket_id = 'templates')
  with check (bucket_id = 'templates');

create policy "owner deletes templates bucket"
  on storage.objects for delete to authenticated
  using (bucket_id = 'templates');

-- Photos (event-scoped via path prefix, matching the existing pattern)
create policy "owner updates photos bucket"
  on storage.objects for update to authenticated
  using (
    bucket_id = 'photos'
    and exists (
      select 1 from public.events e
      where e.owner_id = auth.uid()
        and e.id = (storage.foldername(storage.objects.name))[1]::uuid
    )
  )
  with check (
    bucket_id = 'photos'
    and exists (
      select 1 from public.events e
      where e.owner_id = auth.uid()
        and e.id = (storage.foldername(storage.objects.name))[1]::uuid
    )
  );

create policy "owner deletes photos bucket"
  on storage.objects for delete to authenticated
  using (
    bucket_id = 'photos'
    and exists (
      select 1 from public.events e
      where e.owner_id = auth.uid()
        and e.id = (storage.foldername(storage.objects.name))[1]::uuid
    )
  );

-- Composites
create policy "owner updates composites bucket"
  on storage.objects for update to authenticated
  using (
    bucket_id = 'composites'
    and exists (
      select 1 from public.events e
      where e.owner_id = auth.uid()
        and e.id = (storage.foldername(storage.objects.name))[1]::uuid
    )
  )
  with check (
    bucket_id = 'composites'
    and exists (
      select 1 from public.events e
      where e.owner_id = auth.uid()
        and e.id = (storage.foldername(storage.objects.name))[1]::uuid
    )
  );

create policy "owner deletes composites bucket"
  on storage.objects for delete to authenticated
  using (
    bucket_id = 'composites'
    and exists (
      select 1 from public.events e
      where e.owner_id = auth.uid()
        and e.id = (storage.foldername(storage.objects.name))[1]::uuid
    )
  );
