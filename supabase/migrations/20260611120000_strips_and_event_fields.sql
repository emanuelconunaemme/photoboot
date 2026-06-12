-- Event-level configuration (description, date, theme colors, shots-per-strip),
-- a strips table that's the user-facing unit (composite image of N raw photos),
-- a join table linking strips back to their raw photos, and a switch of
-- deliveries from referencing photos to referencing strips.

-- ────────────────────────────────────────────────────────────────────
-- Events: new columns
-- ────────────────────────────────────────────────────────────────────
alter table public.events
  add column description text,
  add column event_date date,
  add column primary_color text not null default '#E1306C',
  add column secondary_color text not null default '#833AB4',
  add column shots_per_strip int not null default 3,
  add column invite_image_path text;

alter table public.events
  add constraint events_primary_color_format
    check (primary_color ~ '^#[0-9a-fA-F]{6}$'),
  add constraint events_secondary_color_format
    check (secondary_color ~ '^#[0-9a-fA-F]{6}$'),
  add constraint events_shots_per_strip_range
    check (shots_per_strip between 1 and 6);

-- ────────────────────────────────────────────────────────────────────
-- Strips — the composite "photo booth strip" that's the deliverable unit
-- ────────────────────────────────────────────────────────────────────
create table public.strips (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.events (id) on delete cascade,
  composite_path text,   -- key in the `composites` storage bucket
  created_at timestamptz not null default now()
);

create index strips_event_idx on public.strips (event_id, created_at desc);

-- ────────────────────────────────────────────────────────────────────
-- Strip ↔ photo join table (preserves raw-photo provenance + ordering)
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
-- Deliveries: strip_id replaces photo_id
-- ────────────────────────────────────────────────────────────────────
drop index if exists deliveries_pending_idx;

alter table public.deliveries drop constraint deliveries_photo_id_fkey;
alter table public.deliveries drop column photo_id;

alter table public.deliveries
  add column strip_id uuid not null references public.strips (id) on delete cascade;

create index deliveries_pending_idx
  on public.deliveries (strip_id, status)
  where status = 'pending';

-- ────────────────────────────────────────────────────────────────────
-- RLS for strips + strip_photos (mirror the events-ownership pattern)
-- ────────────────────────────────────────────────────────────────────
alter table public.strips enable row level security;
alter table public.strip_photos enable row level security;

create policy "owner manages strips via event"
  on public.strips for all to authenticated
  using (exists (
    select 1 from public.events e
    where e.id = event_id and e.owner_id = auth.uid()
  ))
  with check (exists (
    select 1 from public.events e
    where e.id = event_id and e.owner_id = auth.uid()
  ));

create policy "owner manages strip_photos via strip"
  on public.strip_photos for all to authenticated
  using (exists (
    select 1
    from public.strips s
    join public.events e on e.id = s.event_id
    where s.id = strip_id and e.owner_id = auth.uid()
  ))
  with check (exists (
    select 1
    from public.strips s
    join public.events e on e.id = s.event_id
    where s.id = strip_id and e.owner_id = auth.uid()
  ));

-- Rewrite deliveries RLS to scope via strip → event (was via photo → event).
drop policy if exists "owner manages deliveries via photo" on public.deliveries;

create policy "owner manages deliveries via strip"
  on public.deliveries for all to authenticated
  using (exists (
    select 1
    from public.strips s
    join public.events e on e.id = s.event_id
    where s.id = strip_id and e.owner_id = auth.uid()
  ))
  with check (exists (
    select 1
    from public.strips s
    join public.events e on e.id = s.event_id
    where s.id = strip_id and e.owner_id = auth.uid()
  ));
