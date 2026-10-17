-- Deliver message and request updates immediately to the two participants.
-- These tables remain in the non-exposed bc_private schema; this SELECT access
-- is solely required by Supabase Realtime to apply row-level security.
grant usage on schema bc_private to authenticated;
grant select on bc_private.threads, bc_private.messages to authenticated;

drop policy if exists bc_realtime_thread_participants on bc_private.threads;
create policy bc_realtime_thread_participants on bc_private.threads
for select to authenticated
using ((select auth.uid()) in (starter, receiver));

drop policy if exists bc_realtime_message_participants on bc_private.messages;
create policy bc_realtime_message_participants on bc_private.messages
for select to authenticated
using (
  exists (
    select 1
    from bc_private.threads t
    where t.id = messages.thread_id
      and (select auth.uid()) in (t.starter, t.receiver)
  )
);

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'bc_private'
      and tablename = 'threads'
  ) then
    alter publication supabase_realtime add table bc_private.threads;
  end if;
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'bc_private'
      and tablename = 'messages'
  ) then
    alter publication supabase_realtime add table bc_private.messages;
  end if;
end $$;
