-- Consolidated schema reset.
--
-- This migration is idempotent: drops anything we previously created (tables,
-- policies, storage buckets and the objects inside them) then rebuilds the
-- final strip-centric schema from scratch. Earlier migrations were superseded
-- because they conflicted with each other after a partial-apply.
--
-- WARNING: this drops all data in events/photos/strips/strip_photos/deliveries/
-- contacts/gphotos_credentials. `auth.users` is left untouched.
--
-- Storage objects from previous tests are NOT cleared here — Supabase blocks
-- direct deletes on storage.objects from SQL. Existing objects become
-- orphaned (no row in events/photos/strips references them) and inaccessible
-- via the app. Clean them up via the Supabase dashboard → Storage if you care.

-- ────────────────────────────────────────────────────────────────────
-- Drop everything we own
-- ────────────────────────────────────────────────────────────────────

-- Storage policies first (depend on tables that may be dropped)
drop policy if exists "owner reads photos bucket" on storage.objects;
drop policy if exists "owner writes photos bucket" on storage.objects;
drop policy if exists "owner reads composites bucket" on storage.objects;
drop policy if exists "owner writes composites bucket" on storage.objects;
drop policy if exists "anyone reads templates bucket" on storage.objects;
drop policy if exists "owner writes templates bucket" on storage.objects;

-- Legacy delivery policy that referenced photo_id (may still exist after the
-- partial apply that triggered this reset)
drop policy if exists "owner manages deliveries via photo" on public.deliveries;

-- Drop our tables (cascade catches FKs, policies, triggers)
drop table if exists public.deliveries cascade;
drop table if exists public.strip_photos cascade;
drop table if exists public.strips cascade;
drop table if exists public.contacts cascade;
drop table if exists public.gphotos_credentials cascade;
drop table if exists public.photos cascade;
drop table if exists public.events cascade;

-- Storage objects + buckets: cannot delete from these tables via SQL on cloud
-- (Supabase guards storage.objects and storage.buckets). Buckets get recreated
-- with `on conflict do nothing` below so this migration is idempotent — leftover
-- objects from a previous run become orphans (RLS hides them) but stay billable
-- until cleaned via the dashboard.

-- ────────────────────────────────────────────────────────────────────
-- Rebuild — strip-centric schema
-- ────────────────────────────────────────────────────────────────────

create extension if not exists pgcrypto;

-- Events
create table public.events (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users (id) on delete cascade,
  name text not null,
  slug text not null,
  status text not null default 'draft' check (status in ('draft', 'live', 'archived')),
  template jsonb not null default '{}'::jsonb,
  description text,
  event_date date,
  primary_color text not null default '#E1306C' check (primary_color ~ '^#[0-9a-fA-F]{6}$'),
  secondary_color text not null default '#833AB4' check (secondary_color ~ '^#[0-9a-fA-F]{6}$'),
  shots_per_strip int not null default 3 check (shots_per_strip between 1 and 6),
  invite_image_path text,
  gphotos_album_id text,
  gphotos_share_url text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (owner_id, slug)
);
create index events_owner_status_idx on public.events (owner_id, status);

-- Raw photos
create table public.photos (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.events (id) on delete cascade,
  status text not null default 'uploading' check (status in ('uploading', 'ready', 'failed')),
  capture_mode text not null check (capture_mode in ('single', 'strip', 'strip-4')),
  storage_path text,
  composite_path text,
  gphotos_media_id text,
  width int,
  height int,
  error text,
  taken_at timestamptz not null default now(),
  ready_at timestamptz
);
create index photos_event_taken_idx on public.photos (event_id, taken_at desc);
create index photos_status_idx on public.photos (status) where status <> 'ready';

-- Strips (deliverable unit)
create table public.strips (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.events (id) on delete cascade,
  composite_path text,
  created_at timestamptz not null default now()
);
create index strips_event_idx on public.strips (event_id, created_at desc);

-- Strip ↔ photo join
create table public.strip_photos (
  strip_id uuid not null references public.strips (id) on delete cascade,
  photo_id uuid not null references public.photos (id) on delete cascade,
  position int not null check (position >= 1),
  primary key (strip_id, photo_id)
);
create index strip_photos_strip_idx on public.strip_photos (strip_id, position);
create index strip_photos_photo_idx on public.strip_photos (photo_id);

-- Deliveries (SMS + email queue, scoped to a strip)
create table public.deliveries (
  id uuid primary key default gen_random_uuid(),
  strip_id uuid not null references public.strips (id) on delete cascade,
  channel text not null check (channel in ('sms', 'email')),
  recipient text not null,
  status text not null default 'pending' check (status in ('pending', 'sent', 'failed')),
  attempts int not null default 0,
  error text,
  sent_at timestamptz,
  created_at timestamptz not null default now()
);
create index deliveries_pending_idx on public.deliveries (strip_id, status) where status = 'pending';

-- Preloaded CSV autocomplete contacts
create table public.contacts (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.events (id) on delete cascade,
  name text,
  email text,
  phone text,
  source text not null default 'csv' check (source in ('csv', 'manual'))
);
create index contacts_event_idx on public.contacts (event_id);

-- Google Photos OAuth (one row per user)
create table public.gphotos_credentials (
  owner_id uuid primary key references auth.users (id) on delete cascade,
  access_token text not null,
  refresh_token text not null,
  expires_at timestamptz not null,
  scope text,
  updated_at timestamptz not null default now()
);

-- ────────────────────────────────────────────────────────────────────
-- updated_at + ready_at maintenance triggers
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
-- RLS — scoped via event ownership
-- ────────────────────────────────────────────────────────────────────

alter table public.events enable row level security;
alter table public.photos enable row level security;
alter table public.strips enable row level security;
alter table public.strip_photos enable row level security;
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

create policy "owner manages strips via event"
  on public.strips for all to authenticated
  using (exists (select 1 from public.events e where e.id = event_id and e.owner_id = auth.uid()))
  with check (exists (select 1 from public.events e where e.id = event_id and e.owner_id = auth.uid()));

create policy "owner manages strip_photos via strip"
  on public.strip_photos for all to authenticated
  using (exists (
    select 1 from public.strips s
    join public.events e on e.id = s.event_id
    where s.id = strip_id and e.owner_id = auth.uid()
  ))
  with check (exists (
    select 1 from public.strips s
    join public.events e on e.id = s.event_id
    where s.id = strip_id and e.owner_id = auth.uid()
  ));

create policy "owner manages deliveries via strip"
  on public.deliveries for all to authenticated
  using (exists (
    select 1 from public.strips s
    join public.events e on e.id = s.event_id
    where s.id = strip_id and e.owner_id = auth.uid()
  ))
  with check (exists (
    select 1 from public.strips s
    join public.events e on e.id = s.event_id
    where s.id = strip_id and e.owner_id = auth.uid()
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
-- Storage buckets + policies (uses storage.objects.name, UUID-cast compare
-- for case-insensitivity)
-- ────────────────────────────────────────────────────────────────────

insert into storage.buckets (id, name, public) values
  ('photos', 'photos', false),
  ('composites', 'composites', false),
  ('templates', 'templates', true)
on conflict (id) do nothing;

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

create policy "anyone reads templates bucket"
  on storage.objects for select to anon, authenticated
  using (bucket_id = 'templates');

create policy "owner writes templates bucket"
  on storage.objects for insert to authenticated
  with check (bucket_id = 'templates');
