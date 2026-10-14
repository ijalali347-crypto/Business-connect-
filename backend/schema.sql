
create schema if not exists bc_private;
revoke all on schema bc_private from public, anon, authenticated;
grant usage on schema bc_private to authenticated;
create table public.bc_profiles (
 id uuid primary key references auth.users(id) on delete cascade,
 name text not null check(length(name) between 1 and 60),
 role text not null check(length(role) between 1 and 60),
 company text not null check(length(company) between 1 and 80),
 industry text not null check(length(industry)<=80),
 country text not null check(length(country) between 1 and 60),
 city text not null check(length(city) between 1 and 60),
 meet text[] not null check(cardinality(meet) between 1 and 250),
 bio text not null check(length(bio) between 1 and 400),
 business_logo_url text not null default '' check(length(business_logo_url)<=500),
 business_cover_url text not null default '' check(length(business_cover_url)<=500),
 email text not null default '' check(length(email)<=254),
 phone text not null default '' check(length(phone)<=25),
 verified boolean not null default false,
 founder boolean not null default false,
 verification_source text check(verification_source in ('trial','manual','paid')),
 verified_until timestamptz,
 trial_started_at timestamptz,
 trial_number smallint unique check(trial_number between 1 and 100),
 created_at timestamptz not null default now()
);
create unique index bc_one_founder on public.bc_profiles(founder) where founder;
alter table public.bc_profiles enable row level security;
revoke all on public.bc_profiles from anon, authenticated;
create policy bc_public_profiles on public.bc_profiles for select to anon,authenticated using(true);
create view public.bc_profiles_public with (security_barrier=true,security_invoker=true) as select id,name,role,company,industry,country,city,meet,bio,business_logo_url,business_cover_url,verified,founder,verification_source,verified_until,created_at from public.bc_profiles;
revoke all on public.bc_profiles_public from public;
grant select (id,name,role,company,industry,country,city,meet,bio,business_logo_url,verified,founder,verification_source,verified_until,created_at) on public.bc_profiles to anon,authenticated;
grant select on public.bc_profiles_public to anon,authenticated;

create table bc_private.admins(user_id uuid primary key references auth.users(id), created_at timestamptz not null default now());
create table bc_private.contacts(user_id uuid primary key references public.bc_profiles(id) on delete cascade, email text not null default '', phone text not null default '', show_email boolean not null default false, show_phone boolean not null default false);
create table bc_private.founder_reviews(user_id uuid primary key references public.bc_profiles(id) on delete cascade, legal_name text not null default '' check(length(legal_name)<=120), business_address text not null default '' check(length(business_address)<=300), business_website text not null default '' check(length(business_website)<=500), updated_at timestamptz not null default now());
create table bc_private.applications(user_id uuid primary key references public.bc_profiles(id) on delete cascade, status text not null default 'pending' check(status in ('pending','approved','rejected')), business_url text not null check(length(business_url)<=500), note text not null check(length(note)<=2000), updated_at timestamptz not null default now());
create table bc_private.badge_audit(id bigint generated always as identity primary key, admin_id uuid not null, target_id uuid not null, decision text not null, created_at timestamptz not null default now());
create table bc_private.threads(id uuid primary key default gen_random_uuid(), starter uuid not null references public.bc_profiles(id), receiver uuid not null references public.bc_profiles(id), status text not null default 'pending' check(status in ('pending','accepted','declined')), pair_a uuid generated always as (least(starter,receiver)) stored, pair_b uuid generated always as (greatest(starter,receiver)) stored, created_at timestamptz not null default now(), unique(pair_a,pair_b), check(starter<>receiver));
create index bc_thread_starter on bc_private.threads(starter);
create index bc_thread_receiver on bc_private.threads(receiver);
create table bc_private.messages(id bigint generated always as identity primary key, thread_id uuid not null references bc_private.threads(id) on delete cascade, sender uuid not null references public.bc_profiles(id), body text not null check(length(btrim(body)) between 1 and 2000), created_at timestamptz not null default now());
create index bc_messages_thread on bc_private.messages(thread_id,id);
alter table bc_private.admins enable row level security;
alter table bc_private.contacts enable row level security;
alter table bc_private.founder_reviews enable row level security;
alter table bc_private.applications enable row level security;
alter table bc_private.badge_audit enable row level security;
alter table bc_private.threads enable row level security;
alter table bc_private.messages enable row level security;
revoke all on all tables in schema bc_private from public,anon,authenticated;
revoke all on all sequences in schema bc_private from public,anon,authenticated;

create function bc_private.action(action text,payload jsonb default '{}'::jsonb) returns jsonb
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
 return jsonb_build_object('id',uid,'admin',is_admin,'profile',(select to_jsonb(p) from public.bc_profiles p where id=uid),'contacts',(select to_jsonb(c) from bc_private.contacts c where user_id=uid),'founder_review',(select to_jsonb(r) from bc_private.founder_reviews r where user_id=uid),'application',(select to_jsonb(a) from bc_private.applications a where user_id=uid),'trial_slots_remaining',greatest(0,100-(select count(*) from public.bc_profiles where trial_started_at is not null)));
 elsif action='save_profile' then
 if jsonb_typeof(payload->'meet')<>'array' then raise exception 'Choose meeting countries'; end if;
 insert into public.bc_profiles(id,name,role,company,industry,country,city,meet,bio,business_logo_url,business_cover_url,email,phone)
 values(uid,btrim(payload->>'name'),btrim(payload->>'role'),btrim(payload->>'company'),payload->>'industry',btrim(payload->>'country'),btrim(payload->>'city'),array(select jsonb_array_elements_text(payload->'meet')),btrim(payload->>'bio'),left(coalesce(payload->>'business_logo_url',''),500),left(coalesce(payload->>'business_cover_url',''),500),
 case when coalesce((payload->>'showEmail')::boolean,false) then coalesce(payload->>'email','') else '' end,
 case when coalesce((payload->>'showPhone')::boolean,false) then coalesce(payload->>'phone','') else '' end)
 on conflict(id) do update set name=excluded.name,role=excluded.role,company=excluded.company,industry=excluded.industry,country=excluded.country,city=excluded.city,meet=excluded.meet,bio=excluded.bio,business_logo_url=excluded.business_logo_url,business_cover_url=excluded.business_cover_url,email=excluded.email,phone=excluded.phone;
 insert into bc_private.contacts(user_id,email,phone,show_email,show_phone) values(uid,coalesce(nullif(left(coalesce(payload->>'email',''),254),''),(select email from auth.users where id=uid)),left(coalesce(payload->>'phone',(select phone from bc_private.contacts where user_id=uid),''),25),false,false)
 on conflict(user_id) do update set email=excluded.email,phone=excluded.phone,show_email=false,show_phone=false;
 insert into bc_private.founder_reviews(user_id,legal_name,business_address,business_website) values(uid,left(btrim(coalesce(payload->>'legal_name','')),120),left(btrim(coalesce(payload->>'business_address','')),300),left(btrim(coalesce(payload->>'business_website','')),500)) on conflict(user_id) do update set legal_name=excluded.legal_name,business_address=excluded.business_address,business_website=excluded.business_website,updated_at=now();
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
 select coalesce(jsonb_agg(to_jsonb(p)||jsonb_build_object('application',to_jsonb(a),'private_contact',to_jsonb(c),'founder_review',to_jsonb(r)) order by a.updated_at desc nulls last),'[]'::jsonb) into result
 from public.bc_profiles p left join bc_private.applications a on p.id=a.user_id left join bc_private.contacts c on p.id=c.user_id left join bc_private.founder_reviews r on p.id=r.user_id;
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
create function public.bc_action(action text,payload jsonb default '{}'::jsonb) returns jsonb language sql security invoker set search_path='' as $$ select bc_private.action(action,payload); $$;
revoke all on function public.bc_action(text,jsonb) from public,anon,authenticated;
grant execute on function public.bc_action(text,jsonb) to authenticated;
notify pgrst,'reload schema';

-- Explicit deny policies: private records are accessible only through checked RPC.
create policy bc_no_direct_access on bc_private.admins for all to authenticated using(false) with check(false);
create policy bc_no_direct_access on bc_private.contacts for all to authenticated using(false) with check(false);
create policy bc_no_direct_access on bc_private.founder_reviews for all to authenticated using(false) with check(false);
create policy bc_no_direct_access on bc_private.applications for all to authenticated using(false) with check(false);
create policy bc_no_direct_access on bc_private.badge_audit for all to authenticated using(false) with check(false);
create policy bc_no_direct_access on bc_private.threads for all to authenticated using(false) with check(false);
create policy bc_no_direct_access on bc_private.messages for all to authenticated using(false) with check(false);
