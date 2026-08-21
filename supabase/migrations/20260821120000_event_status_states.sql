-- Event lifecycle becomes draft → upcoming → live → done.
-- 'archived' is retired; existing archived events become 'done'.

alter table public.events drop constraint if exists events_status_check;

update public.events set status = 'done' where status = 'archived';

alter table public.events
  add constraint events_status_check
  check (status in ('draft', 'upcoming', 'live', 'done'));
