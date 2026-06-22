-- Allow `deliveries` to track local-only actions on a strip — print +
-- airdrop. These don't have a remote recipient (recipient becomes nullable)
-- and don't go through the send-delivery Edge Function. The client inserts
-- rows directly with status = 'sent' once the action completes locally.
--
-- Stats on the event page roll these into the same totals as sms/email.

alter table public.deliveries
  drop constraint if exists deliveries_channel_check;

alter table public.deliveries
  add constraint deliveries_channel_check
  check (channel in ('sms', 'email', 'print', 'airdrop'));

alter table public.deliveries
  alter column recipient drop not null;
