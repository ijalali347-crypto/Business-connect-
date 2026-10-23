-- Private reports for Business Connect profile moderation.
create table if not exists bc_private.profile_reports (
  id bigint generated always as identity primary key,
  reporter_id uuid not null references auth.users(id) on delete cascade,
  target_id uuid not null references public.bc_profiles(id) on delete cascade,
  reason text not null check (reason in ('fake_profile','scam','spam','abusive_content','other')),
  message text not null check (length(btrim(message)) between 10 and 2000),
  status text not null default 'open' check (status in ('open','reviewed','actioned','dismissed')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (reporter_id,target_id)
);

alter table bc_private.profile_reports enable row level security;
revoke all on bc_private.profile_reports from anon, authenticated;
create index if not exists profile_reports_created_at_idx on bc_private.profile_reports (created_at desc);
create index if not exists profile_reports_target_id_idx on bc_private.profile_reports (target_id);

create or replace function public.bc_submit_profile_report(p_target uuid, p_reason text, p_message text)
returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  uid uuid := auth.uid();
  clean_reason text := lower(btrim(coalesce(p_reason,'')));
  clean_message text := btrim(coalesce(p_message,''));
begin
  if uid is null or coalesce(auth.jwt()->>'is_anonymous','false')='true'
     or not exists (select 1 from auth.users where id=uid and email_confirmed_at is not null) then
    raise exception 'Sign in with a confirmed account first';
  end if;
  if p_target is null or p_target=uid then raise exception 'You cannot report this profile'; end if;
  if clean_reason not in ('fake_profile','scam','spam','abusive_content','other') then raise exception 'Choose a valid report reason'; end if;
  if length(clean_message) not between 10 and 2000 then raise exception 'Write 10–2000 characters about this report'; end if;
  if not exists (select 1 from public.bc_profiles where id=p_target) then raise exception 'Profile not found'; end if;

  insert into bc_private.profile_reports(reporter_id,target_id,reason,message)
  values(uid,p_target,clean_reason,clean_message)
  on conflict(reporter_id,target_id) do update
    set reason=excluded.reason,message=excluded.message,status='open',updated_at=now();
  return jsonb_build_object('ok',true);
end;
$$;

create or replace function public.bc_founder_list_profile_reports()
returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  uid uuid := auth.uid();
  result jsonb;
begin
  if uid is null or not exists(select 1 from bc_private.admins where user_id=uid) then raise exception 'Founder access required'; end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'id',r.id,'reason',r.reason,'message',r.message,'status',r.status,
    'created_at',r.created_at,'updated_at',r.updated_at,
    'reporter_id',r.reporter_id,'reporter_name',coalesce(reporter.name,'Account without profile'),
    'reporter_company',coalesce(reporter.company,''),'reporter_email',coalesce(contact.email,auth_user.email,''),
    'target_id',r.target_id,'target_name',target.name,'target_company',target.company
  ) order by r.created_at desc),'[]'::jsonb)
  into result
  from bc_private.profile_reports r
  join public.bc_profiles target on target.id=r.target_id
  left join public.bc_profiles reporter on reporter.id=r.reporter_id
  left join bc_private.contacts contact on contact.user_id=r.reporter_id
  left join auth.users auth_user on auth_user.id=r.reporter_id;
  return result;
end;
$$;

revoke all on function public.bc_submit_profile_report(uuid,text,text) from public;
revoke all on function public.bc_founder_list_profile_reports() from public;
grant execute on function public.bc_submit_profile_report(uuid,text,text) to authenticated;
grant execute on function public.bc_founder_list_profile_reports() to authenticated;
notify pgrst, 'reload schema';
