-- Use invoker permissions for the public profile view and grant only public columns.
alter view public.bc_profiles_public set (security_invoker=true, security_barrier=true);
grant select (id,name,role,company,industry,country,city,meet,bio,business_logo_url,verified,founder,verification_source,verified_until,created_at) on public.bc_profiles to anon,authenticated;
notify pgrst,'reload schema';
