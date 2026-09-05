alter table public.products add column if not exists image_public_id text;
alter table public.services add column if not exists cover_image_public_id text;
alter table public.events add column if not exists poster_public_id text;
alter table public.gallery_photos add column if not exists image_public_id text;

update public.businesses
set logo_public_id = regexp_replace(regexp_replace(split_part(split_part(logo_url, '/image/upload/', 2), '?', 1), '^v[0-9]+/', ''), '[.][^/]+$', '')
where logo_public_id is null and logo_url like 'https://res.cloudinary.com/%/image/upload/%';

update public.products
set image_public_id = regexp_replace(regexp_replace(split_part(split_part(image_url, '/image/upload/', 2), '?', 1), '^v[0-9]+/', ''), '[.][^/]+$', '')
where image_public_id is null and image_url like 'https://res.cloudinary.com/%/image/upload/%';

update public.services
set cover_image_public_id = regexp_replace(regexp_replace(split_part(split_part(cover_image, '/image/upload/', 2), '?', 1), '^v[0-9]+/', ''), '[.][^/]+$', '')
where cover_image_public_id is null and cover_image like 'https://res.cloudinary.com/%/image/upload/%';

update public.events
set poster_public_id = regexp_replace(regexp_replace(split_part(split_part(poster_url, '/image/upload/', 2), '?', 1), '^v[0-9]+/', ''), '[.][^/]+$', '')
where poster_public_id is null and poster_url like 'https://res.cloudinary.com/%/image/upload/%';

update public.gallery_photos
set image_public_id = regexp_replace(regexp_replace(split_part(split_part(image_url, '/image/upload/', 2), '?', 1), '^v[0-9]+/', ''), '[.][^/]+$', '')
where image_public_id is null and image_url like 'https://res.cloudinary.com/%/image/upload/%';
