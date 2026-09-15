-- 008_add_dynamic_social_links.sql
-- Preserve the current JSON-based social_links field and normalize data for dynamic platform keys.

alter table public.businesses
  add column if not exists social_links jsonb default '{}'::jsonb;

update public.businesses
set social_links = coalesce(social_links, '{}'::jsonb)
where social_links is null;

-- Backfill existing known platforms from legacy fields where present.
update public.businesses
set social_links = jsonb_strip_nulls(
  jsonb_build_object(
    'instagram', case when instagram_url is not null and trim(instagram_url) <> '' then instagram_url else null end,
    'facebook', case when facebook_url is not null and trim(facebook_url) <> '' then facebook_url else null end,
    'linkedin', case when linkedin_url is not null and trim(linkedin_url) <> '' then linkedin_url else null end,
    'youtube', case when youtube_url is not null and trim(youtube_url) <> '' then youtube_url else null end,
    'website', case when website_url is not null and trim(website_url) <> '' then website_url else null end,
    'whatsapp', case when whatsapp_number is not null and trim(whatsapp_number) <> '' then whatsapp_number else null end
  )
)
where "social_links" is null or jsonb_typeof("social_links") = 'null';

-- Legacy columns may exist in some installations; this migration keeps them intact while supporting a category-driven JSON model.
-- No destructive drop is performed here to preserve data compatibility.
