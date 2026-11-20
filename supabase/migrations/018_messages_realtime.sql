-- 018_messages_realtime.sql
-- Private, per-user Broadcast notifications for direct messages.
--
-- Messages remain inaccessible through the Data API. Realtime only carries a
-- message id; clients fetch the actual conversation through dm_thread(), which
-- performs the existing server-side authorization and read-state update.
--
-- Each authenticated user may subscribe only to user:<their auth uid>.
-- No message body, video id, or other private content is broadcast.

alter table realtime.messages enable row level security;

drop policy if exists "Users receive their own YapChat events" on realtime.messages;
create policy "Users receive their own YapChat events"
  on realtime.messages
  for select
  to authenticated
  using (
    extension = 'broadcast'
    and realtime.topic() = 'user:' || (select auth.uid())::text
  );

create or replace function public.broadcast_direct_message()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform realtime.send(
    jsonb_build_object('message_id', new.id),
    'new_message',
    'user:' || new.receiver_id::text,
    true
  );
  return new;
end;
$$;

revoke all on function public.broadcast_direct_message() from public, anon, authenticated;

drop trigger if exists messages_broadcast_insert on public.messages;
create trigger messages_broadcast_insert
  after insert on public.messages
  for each row
  execute function public.broadcast_direct_message();
