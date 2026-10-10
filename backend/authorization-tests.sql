
begin;
insert into auth.users(id,email,email_confirmed_at) values
('00000000-0000-4000-8000-000000000001','bc-test-sender@example.invalid',now()),
('00000000-0000-4000-8000-000000000002','bc-test-receiver@example.invalid',now()),
('00000000-0000-4000-8000-000000000003','bc-test-stranger@example.invalid',now());
insert into public.bc_profiles(id,name,role,company,industry,country,city,meet,bio) select id,'Test','Founder','Test company','Technology','UAE','Dubai',array['Anywhere'],'Test business' from auth.users where id in('00000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-000000000002','00000000-0000-4000-8000-000000000003');
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
select public.bc_action('send','{"target":"00000000-0000-4000-8000-000000000002","body":"One"}');
select public.bc_action('send','{"target":"00000000-0000-4000-8000-000000000002","body":"Two"}');
select public.bc_action('send','{"target":"00000000-0000-4000-8000-000000000002","body":"Three"}');
do $$ begin
 begin perform public.bc_action('send','{"target":"00000000-0000-4000-8000-000000000002","body":"Four"}'); raise exception 'TEST FAILED: fourth message accepted'; exception when others then if sqlerrm not like 'Three messages sent.%' then raise; end if; end;
 begin perform public.bc_action('admin_list'); raise exception 'TEST FAILED: non-admin allowed'; exception when others then if sqlerrm<>'Founder access required' then raise; end if; end;
 begin perform public.bc_action('badge','{"target":"00000000-0000-4000-8000-000000000001","decision":"approve"}'); raise exception 'TEST FAILED: self promotion'; exception when others then if sqlerrm<>'Founder access required' then raise; end if; end;
 begin perform public.bc_action('respond',jsonb_build_object('thread',public.bc_action('chat','{"target":"00000000-0000-4000-8000-000000000002"}')->'thread'->>'id','decision','accepted')); raise exception 'TEST FAILED: sender accepted own request'; exception when others then if sqlerrm<>'Only the receiver can respond' then raise; end if; end;
end $$;
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000003","role":"authenticated"}',true);
do $$ begin
 if public.bc_action('inbox')<>'[]'::jsonb then raise exception 'TEST FAILED: stranger sees conversations'; end if;
 if public.bc_action('chat','{"target":"00000000-0000-4000-8000-000000000001"}')->'messages'<>'[]'::jsonb then raise exception 'TEST FAILED: stranger sees messages'; end if;
end $$;
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000002","role":"authenticated"}',true);
do $$ declare thread_id text; begin
 begin perform public.bc_action('send','{"target":"00000000-0000-4000-8000-000000000001","body":"Reply without accepting"}'); raise exception 'TEST FAILED: receiver replies without acceptance'; exception when others then if sqlerrm<>'Accept this request before replying' then raise; end if; end;
 thread_id:=public.bc_action('chat','{"target":"00000000-0000-4000-8000-000000000001"}')->'thread'->>'id';
 perform public.bc_action('respond',jsonb_build_object('thread',thread_id,'decision','accepted'));
 perform public.bc_action('send','{"target":"00000000-0000-4000-8000-000000000001","body":"Accepted reply"}');
end $$;
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
select public.bc_action('send','{"target":"00000000-0000-4000-8000-000000000002","body":"Fourth after acceptance"}');
select public.bc_action('save_profile','{"name":"Test","role":"Founder","company":"Test","industry":"Technology","country":"UAE","city":"Dubai","meet":["Anywhere"],"bio":"Business","email":"hidden@example.invalid","phone":"+971500000000","showEmail":false,"showPhone":false,"verified":true,"founder":true}');
do $$ begin
 if exists(select 1 from public.bc_profiles where id=auth.uid() and (verified or founder or email<>'' or phone<>'')) then raise exception 'TEST FAILED: hidden contacts or badges leaked'; end if;
end $$;
reset role;
insert into bc_private.admins(user_id) values('00000000-0000-4000-8000-000000000001');
set local role authenticated;
select public.bc_action('badge','{"target":"00000000-0000-4000-8000-000000000002","decision":"approve"}');
do $$ begin if not exists(select 1 from public.bc_profiles where id='00000000-0000-4000-8000-000000000002' and verified) then raise exception 'TEST FAILED: admin approval'; end if; end $$;
select public.bc_action('badge','{"target":"00000000-0000-4000-8000-000000000002","decision":"remove"}');
select public.bc_action('send','{"target":"00000000-0000-4000-8000-000000000003","body":"Decline test"}');
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000003","role":"authenticated"}',true);
select public.bc_action('respond',jsonb_build_object('thread',public.bc_action('chat','{"target":"00000000-0000-4000-8000-000000000001"}')->'thread'->>'id','decision','declined'));
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
do $$ begin
 begin perform public.bc_action('send','{"target":"00000000-0000-4000-8000-000000000003","body":"After decline"}'); raise exception 'TEST FAILED: declined request reopened'; exception when others then if sqlerrm<>'This request was declined' then raise; end if; end;
end $$;
select 'All Business Connect authorization and request-limit tests passed' as result;
rollback;
