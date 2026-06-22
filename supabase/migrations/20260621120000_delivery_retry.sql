-- Adds an automatic retry loop for `pending` deliveries that hit a
-- retryable error in the Edge Function (Resend 429, 5xx, network blips).
-- The function distinguishes retryable from permanent now — retryable rows
-- stay in `pending` with `attempts` incremented and `last_attempt_at`
-- stamped, instead of being moved to `failed`.
--
-- pg_cron runs `retry_pending_deliveries()` every minute, picking up
-- pending rows whose backoff window has elapsed. Capped at 8 attempts so
-- a permanently-broken row eventually gives up (and stays pending — manual
-- cleanup if needed).

alter table public.deliveries
  add column if not exists last_attempt_at timestamptz;

create extension if not exists pg_cron;

create or replace function public.retry_pending_deliveries()
returns void
language plpgsql
security definer
as $$
declare
  d_id uuid;
begin
  for d_id in
    select id
    from public.deliveries
    where status = 'pending'
      and attempts < 8
      and (
        -- New rows: give the on_insert trigger ≥60s to do its thing
        -- before the retry job picks them up.
        (attempts = 0 and created_at < now() - interval '60 seconds')
        -- Subsequent retries: exponential backoff, capped at ~32 min.
        --   1→30s, 2→60s, 3→120s, 4→240s, 5→480s, 6→960s, 7+→1920s
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
    perform public.send_delivery_now(d_id);
  end loop;
end;
$$;

-- One-minute cadence. pg_cron jobs are global; the name keys this one so
-- re-applying the migration is idempotent.
do $$
begin
  if exists (select 1 from cron.job where jobname = 'photoboot-delivery-retry') then
    perform cron.unschedule('photoboot-delivery-retry');
  end if;
end $$;

select cron.schedule(
  'photoboot-delivery-retry',
  '* * * * *',
  $$select public.retry_pending_deliveries();$$
);
