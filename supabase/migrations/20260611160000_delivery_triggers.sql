-- Postgres triggers that invoke the send-delivery Edge Function via pg_net.
--
-- Two fire conditions (either ordering converges on the same send):
--   1. deliveries INSERT — if the strip is already ready, send immediately
--   2. strips UPDATE — when composite_path becomes non-null, fan out any
--      pending deliveries for that strip
--
-- pg_net is async — `perform` returns immediately and the HTTP call runs in
-- the background. The function updates deliveries.status itself.

create extension if not exists pg_net;

-- Hardcoded URL: project ref is stable, and the Edge Function is deployed
-- with --no-verify-jwt so no auth header is required.
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
  if exists (
    select 1 from public.strips
    where id = new.strip_id and composite_path is not null
  ) then
    perform public.send_delivery_now(new.id);
  end if;
  return new;
end;
$$;

drop trigger if exists deliveries_send_on_insert on public.deliveries;
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
begin
  if (old.composite_path is null and new.composite_path is not null) then
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

drop trigger if exists strips_send_on_composite_ready on public.strips;
create trigger strips_send_on_composite_ready
  after update on public.strips
  for each row execute function public.on_strip_composite_ready();
