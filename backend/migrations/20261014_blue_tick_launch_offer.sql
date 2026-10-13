alter table public.bc_profiles add column if not exists trial_number smallint;
alter table public.bc_profiles drop constraint if exists bc_profiles_trial_number_check;
alter table public.bc_profiles add constraint bc_profiles_trial_number_check check(trial_number is null or trial_number between 1 and 100);
create unique index if not exists bc_profiles_trial_number_unique on public.bc_profiles(trial_number) where trial_number is not null;

create or replace function bc_private.action(action text,payload jsonb default '{}'::jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
 uid uuid := auth.uid();
 is_admin boolean;
 target uuid;
 t bc_private.threads%rowtype;
 result jsonb;
 msg text;
 expires_at timestamptz;
 trial_count integer;
begin
 if uid is null or coalesce(auth.jwt()->>'is_anonymous','false')='true' or not exists(select 1 from auth.users where id=uid and email_confirmed_at is not null) then
 raise exception 'Sign in with a confirmed account first'; end if;
 is_admin := exists(select 1 from bc_private.admins where user_id=uid);
 if action='me' then
 return jsonb_build_object('id',uid,'admin',is_admin,'profile',(select to_jsonb(p) from public.bc_profiles p where id=uid),'contacts',(select to_jsonb(c) from bc_private.contacts c where user_id=uid),'application',(select to_jsonb(a) from bc_private.applications a where user_id=uid),'trial_slots_remaining',greatest(0,100-(select count(*) from public.bc_profiles where trial_started_at is not null)));
 elsif action='save_profile' then
 if jsonb_typeof(payload->'meet')<>'array' then raise exception 'Choose meeting countries'; end if;
 insert into public.bc_profiles(id,name,role,company,industry,country,city,meet,bio,email,phone)
 values(uid,btrim(payload->>'name'),btrim(payload->>'role'),btrim(payload->>'company'),payload->>'industry',btrim(payload->>'country'),btrim(payload->>'city'),array(select jsonb_array_elements_text(payload->'meet')),btrim(payload->>'bio'),
 case when coalesce((payload->>'showEmail')::boolean,false) then coalesce(payload->>'email','') else '' end,
 case when coalesce((payload->>'showPhone')::boolean,false) then coalesce(payload->>'phone','') else '' end)
 on conflict(id) do update set name=excluded.name,role=excluded.role,company=excluded.company,industry=excluded.industry,country=excluded.country,city=excluded.city,meet=excluded.meet,bio=excluded.bio,email=excluded.email,phone=excluded.phone;
 insert into bc_private.contacts(user_id,email,phone,show_email,show_phone) values(uid,left(coalesce(payload->>'email',''),254),left(coalesce(payload->>'phone',''),25),coalesce((payload->>'showEmail')::boolean,false),coalesce((payload->>'showPhone')::boolean,false))
 on conflict(user_id) do update set email=excluded.email,phone=excluded.phone,show_email=excluded.show_email,show_phone=excluded.show_phone;
 return jsonb_build_object('ok',true);
 elsif action='start_blue_trial' then
 if not exists(select 1 from public.bc_profiles where id=uid) then raise exception 'Create your business profile first'; end if;
 if exists(select 1 from public.bc_profiles where id=uid and founder) then raise exception 'Founder badge is already active'; end if;
 if exists(select 1 from public.bc_profiles where id=uid and trial_started_at is not null) then raise exception 'Your free blue tick launch offer has already been used'; end if;
 if exists(select 1 from public.bc_profiles where id=uid and verified and (verified_until is null or verified_until>now())) then raise exception 'Your blue tick is already active'; end if;
 perform pg_advisory_xact_lock(hashtext('bc_blue_tick_trial_slots'));
 select count(*) into trial_count from public.bc_profiles where trial_started_at is not null;
 if trial_count>=100 then raise exception 'This launch offer is no longer available'; end if;
 update public.bc_profiles
 set verified=true,verification_source='trial',trial_started_at=now(),trial_number=trial_count+1,verified_until=now()+interval '3 months'
 where id=uid
 returning verified_until into expires_at;
 return jsonb_build_object('ok',true,'verified_until',expires_at,'trial_number',trial_count+1);
 elsif action='apply' then
 if not exists(select 1 from public.bc_profiles where id=uid) then raise exception 'Save your business profile first'; end if;
 if exists(select 1 from public.bc_profiles where id=uid and (verified or founder)) then raise exception 'Your profile already has a badge'; end if;
 insert into bc_private.applications(user_id,business_url,note) values(uid,coalesce(payload->>'business_url',''),coalesce(payload->>'note',''))
 on conflict(user_id) do update set business_url=excluded.business_url,note=excluded.note,status='pending',updated_at=now();
 return jsonb_build_object('ok',true);
 elsif action='admin_list' then
 if not is_admin then raise exception 'Founder access required'; end if;
 select coalesce(jsonb_agg(to_jsonb(p)||jsonb_build_object('application',to_jsonb(a)) order by a.updated_at desc nulls last),'[]'::jsonb) into result
 from public.bc_profiles p left join bc_private.applications a on p.id=a.user_id;
 return result;
 elsif action='badge' then
 if not is_admin then raise exception 'Founder access required'; end if;
 target:=(payload->>'target')::uuid;
 if payload->>'decision' not in ('approve','reject','remove') then raise exception 'Invalid badge decision'; end if;
 if exists(select 1 from public.bc_profiles where id=target and founder) then raise exception 'Founder badge cannot be changed here'; end if;
 update public.bc_profiles
 set verified=(payload->>'decision'='approve'),
 verification_source=case when payload->>'decision'='approve' then 'manual' else null end,
 verified_until=null
 where id=target;
 if not found then raise exception 'Profile not found'; end if;
 update bc_private.applications set status=case when payload->>'decision'='approve' then 'approved' else 'rejected' end,updated_at=now() where user_id=target;
 insert into bc_private.badge_audit(admin_id,target_id,decision) values(uid,target,payload->>'decision');
 return jsonb_build_object('ok',true);
 elsif action='inbox' then
 select coalesce(jsonb_agg(to_jsonb(th)||jsonb_build_object('other_name',p.name,'other_id',p.id,'last_message',(select body from bc_private.messages where thread_id=th.id order by id desc limit 1)) order by th.created_at desc),'[]'::jsonb) into result
 from bc_private.threads th join public.bc_profiles p on p.id=case when th.starter=uid then th.receiver else th.starter end where uid in(th.starter,th.receiver);
 return result;
 elsif action='chat' then
 target:=(payload->>'target')::uuid;
 select * into t from bc_private.threads where pair_a=least(uid,target) and pair_b=greatest(uid,target);
 if not found then return jsonb_build_object('thread',null,'messages','[]'::jsonb); end if;
 if uid not in(t.starter,t.receiver) then raise exception 'Access denied'; end if;
 select coalesce(jsonb_agg(to_jsonb(m) order by m.id),'[]'::jsonb) into result from (select * from bc_private.messages where thread_id=t.id order by id desc limit 200) m;
 return jsonb_build_object('thread',to_jsonb(t),'messages',result);
 elsif action='send' then
 target:=(payload->>'target')::uuid;msg:=btrim(payload->>'body');
 if target is null or target=uid then raise exception 'Choose another business profile'; end if;
 if msg is null or length(msg) not between 1 and 2000 then raise exception 'Message must contain 1–2000 characters'; end if;
 if not exists(select 1 from public.bc_profiles where id=uid) then raise exception 'Save your business profile before messaging'; end if;
 insert into bc_private.threads(starter,receiver) values(uid,target) on conflict(pair_a,pair_b) do nothing;
 select * into t from bc_private.threads where pair_a=least(uid,target) and pair_b=greatest(uid,target) for update;
 if uid not in(t.starter,t.receiver) then raise exception 'Access denied'; end if;
 if t.status='declined' then raise exception 'This request was declined'; end if;
 if t.status='pending' then
 if t.starter<>uid then raise exception 'Accept this request before replying'; end if;
 if (select count(*) from bc_private.messages where thread_id=t.id)>=3 then raise exception 'Three messages sent. Wait for the receiver to accept'; end if;
 end if;
 insert into bc_private.messages(thread_id,sender,body) values(t.id,uid,msg);
 return jsonb_build_object('ok',true);
 elsif action='respond' then
 target:=(payload->>'thread')::uuid;
 select * into t from bc_private.threads where id=target for update;
 if not found or t.receiver<>uid then raise exception 'Only the receiver can respond'; end if;
 if t.status<>'pending' then raise exception 'This request has already been reviewed'; end if;
 if payload->>'decision' not in ('accepted','declined') then raise exception 'Invalid response'; end if;
 update bc_private.threads set status=payload->>'decision' where id=t.id;
 return jsonb_build_object('ok',true);
 else raise exception 'Unknown operation';
 end if;
end $$;
revoke all on function bc_private.action(text,jsonb) from public,anon,authenticated;
grant execute on function bc_private.action(text,jsonb) to authenticated;
notify pgrst, 'reload schema';