-- Event share links — public per-event gallery gated by password + magic-token.
--
-- New surface:
--   - events gains share_code (public URL slug), share_password_hash (bcrypt),
--     share_enabled (owner-controlled toggle).
--   - event_share_recipients tracks who we've sent a magic-link URL to. Each
--     row carries a unique token so recipients skip the password prompt.
--
-- Send flow mirrors deliveries: INSERT trigger → pg_net → send-event-share
-- Edge Function. Retry loop via pg_cron every minute, same exponential
-- backoff as retry_pending_deliveries.

-- ────────────────────────────────────────────────────────────────────
-- events: share columns
-- ────────────────────────────────────────────────────────────────────
alter table public.events
  add column if not exists share_code text unique,
  add column if not exists share_password_hash text,
  add column if not exists share_enabled boolean not null default false;

-- ────────────────────────────────────────────────────────────────────
-- event_share_recipients
-- ────────────────────────────────────────────────────────────────────
create table if not exists public.event_share_recipients (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.events (id) on delete cascade,
  channel text not null check (channel in ('sms', 'email')),
  recipient text not null,
  token text not null unique,
  status text not null default 'pending' check (status in ('pending', 'sent', 'failed')),
  attempts int not null default 0,
  error text,
  sent_at timestamptz,
  last_attempt_at timestamptz,
  created_at timestamptz not null default now()
);
create index if not exists event_share_recipients_event_idx
  on public.event_share_recipients (event_id, created_at desc);
create index if not exists event_share_recipients_pending_idx
  on public.event_share_recipients (status)
  where status = 'pending';

alter table public.event_share_recipients enable row level security;

drop policy if exists "owner manages event_share_recipients via event"
  on public.event_share_recipients;

create policy "owner manages event_share_recipients via event"
  on public.event_share_recipients for all to authenticated
  using (exists (
    select 1 from public.events e
    where e.id = event_id and e.owner_id = auth.uid()
  ))
  with check (exists (
    select 1 from public.events e
    where e.id = event_id and e.owner_id = auth.uid()
  ));

-- ────────────────────────────────────────────────────────────────────
-- Dispatch: pg_net → send-event-share Edge Function
-- ────────────────────────────────────────────────────────────────────
create or replace function public.send_event_share_now(p_recipient_id uuid)
returns void
language plpgsql
security definer
as $$
declare
  edge_url constant text := 'https://fyhddmerdksdbdryvtaf.supabase.co/functions/v1/send-event-share';
begin
  perform net.http_post(
    url := edge_url,
    headers := jsonb_build_object('Content-Type', 'application/json'),
    body := jsonb_build_object('recipient_id', p_recipient_id)
  );
end;
$$;

create or replace function public.on_event_share_recipient_insert()
returns trigger
language plpgsql
security definer
as $$
begin
  perform public.send_event_share_now(new.id);
  return new;
end;
$$;

drop trigger if exists event_share_recipients_send_on_insert on public.event_share_recipients;
create trigger event_share_recipients_send_on_insert
  after insert on public.event_share_recipients
  for each row execute function public.on_event_share_recipient_insert();

-- ────────────────────────────────────────────────────────────────────
-- Retry cron — mirrors retry_pending_deliveries backoff (30s → 1920s, cap 8)
-- ────────────────────────────────────────────────────────────────────
create or replace function public.retry_pending_event_shares()
returns void
language plpgsql
security definer
as $$
declare
  r_id uuid;
begin
  for r_id in
    select id
    from public.event_share_recipients
    where status = 'pending'
      and attempts < 8
      and (
        (attempts = 0 and created_at < now() - interval '60 seconds')
        or (
          attempts > 0
          and last_attempt_at is not null
          and last_attempt_at < now() - (
            interval '30 seconds' * power(2, least(attempts - 1, 6)::int)
          )
        )
      )
    order by created_at
    limit 10
  loop
    perform public.send_event_share_now(r_id);
  end loop;
end;
$$;

do $$
begin
  if exists (select 1 from cron.job where jobname = 'photoboot-event-share-retry') then
    perform cron.unschedule('photoboot-event-share-retry');
  end if;
end $$;

select cron.schedule(
  'photoboot-event-share-retry',
  '* * * * *',
  $$select public.retry_pending_event_shares();$$
);
