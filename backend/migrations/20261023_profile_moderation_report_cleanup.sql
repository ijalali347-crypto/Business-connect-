-- Keep permanent profile deletion complete by removing reports made by or about the deleted profile.
create or replace function public.bc_founder_moderate_profile(p_target uuid, p_action text)
returns jsonb language plpgsql security definer set search_path=''
as $$
declare uid uuid:=auth.uid(); clean_action text:=lower(btrim(coalesce(p_action,'')));
begin
  if uid is null or coalesce(auth.jwt()->>'is_anonymous','false')='true'
     or not exists(select 1 from auth.users where id=uid and email_confirmed_at is not null) then raise exception 'Sign in with a confirmed account first'; end if;
  if not exists(select 1 from bc_private.admins where user_id=uid) then raise exception 'Founder access required'; end if;
  if p_target is null or p_target=uid then raise exception 'You cannot moderate your own founder profile'; end if;
  if clean_action not in ('block','unblock','delete') then raise exception 'Invalid moderation action'; end if;
  if not exists(select 1 from public.bc_profiles where id=p_target) then raise exception 'Profile not found'; end if;
  if exists(select 1 from public.bc_profiles where id=p_target and founder) then raise exception 'Founder profile cannot be moderated here'; end if;
  if clean_action='block' then
    update public.bc_profiles set is_blocked=true,blocked_at=now(),blocked_by=uid where id=p_target;
    update bc_private.profile_reports set status='actioned',updated_at=now() where target_id=p_target and status='open';
    return jsonb_build_object('ok',true,'action','block');
  elsif clean_action='unblock' then
    update public.bc_profiles set is_blocked=false,blocked_at=null,blocked_by=null where id=p_target;
    return jsonb_build_object('ok',true,'action','unblock');
  end if;
  delete from bc_private.messages m using bc_private.threads t where m.thread_id=t.id and (t.starter=p_target or t.receiver=p_target);
  delete from bc_private.threads where starter=p_target or receiver=p_target;
  delete from bc_private.profile_reports where target_id=p_target or reporter_id=p_target;
  delete from bc_private.badge_audit where target_id=p_target;
  delete from bc_private.applications where user_id=p_target;
  delete from bc_private.contacts where user_id=p_target;
  delete from bc_private.founder_reviews where user_id=p_target;
  delete from public.bc_profiles where id=p_target;
  return jsonb_build_object('ok',true,'action','delete');
end;
$$;