-- Add photo support for profile posts.
alter table bc_private.profile_posts add column if not exists image_url text not null default '' check (length(image_url) <= 500 and (image_url = '' or image_url ~ '^https?://'));
-- The public post-list and create-post functions must return/accept image_url.
-- Applied to Supabase project khzqerdrhzdrkhdxfaxn on 2026-11-02.
