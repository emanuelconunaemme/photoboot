-- Phase 0 schema: events, photos, deliveries, contacts, gphotos_credentials.
-- Async delivery (triggers calling Edge Functions) lands in a Phase 2 migration —
-- this file only creates the data model + RLS so we can ship the upload spine first.

create extension if not exists pgcrypto;

-- ────────────────────────────────────────────────────────────────────
-- events
-- ────────────────────────────────────────────────────────────────────
create table public.events (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users (id) on delete cascade,
  name text not null,
  slug text not null,
  status text not null default 'draft' check (status in ('draft', 'live', 'archived')),
  template jsonb not null default '{}'::jsonb,
  gphotos_album_id text,
  gphotos_share_url text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (owner_id, slug)
);

create index events_owner_status_idx on public.events (owner_id, status);

-- ────────────────────────────────────────────────────────────────────
-- photos
-- ────────────────────────────────────────────────────────────────────
create table public.photos (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.events (id) on delete cascade,
  status text not null default 'uploading' check (status in ('uploading', 'ready', 'failed')),
  capture_mode text not null check (capture_mode in ('single', 'strip-4')),
  storage_path text,         -- supabase storage key for the raw capture(s)
  composite_path text,       -- final composed image for strip mode
  gphotos_media_id text,
  width int,
  height int,
  error text,
  taken_at timestamptz not null default now(),
  ready_at timestamptz
);

create index photos_event_taken_idx on public.photos (event_id, taken_at desc);
create index photos_status_idx on public.photos (status) where status <> 'ready';

-- ────────────────────────────────────────────────────────────────────
-- deliveries (SMS + email fan-out queue)
-- ────────────────────────────────────────────────────────────────────
create table public.deliveries (
  id uuid primary key default gen_random_uuid(),
  photo_id uuid not null references public.photos (id) on delete cascade,
  channel text not null check (channel in ('sms', 'email')),
  recipient text not null,
  status text not null default 'pending' check (status in ('pending', 'sent', 'failed')),
  attempts int not null default 0,
  error text,
  sent_at timestamptz,
  created_at timestamptz not null default now()
);

-- Hot path index for the worker: pending deliveries whose photo is ready
create index deliveries_pending_idx on public.deliveries (photo_id, status) where status = 'pending';

-- ────────────────────────────────────────────────────────────────────
-- contacts (preloaded CSV for autocomplete on iPad)
-- ────────────────────────────────────────────────────────────────────
create table public.contacts (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.events (id) on delete cascade,
  name text,
  email text,
  phone text,
  source text not null default 'csv' check (source in ('csv', 'manual'))
);

create index contacts_event_idx on public.contacts (event_id);

-- ────────────────────────────────────────────────────────────────────
-- gphotos_credentials (one row per user — single user for now)
-- ────────────────────────────────────────────────────────────────────
create table public.gphotos_credentials (
  owner_id uuid primary key references auth.users (id) on delete cascade,
  access_token text not null,
  refresh_token text not null,
  expires_at timestamptz not null,
  scope text,
  updated_at timestamptz not null default now()
);

-- ────────────────────────────────────────────────────────────────────
-- updated_at maintenance
-- ────────────────────────────────────────────────────────────────────
create or replace function public.set_updated_at() returns trigger
language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger events_set_updated_at
  before update on public.events
  for each row execute function public.set_updated_at();

create trigger gphotos_credentials_set_updated_at
  before update on public.gphotos_credentials
  for each row execute function public.set_updated_at();

-- ────────────────────────────────────────────────────────────────────
-- ready_at maintenance — set the first time status flips to 'ready'
-- ────────────────────────────────────────────────────────────────────
create or replace function public.set_photo_ready_at() returns trigger
language plpgsql as $$
begin
  if new.status = 'ready' and (old.status is null or old.status <> 'ready') then
    new.ready_at = coalesce(new.ready_at, now());
  end if;
  return new;
end;
$$;

create trigger photos_set_ready_at
  before update on public.photos
  for each row execute function public.set_photo_ready_at();

-- ────────────────────────────────────────────────────────────────────
-- RLS — single user, scope by owner_id via events join
-- ────────────────────────────────────────────────────────────────────
alter table public.events enable row level security;
alter table public.photos enable row level security;
alter table public.deliveries enable row level security;
alter table public.contacts enable row level security;
alter table public.gphotos_credentials enable row level security;

create policy "owner manages own events"
  on public.events for all to authenticated
  using (owner_id = auth.uid())
  with check (owner_id = auth.uid());

create policy "owner manages photos via event"
  on public.photos for all to authenticated
  using (exists (select 1 from public.events e where e.id = event_id and e.owner_id = auth.uid()))
  with check (exists (select 1 from public.events e where e.id = event_id and e.owner_id = auth.uid()));

create policy "owner manages deliveries via photo"
  on public.deliveries for all to authenticated
  using (exists (
    select 1 from public.photos p
    join public.events e on e.id = p.event_id
    where p.id = photo_id and e.owner_id = auth.uid()
  ))
  with check (exists (
    select 1 from public.photos p
    join public.events e on e.id = p.event_id
    where p.id = photo_id and e.owner_id = auth.uid()
  ));

create policy "owner manages contacts via event"
  on public.contacts for all to authenticated
  using (exists (select 1 from public.events e where e.id = event_id and e.owner_id = auth.uid()))
  with check (exists (select 1 from public.events e where e.id = event_id and e.owner_id = auth.uid()));

create policy "owner manages own gphotos credentials"
  on public.gphotos_credentials for all to authenticated
  using (owner_id = auth.uid())
  with check (owner_id = auth.uid());

-- ────────────────────────────────────────────────────────────────────
-- Storage buckets
-- ────────────────────────────────────────────────────────────────────
insert into storage.buckets (id, name, public) values
  ('photos', 'photos', false),
  ('composites', 'composites', false),
  ('templates', 'templates', true)
on conflict (id) do nothing;

-- Photos bucket: owner-only via event ownership
create policy "owner reads photos bucket"
  on storage.objects for select to authenticated
  using (
    bucket_id = 'photos'
    and exists (
      select 1 from public.events e
      where e.owner_id = auth.uid()
        and split_part(name, '/', 1) = e.id::text
    )
  );

create policy "owner writes photos bucket"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'photos'
    and exists (
      select 1 from public.events e
      where e.owner_id = auth.uid()
        and split_part(name, '/', 1) = e.id::text
    )
  );

-- Composites bucket: same scoping
create policy "owner reads composites bucket"
  on storage.objects for select to authenticated
  using (
    bucket_id = 'composites'
    and exists (
      select 1 from public.events e
      where e.owner_id = auth.uid()
        and split_part(name, '/', 1) = e.id::text
    )
  );

create policy "owner writes composites bucket"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'composites'
    and exists (
      select 1 from public.events e
      where e.owner_id = auth.uid()
        and split_part(name, '/', 1) = e.id::text
    )
  );

-- Templates bucket is public-read (logos, backgrounds served to iPad)
create policy "anyone reads templates bucket"
  on storage.objects for select to anon, authenticated
  using (bucket_id = 'templates');

create policy "owner writes templates bucket"
  on storage.objects for insert to authenticated
  with check (bucket_id = 'templates');
