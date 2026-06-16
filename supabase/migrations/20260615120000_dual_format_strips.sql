-- Multi-format strip schema. Replaces all earlier migrations.
--
-- Major changes from previous schema:
--   - Strips can be rendered in BOTH 2x6 and 4x6 formats; each strip stores
--     two composite paths instead of one.
--   - Events carry TWO background images (one per format) plus strip_title
--     and strip_subtitle for branded text.
--   - Capture is always 2 photos (events.shots_per_strip retained but ignored
--     at runtime; layout is dictated by format).
--   - Triggers fire when either composite becomes non-null.
--
-- This migration nukes prior data (events / photos / strips / strip_photos /
-- deliveries / contacts / gphotos_credentials). auth.users is untouched.
-- Existing storage objects from prior runs are orphaned — clean via dashboard
-- if you care; Supabase blocks direct DELETE on storage.objects from SQL.

-- ────────────────────────────────────────────────────────────────────
-- Drop everything we own
-- ────────────────────────────────────────────────────────────────────

-- Storage policies
drop policy if exists "owner reads photos bucket" on storage.objects;
drop policy if exists "owner writes photos bucket" on storage.objects;
drop policy if exists "owner reads composites bucket" on storage.objects;
drop policy if exists "owner writes composites bucket" on storage.objects;
drop policy if exists "anyone reads templates bucket" on storage.objects;
drop policy if exists "owner writes templates bucket" on storage.objects;

-- Legacy policy names
drop policy if exists "owner manages deliveries via photo" on public.deliveries;

-- Triggers + functions
drop trigger if exists deliveries_send_on_insert on public.deliveries;
drop trigger if exists strips_send_on_composite_ready on public.strips;
drop function if exists public.on_delivery_insert();
drop function if exists public.on_strip_composite_ready();
drop function if exists public.send_delivery_now(uuid);

-- Tables (cascade catches FKs, policies, child triggers)
drop table if exists public.deliveries cascade;
drop table if exists public.strip_photos cascade;
drop table if exists public.strips cascade;
drop table if exists public.contacts cascade;
drop table if exists public.gphotos_credentials cascade;
drop table if exists public.photos cascade;
drop table if exists public.events cascade;

-- ────────────────────────────────────────────────────────────────────
-- Extensions
-- ────────────────────────────────────────────────────────────────────
create extension if not exists pgcrypto;
create extension if not exists pg_net;

-- ────────────────────────────────────────────────────────────────────
-- Events
-- ────────────────────────────────────────────────────────────────────
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
  shots_per_strip int not null default 2 check (shots_per_strip between 1 and 6),
  invite_image_path text,
  background_2x6_path text,
  background_4x6_path text,
  strip_title text,
  strip_subtitle text,
  gphotos_album_id text,
  gphotos_share_url text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (owner_id, slug)
);
create index events_owner_status_idx on public.events (owner_id, status);

-- ────────────────────────────────────────────────────────────────────
-- Raw photos
-- ────────────────────────────────────────────────────────────────────
create table public.photos (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.events (id) on delete cascade,
  status text not null default 'uploading' check (status in ('uploading', 'ready', 'failed')),
  capture_mode text not null check (capture_mode in ('single', 'strip', 'strip-4')),
  storage_path text,
  composite_path text,    -- legacy column, unused; kept to avoid extra ALTER
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
-- Strips — TWO composites per strip (one per format)
-- ────────────────────────────────────────────────────────────────────
create table public.strips (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.events (id) on delete cascade,
  composite_2x6_path text,
  composite_4x6_path text,
  created_at timestamptz not null default now()
);
create index strips_event_idx on public.strips (event_id, created_at desc);

-- ────────────────────────────────────────────────────────────────────
-- Strip ↔ photo join (always 2 photos, but schema supports N)
-- ────────────────────────────────────────────────────────────────────
create table public.strip_photos (
  strip_id uuid not null references public.strips (id) on delete cascade,
  photo_id uuid not null references public.photos (id) on delete cascade,
  position int not null check (position >= 1),
  primary key (strip_id, photo_id)
);
create index strip_photos_strip_idx on public.strip_photos (strip_id, position);
create index strip_photos_photo_idx on public.strip_photos (photo_id);

-- ────────────────────────────────────────────────────────────────────
-- Deliveries — strip_id (strip is the deliverable unit)
-- ────────────────────────────────────────────────────────────────────
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

-- ────────────────────────────────────────────────────────────────────
-- Contacts (preloaded CSV for autocomplete)
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
-- Google Photos credentials
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
-- updated_at + ready_at maintenance
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
-- RLS
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
-- Storage buckets (idempotent; SQL can't delete storage rows, only insert)
-- ────────────────────────────────────────────────────────────────────
insert into storage.buckets (id, name, public) values
  ('photos', 'photos', false),
  ('composites', 'composites', false),
  ('templates', 'templates', true)
on conflict (id) do nothing;

-- Storage RLS — qualified column names + UUID cast for case-insensitivity
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

-- ────────────────────────────────────────────────────────────────────
-- Delivery dispatch triggers (pg_net → send-delivery Edge Function)
-- ────────────────────────────────────────────────────────────────────

create or replace function public.send_delivery_now(p_delivery_id uuid)
returns void
language plpgsql
security definer
as $$
declare
  edge_url constant text := 'https://fyhddmerdksdbdryvtaf.supabase.co/functions/v1/send-delivery';
begin
  perform net.http_post(
    url := edge_url,
    headers := jsonb_build_object('Content-Type', 'application/json'),
    body := jsonb_build_object('delivery_id', p_delivery_id)
  );
end;
$$;

create or replace function public.on_delivery_insert()
returns trigger
language plpgsql
security definer
as $$
begin
  -- Fire only if the strip already has at least one composite ready.
  if exists (
    select 1 from public.strips
    where id = new.strip_id
      and (composite_2x6_path is not null or composite_4x6_path is not null)
  ) then
    perform public.send_delivery_now(new.id);
  end if;
  return new;
end;
$$;

create trigger deliveries_send_on_insert
  after insert on public.deliveries
  for each row execute function public.on_delivery_insert();

create or replace function public.on_strip_composite_ready()
returns trigger
language plpgsql
security definer
as $$
declare
  d_id uuid;
  was_ready boolean;
  is_ready boolean;
begin
  was_ready := (old.composite_2x6_path is not null or old.composite_4x6_path is not null);
  is_ready  := (new.composite_2x6_path is not null or new.composite_4x6_path is not null);

  if (not was_ready) and is_ready then
    for d_id in
      select id from public.deliveries
      where strip_id = new.id and status = 'pending'
    loop
      perform public.send_delivery_now(d_id);
    end loop;
  end if;
  return new;
end;
$$;

create trigger strips_send_on_composite_ready
  after update on public.strips
  for each row execute function public.on_strip_composite_ready();
