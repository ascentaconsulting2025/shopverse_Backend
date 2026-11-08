-- Shopverse consolidated Supabase master schema
-- Source of truth: schema.sql followed by forward migrations 001–021.
-- Intended for a fresh Supabase project SQL Editor. Do not run against production.

-- 1–12. Core tables, constraints, indexes, and baseline RLS from schema.sql
-- Shopverse backend schema for Supabase
-- Run this in Supabase SQL editor (Dashboard > SQL Editor > New query)

-- Enable crypto extension (gen_random_uuid)
create extension if not exists "pgcrypto";

-- Profiles table: one profile row per auth user
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text,
  phone text,
  created_at timestamptz default now()
);

-- Businesses
create table if not exists public.businesses (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles(id) on delete cascade,
  business_name text not null,
  business_name_mr text,
  slug text not null,
  category text,
  category_mr text,
  description text,
  description_mr text,
  owner_name_mr text,
  designation_mr text,
  tagline_mr text,
  logo_url text,
  logo_public_id text,
  profile_image_url text,
  profile_image_public_id text,
  phone text,
  whatsapp_number text,
  address text,
  social_links jsonb,
  qr_code_url text,
  details jsonb not null default '{}'::jsonb,
  status text not null default 'draft',
  is_verified boolean not null default false,
  plan_id text not null default 'free',
  is_published boolean default false,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

-- Existing installations: add the field used to preserve the complete card model.
alter table public.businesses add column if not exists details jsonb not null default '{}'::jsonb;
alter table public.businesses add column if not exists logo_url text;
alter table public.businesses add column if not exists logo_public_id text;
alter table public.businesses add column if not exists profile_image_url text;
alter table public.businesses add column if not exists profile_image_public_id text;
alter table public.businesses add column if not exists phone text;
alter table public.businesses add column if not exists business_name_mr text;
alter table public.businesses add column if not exists category_mr text;
alter table public.businesses add column if not exists description_mr text;
alter table public.businesses add column if not exists owner_name_mr text;
alter table public.businesses add column if not exists designation_mr text;
alter table public.businesses add column if not exists tagline_mr text;
alter table public.businesses add column if not exists status text not null default 'draft';
alter table public.businesses add column if not exists is_verified boolean not null default false;
alter table public.businesses add column if not exists plan_id text not null default 'free';
update public.businesses set status = case when is_published then 'active' else coalesce(nullif(details->>'status', ''), 'draft') end where status is null or status = 'draft';

-- Unique slug
create unique index if not exists idx_businesses_slug on public.businesses(slug);

-- Products
create table if not exists public.products (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  name text not null,
  name_en text,
  name_mr text,
  description text,
  description_en text,
  description_mr text,
  price numeric(12,2),
  original_price numeric(12,2),
  image_url text,
  image_public_id text,
  category text,
  category_en text,
  category_mr text,
  is_available boolean default true,
  sort_order int default 0,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

-- Product fields added after the initial single-language product schema.
alter table public.products add column if not exists name_en text;
alter table public.products add column if not exists name_mr text;
alter table public.products add column if not exists description_en text;
alter table public.products add column if not exists description_mr text;
alter table public.products add column if not exists original_price numeric(12,2);
alter table public.products add column if not exists category_en text;
alter table public.products add column if not exists category_mr text;

-- Composite index for product list queries
create index if not exists idx_products_business_available on public.products(business_id, is_available);

-- Services
create table if not exists public.services (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  name text not null,
  name_en text not null,
  name_mr text not null,
  starting_price numeric(12,2) check (starting_price > 0),
  duration_en text,
  duration_mr text,
  category_en text,
  category_mr text,
  details text,
  details_en text,
  details_mr text,
  cover_image text,
  cover_image_public_id text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_services_business_created on public.services(business_id, created_at desc);

-- Inquiries
create table if not exists public.inquiries (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  customer_name text,
  customer_phone text,
  message text,
  created_at timestamptz default now()
);

-- ROW LEVEL SECURITY: enable and policies

-- Profiles RLS: owners can manage their profile
alter table public.profiles enable row level security;

create policy "Profiles: owner select" on public.profiles
  for select using (auth.uid() = id);

create policy "Profiles: owner insert" on public.profiles
  for insert with check (auth.uid() = id);

create policy "Profiles: owner update" on public.profiles
  for update using (auth.uid() = id) with check (auth.uid() = id);

create policy "Profiles: owner delete" on public.profiles
  for delete using (auth.uid() = id);

-- Businesses RLS
alter table public.businesses enable row level security;

-- Owners: full access for rows they own
create policy "Businesses: owner full access" on public.businesses
  for all using (owner_id = auth.uid()) with check (owner_id = auth.uid());

-- Public browse: allow anonymous/public select for published businesses
create policy "Businesses: public select published" on public.businesses
  for select using (is_published = true);

-- Products RLS
alter table public.products enable row level security;

-- Owners: allow full access to products that belong to a business they own
create policy "Products: owner select" on public.products
  for select using (
    exists (select 1 from public.businesses b where b.id = public.products.business_id and b.owner_id = auth.uid())
  );

create policy "Products: owner insert" on public.products
  for insert with check (
    exists (select 1 from public.businesses b where b.id = public.products.business_id and b.owner_id = auth.uid())
  );

create policy "Products: owner update" on public.products
  for update using (
    exists (select 1 from public.businesses b where b.id = public.products.business_id and b.owner_id = auth.uid())
  ) with check (
    exists (select 1 from public.businesses b where b.id = public.products.business_id and b.owner_id = auth.uid())
  );

create policy "Products: owner delete" on public.products
  for delete using (
    exists (select 1 from public.businesses b where b.id = public.products.business_id and b.owner_id = auth.uid())
  );

-- Public select for products only if the parent business is published
create policy "Products: public select when business published" on public.products
  for select using (
    exists (select 1 from public.businesses b where b.id = public.products.business_id and b.is_published = true)
  );

-- Services RLS
alter table public.services enable row level security;

create policy "Services: owner select" on public.services
  for select using (
    exists (select 1 from public.businesses b where b.id = public.services.business_id and b.owner_id = auth.uid())
  );

create policy "Services: owner insert" on public.services
  for insert with check (
    exists (select 1 from public.businesses b where b.id = public.services.business_id and b.owner_id = auth.uid())
  );

create policy "Services: owner update" on public.services
  for update using (
    exists (select 1 from public.businesses b where b.id = public.services.business_id and b.owner_id = auth.uid())
  ) with check (
    exists (select 1 from public.businesses b where b.id = public.services.business_id and b.owner_id = auth.uid())
  );

create policy "Services: owner delete" on public.services
  for delete using (
    exists (select 1 from public.businesses b where b.id = public.services.business_id and b.owner_id = auth.uid())
  );

create policy "Services: public select when business published" on public.services
  for select using (
    exists (select 1 from public.businesses b where b.id = public.services.business_id and b.is_published = true)
  );

-- Inquiries RLS
alter table public.inquiries enable row level security;

-- Public may insert inquiries for businesses that are published
create policy "Inquiries: public insert for published businesses" on public.inquiries
  for insert with check (
    exists (select 1 from public.businesses b where b.id = public.inquiries.business_id and b.is_published = true)
  );

-- Business owners may select/delete inquiries for their business
create policy "Inquiries: owner select" on public.inquiries
  for select using (
    exists (select 1 from public.businesses b where b.id = public.inquiries.business_id and b.owner_id = auth.uid())
  );

create policy "Inquiries: owner delete" on public.inquiries
  for delete using (
    exists (select 1 from public.businesses b where b.id = public.inquiries.business_id and b.owner_id = auth.uid())
  );

-- Quick sanity: ensure owner_id in businesses references existing profile (no-op if FK present)

-- End of schema




-- Migration 001_create_services.sql
create table if not exists public.services (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  name text not null,
  name_en text not null,
  name_mr text not null,
  starting_price numeric(12,2) not null check (starting_price >= 0),
  duration_en text,
  duration_mr text,
  category_en text,
  category_mr text,
  details text,
  details_en text,
  details_mr text,
  cover_image text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_services_business_created
  on public.services(business_id, created_at desc);

-- Preserve legacy services embedded in businesses.details when this migration is first applied.
insert into public.services (
  business_id, name, name_en, name_mr, starting_price,
  duration_en, duration_mr, category_en, category_mr,
  details, details_en, details_mr, cover_image
)
select
  b.id,
  coalesce(nullif(service_item->'name'->>'en', ''), service_item->'name'->>'mr', 'Untitled service'),
  coalesce(service_item->'name'->>'en', ''),
  coalesce(service_item->'name'->>'mr', ''),
  greatest(coalesce((service_item->>'startingPrice')::numeric, 0), 0),
  nullif(service_item->'duration'->>'en', ''),
  nullif(service_item->'duration'->>'mr', ''),
  nullif(service_item->'category'->>'en', ''),
  nullif(service_item->'category'->>'mr', ''),
  coalesce(nullif(service_item->'description'->>'en', ''), service_item->'description'->>'mr'),
  nullif(service_item->'description'->>'en', ''),
  nullif(service_item->'description'->>'mr', ''),
  nullif(service_item->>'image', '')
from public.businesses b
cross join lateral jsonb_array_elements(
  case when jsonb_typeof(b.details->'services') = 'array' then b.details->'services' else '[]'::jsonb end
) as service_item
where not exists (
  select 1 from public.services existing
  where existing.business_id = b.id
    and existing.name_en = coalesce(service_item->'name'->>'en', '')
    and existing.name_mr = coalesce(service_item->'name'->>'mr', '')
);





-- Migration 002_create_events_offers_gallery.sql
create table if not exists public.events (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  event_name_en text not null, event_name_mr text not null default '',
  description_en text not null default '', description_mr text not null default '',
  event_date text not null, start_time text not null, end_time text not null default '',
  venue_en text not null, venue_mr text not null default '', enquiry_number text not null,
  website_url text, poster_url text, poster_public_id text, is_active boolean not null default true,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(), deleted_at timestamptz
);
create index if not exists idx_events_business_date on public.events(business_id, event_date);

create table if not exists public.offers (
  id uuid primary key default gen_random_uuid(), business_id uuid not null references public.businesses(id) on delete cascade,
  event_id uuid references public.events(id) on delete set null, offer_title_en text not null, offer_title_mr text not null default '',
  discount_percentage numeric(5,2) check (discount_percentage between 0 and 100), discount_badge_en text not null default '', discount_badge_mr text not null default '',
  coupon_code text not null, validity_en text not null, validity_mr text not null default '', terms_en text not null, terms_mr text not null default '',
  is_active boolean not null default true, created_at timestamptz not null default now(), updated_at timestamptz not null default now(), deleted_at timestamptz
);
alter table public.offers add column if not exists deleted_at timestamptz;
create index if not exists idx_offers_business_event on public.offers(business_id, event_id);
create unique index if not exists idx_offers_business_coupon_active on public.offers(business_id, coupon_code) where deleted_at is null;

create table if not exists public.gallery_photos (
  id uuid primary key default gen_random_uuid(), business_id uuid not null references public.businesses(id) on delete cascade,
  event_id uuid references public.events(id) on delete set null, image_url text not null, image_public_id text, caption text not null default '', category text not null default '',
  sort_order integer not null default 0, is_active boolean not null default true, created_at timestamptz not null default now(), updated_at timestamptz not null default now(), deleted_at timestamptz
);
create index if not exists idx_gallery_business_sort on public.gallery_photos(business_id, sort_order, created_at desc);

alter table public.events enable row level security; alter table public.offers enable row level security; alter table public.gallery_photos enable row level security;
create policy "Events owner manage" on public.events for all using (exists (select 1 from public.businesses b where b.id = events.business_id and b.owner_id = auth.uid())) with check (exists (select 1 from public.businesses b where b.id = events.business_id and b.owner_id = auth.uid()));
create policy "Events public active" on public.events for select using (is_active and deleted_at is null and exists (select 1 from public.businesses b where b.id = events.business_id and b.is_published = true));
create policy "Offers owner manage" on public.offers for all using (exists (select 1 from public.businesses b where b.id = offers.business_id and b.owner_id = auth.uid())) with check (exists (select 1 from public.businesses b where b.id = offers.business_id and b.owner_id = auth.uid()));
create policy "Offers public active" on public.offers for select using (is_active and deleted_at is null and exists (select 1 from public.businesses b where b.id = offers.business_id and b.is_published = true));
create policy "Gallery owner manage" on public.gallery_photos for all using (exists (select 1 from public.businesses b where b.id = gallery_photos.business_id and b.owner_id = auth.uid())) with check (exists (select 1 from public.businesses b where b.id = gallery_photos.business_id and b.owner_id = auth.uid()));
create policy "Gallery public active" on public.gallery_photos for select using (is_active and deleted_at is null and exists (select 1 from public.businesses b where b.id = gallery_photos.business_id and b.is_published = true));

-- Preserve legacy card content that was previously embedded in businesses.details.
insert into public.events (business_id, event_name_en, event_name_mr, description_en, description_mr, event_date, start_time, venue_en, venue_mr, enquiry_number, website_url, poster_url, is_active)
select b.id, coalesce(e->'title'->>'en', e->'eventName'->>'en', e->'title'->>'mr', 'Untitled event'), coalesce(e->'title'->>'mr', e->'eventName'->>'mr', ''), coalesce(e->'description'->>'en', ''), coalesce(e->'description'->>'mr', ''), coalesce(e->>'date', ''), coalesce(e->>'time', ''), coalesce(e->'venue'->>'en', e->'venue'->>'mr', ''), coalesce(e->'venue'->>'mr', ''), coalesce(e->>'enquiryNo', ''), nullif(e->>'eventLink', ''), nullif(coalesce(e->>'photo', e->>'image'), ''), coalesce((e->>'isActive')::boolean, true)
from public.businesses b cross join lateral jsonb_array_elements(case when jsonb_typeof(b.details->'events') = 'array' then b.details->'events' else '[]'::jsonb end) e
where not exists (select 1 from public.events existing where existing.business_id = b.id and existing.event_name_en = coalesce(e->'title'->>'en', e->'eventName'->>'en', e->'title'->>'mr', 'Untitled event'));

insert into public.offers (business_id, offer_title_en, offer_title_mr, discount_badge_en, discount_badge_mr, coupon_code, validity_en, validity_mr, terms_en, terms_mr, is_active)
select b.id, coalesce(o->'title'->>'en', o->'title'->>'mr', 'Untitled offer'), coalesce(o->'title'->>'mr', ''), coalesce(o->'discountBadge'->>'en', ''), coalesce(o->'discountBadge'->>'mr', ''), coalesce(nullif(o->>'couponCode', ''), 'legacy-' || md5(o::text)), coalesce(o->'validUntil'->>'en', ''), coalesce(o->'validUntil'->>'mr', ''), coalesce(o->'description'->>'en', ''), coalesce(o->'description'->>'mr', ''), coalesce((o->>'isActive')::boolean, true)
from public.businesses b cross join lateral jsonb_array_elements(case when jsonb_typeof(b.details->'offers') = 'array' then b.details->'offers' else '[]'::jsonb end) o
where not exists (select 1 from public.offers existing where existing.business_id = b.id and existing.coupon_code = coalesce(nullif(o->>'couponCode', ''), 'legacy-' || md5(o::text)));

insert into public.gallery_photos (business_id, image_url, caption, category, is_active)
select b.id, coalesce(nullif(g->>'url', ''), g->>'imageUrl'), coalesce(g->'caption'->>'en', g->'caption'->>'mr', g->>'caption', ''), coalesce(g->'category'->>'en', g->'category'->>'mr', g->>'category', ''), true
from public.businesses b cross join lateral jsonb_array_elements(case when jsonb_typeof(b.details->'gallery') = 'array' then b.details->'gallery' else '[]'::jsonb end) g
where coalesce(nullif(g->>'url', ''), g->>'imageUrl') is not null and not exists (select 1 from public.gallery_photos existing where existing.business_id = b.id and existing.image_url = coalesce(nullif(g->>'url', ''), g->>'imageUrl'));


-- Migration 003_unique_business_slugs.sql
-- Keep public digital-card URLs unique for all existing installations.
create unique index if not exists idx_businesses_slug on public.businesses(slug);


-- Migration 004_create_business_visibility.sql
create table if not exists public.business_section_visibility (
  business_id uuid primary key references public.businesses(id) on delete cascade,
  products boolean not null default true,
  services boolean not null default true,
  special_offers boolean not null default true,
  photo_gallery boolean not null default true,
  upcoming_events boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.business_section_visibility enable row level security;

create policy "Business visibility owner manage" on public.business_section_visibility
  for all using (exists (select 1 from public.businesses b where b.id = business_id and b.owner_id = auth.uid()))
  with check (exists (select 1 from public.businesses b where b.id = business_id and b.owner_id = auth.uid()));

create policy "Business visibility public read" on public.business_section_visibility
  for select using (exists (select 1 from public.businesses b where b.id = business_id and b.is_published = true));


-- Migration 005_add_business_marathi_fields.sql
-- Add nullable Marathi values without changing existing English data.
alter table public.businesses add column if not exists business_name_mr text;
alter table public.businesses add column if not exists category_mr text;
alter table public.businesses add column if not exists owner_name_mr text;
alter table public.businesses add column if not exists designation_mr text;
alter table public.businesses add column if not exists tagline_mr text;
alter table public.businesses add column if not exists description_mr text;


-- Migration 006_add_logo_public_id.sql
alter table public.businesses add column if not exists logo_public_id text;


-- Migration 007_add_image_public_ids.sql
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



-- Migration 008_add_dynamic_social_links.sql
-- 008_add_dynamic_social_links.sql
-- Preserve the current JSON-based social_links field and normalize data for dynamic platform keys.

alter table public.businesses
  add column if not exists social_links jsonb default '{}'::jsonb;

update public.businesses
set social_links = coalesce(social_links, '{}'::jsonb)
where social_links is null;

-- Backfill legacy social URL columns only when that legacy schema is present.
-- The clean base schema stores social links in JSON and has no *_url columns.
do $$
begin
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'businesses' and column_name = 'instagram_url'
  ) and exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'businesses' and column_name = 'facebook_url'
  ) and exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'businesses' and column_name = 'linkedin_url'
  ) and exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'businesses' and column_name = 'youtube_url'
  ) and exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'businesses' and column_name = 'website_url'
  ) then
    execute $sql$
      update public.businesses
      set social_links = jsonb_strip_nulls(jsonb_build_object(
        'instagram', nullif(trim(instagram_url), ''),
        'facebook', nullif(trim(facebook_url), ''),
        'linkedin', nullif(trim(linkedin_url), ''),
        'youtube', nullif(trim(youtube_url), ''),
        'website', nullif(trim(website_url), ''),
        'whatsapp', nullif(trim(whatsapp_number), '')
      ))
      where social_links is null or jsonb_typeof(social_links) = 'null'
    $sql$;
  end if;
end $$;

-- Legacy columns may exist in some installations; this migration keeps them intact while supporting a category-driven JSON model.
-- No destructive drop is performed here to preserve data compatibility.



-- Migration 009_optional_prices_and_business_people.sql
-- Price zero was the historical implicit default for an omitted value.  The
-- application now treats zero as unset; make that state explicit for new data.
alter table public.products alter column price drop default;
alter table public.products alter column price drop not null;
update public.products set price = null where price = 0;

alter table public.services alter column starting_price drop not null;
update public.services set starting_price = null where starting_price = 0;

-- Offers did not previously have media fields. Nullable columns keep existing
-- offers unchanged while allowing the public image-detail interaction.
alter table public.offers add column if not exists image_url text;
alter table public.offers add column if not exists image_public_id text;

create table if not exists public.business_people (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  full_name_en text not null,
  full_name_mr text,
  designation_en text,
  designation_mr text,
  description_en text,
  description_mr text,
  profile_image_url text,
  profile_image_public_id text,
  display_order integer not null default 0 check (display_order >= 0),
  is_primary boolean not null default false,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_business_people_active_order
  on public.business_people (business_id, is_active, display_order);
create unique index if not exists idx_business_people_one_primary
  on public.business_people (business_id) where is_primary and is_active;

-- One idempotent legacy profile per business. Existing columns/details stay
-- untouched so older consumers continue to receive the original owner fields.
insert into public.business_people (
  business_id, full_name_en, full_name_mr, designation_en, designation_mr,
  profile_image_url, profile_image_public_id, display_order, is_primary
)
select b.id,
  coalesce(nullif(trim(b.details->'ownerName'->>'en'), ''), nullif(trim(b.details->>'ownerName'), ''), nullif(trim(b.business_name), ''), 'Business owner'),
  nullif(trim(coalesce(b.owner_name_mr, b.details->'ownerName'->>'mr', '')), ''),
  nullif(trim(coalesce(b.details->'designation'->>'en', b.details->>'designation', '')), ''),
  nullif(trim(coalesce(b.designation_mr, b.details->'designation'->>'mr', '')), ''),
  coalesce(nullif(b.profile_image_url, ''), nullif(b.details->>'profileImage', '')),
  coalesce(nullif(b.profile_image_public_id, ''), nullif(b.details->>'profileImagePublicId', '')),
  0, true
from public.businesses b
where not exists (select 1 from public.business_people p where p.business_id = b.id);

alter table public.business_people enable row level security;
create policy "Business people: owner full access" on public.business_people
  for all using (exists (select 1 from public.businesses b where b.id = business_people.business_id and b.owner_id = auth.uid()))
  with check (exists (select 1 from public.businesses b where b.id = business_people.business_id and b.owner_id = auth.uid()));
create policy "Business people: public select active" on public.business_people
  for select using (is_active and exists (select 1 from public.businesses b where b.id = business_people.business_id and b.is_published = true));



-- Migration 010_category_folders.sql
-- Safe to rerun after a partial or completed installation. Existing data is preserved.
begin;
create table if not exists public.business_categories (
 id uuid primary key default gen_random_uuid(),
 business_id uuid not null references public.businesses(id) on delete cascade,
 type text not null check (type in ('product','service')),
 name text not null check (length(trim(name)) between 1 and 100),
 image_url text not null default '',
 display_order integer not null default 0,
 is_published boolean not null default true,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(id,business_id,type)
);
alter table public.business_categories add column if not exists legacy_category_id uuid;
create unique index if not exists business_categories_legacy_scope_idx
 on public.business_categories(business_id,type,legacy_category_id);
create index if not exists business_categories_business_type_order_idx on public.business_categories(business_id,type,display_order);
alter table public.products
 add column if not exists folder_category_id uuid,
 add column if not exists category_type text generated always as ('product'::text) stored,
 add column if not exists is_published boolean not null default true,
 add column if not exists folder_assignment_migrated boolean not null default false;
alter table public.services
 add column if not exists folder_category_id uuid,
 add column if not exists category_type text generated always as ('service'::text) stored,
 add column if not exists is_published boolean not null default true,
 add column if not exists folder_assignment_migrated boolean not null default false;

-- The deployed schema uses products.category_id/services.category_id for the
-- shared listing_categories taxonomy. Preserve those columns and their FKs.
-- Import only assigned legacy categories, once per business and item type.
do $$
declare item_table text; item_type text;
begin
 if to_regclass('public.listing_categories') is not null then
  foreach item_table in array array['products','services'] loop
   item_type := case when item_table='products' then 'product' else 'service' end;
   if exists(select 1 from information_schema.columns where table_schema='public'
     and table_name=item_table and column_name='category_id') then
    execute format($import$
     insert into public.business_categories
      (business_id,type,name,image_url,display_order,is_published,legacy_category_id)
     select distinct i.business_id,%L,
      left(coalesce(nullif(trim(c.name),''),'Imported category'),100),
      coalesce(c.image_url,''),coalesce(c.display_order,0),coalesce(c.is_active,true),c.id
     from public.%I i join public.listing_categories c on c.id=i.category_id
     where not i.folder_assignment_migrated
     on conflict(business_id,type,legacy_category_id) do nothing
    $import$,item_type,item_table);
    execute format($assign$
     update public.%I i set folder_category_id=c.id, folder_assignment_migrated=true
     from public.business_categories c
     where c.business_id=i.business_id and c.type=%L
      and c.legacy_category_id=i.category_id and i.folder_category_id is null and not i.folder_assignment_migrated
    $assign$,item_table,item_type);
   end if;
  end loop;
 end if;
end $$;
update public.products set folder_assignment_migrated=true where not folder_assignment_migrated;
update public.services set folder_assignment_migrated=true where not folder_assignment_migrated;
alter table public.products alter column folder_assignment_migrated set default true;
alter table public.services alter column folder_assignment_migrated set default true;

-- ADD COLUMN IF NOT EXISTS does not add a missing FK to an existing column.
-- Install the constraints separately, preserving existing rows and assignments.
do $$
declare item_table text; category_column smallint;
begin
 if not exists (
  select 1 from pg_constraint where conrelid='public.business_categories'::regclass
  and contype='u' and conkey=array[
   (select attnum from pg_attribute where attrelid='public.business_categories'::regclass and attname='id'),
   (select attnum from pg_attribute where attrelid='public.business_categories'::regclass and attname='business_id'),
   (select attnum from pg_attribute where attrelid='public.business_categories'::regclass and attname='type')
  ]::smallint[]
 ) then
  alter table public.business_categories add constraint business_categories_scope_unique unique(id,business_id,type);
 end if;
 foreach item_table in array array['products','services'] loop
  select attnum into category_column from pg_attribute
   where attrelid=format('public.%I',item_table)::regclass and attname='folder_category_id';
  if not exists (
   select 1 from pg_constraint where conrelid=format('public.%I',item_table)::regclass
   and contype='f' and confrelid='public.business_categories'::regclass
   and conkey=array[category_column] and confdeltype='n'
  ) then
   execute format('alter table public.%I add constraint %I foreign key(folder_category_id) references public.business_categories(id) on delete set null',item_table,item_table || '_business_folder_fk');
  end if;
  if not exists (
   select 1 from pg_constraint where conrelid=format('public.%I',item_table)::regclass
   and conname=item_table || '_folder_scope'
  ) then
   execute format('alter table public.%I add constraint %I foreign key(folder_category_id,business_id,category_type) references public.business_categories(id,business_id,type)',item_table,item_table || '_folder_scope');
  end if;
 end loop;
end $$;
create index if not exists products_business_folder_category_idx on public.products(business_id,folder_category_id);
create index if not exists services_business_folder_category_idx on public.services(business_id,folder_category_id);
alter table public.business_categories enable row level security;
drop policy if exists "Category owner access" on public.business_categories;
create policy "Category owner access" on public.business_categories for all
 using (exists(select 1 from public.businesses b where b.id=business_id and b.owner_id=auth.uid()))
 with check (exists(select 1 from public.businesses b where b.id=business_id and b.owner_id=auth.uid()));
drop policy if exists "Published categories" on public.business_categories;
create policy "Published categories" on public.business_categories for select using (
 is_published and exists(select 1 from public.businesses b where b.id=business_id and b.is_published)
);
-- Restrictive policies also protect direct Supabase reads alongside existing policies.
drop policy if exists "Product publication boundary" on public.products;
create policy "Product publication boundary" on public.products as restrictive for select using (
 exists(select 1 from public.businesses b where b.id=business_id and b.owner_id=auth.uid())
 or (is_published and (folder_category_id is null or exists(select 1 from public.business_categories c where c.id=folder_category_id and c.is_published)))
);
drop policy if exists "Service publication boundary" on public.services;
create policy "Service publication boundary" on public.services as restrictive for select using (
 exists(select 1 from public.businesses b where b.id=business_id and b.owner_id=auth.uid())
 or (is_published and (folder_category_id is null or exists(select 1 from public.business_categories c where c.id=folder_category_id and c.is_published)))
);
-- Atomic bulk moves validate every requested record before updating any record.
create or replace function public.move_category_items(p_business uuid,p_type text,p_ids uuid[],p_category uuid)
returns void language plpgsql security invoker set search_path=public as $$
declare matched integer;
begin
 if p_type not in ('product','service') or cardinality(p_ids) < 1 then raise exception 'Invalid move'; end if;
 if p_category is not null and not exists(select 1 from business_categories where id=p_category and business_id=p_business and type=p_type) then raise exception 'Invalid category'; end if;
 if p_type='product' then
  perform id from products where business_id=p_business and id=any(p_ids) for update;
  select count(*) into matched from products where business_id=p_business and id=any(p_ids);
 else
  perform id from services where business_id=p_business and id=any(p_ids) for update;
  select count(*) into matched from services where business_id=p_business and id=any(p_ids);
 end if;
 if matched <> cardinality(p_ids) then raise exception 'Invalid items'; end if;
 if p_type='product' then update products set folder_category_id=p_category,updated_at=now() where business_id=p_business and id=any(p_ids);
 else update services set folder_category_id=p_category,updated_at=now() where business_id=p_business and id=any(p_ids); end if;
end $$;
revoke all on function public.move_category_items(uuid,text,uuid[],uuid) from public,anon,authenticated;
grant execute on function public.move_category_items(uuid,text,uuid[],uuid) to service_role;
create or replace function public.reorder_categories(p_business uuid,p_type text,p_ids uuid[])
returns void language plpgsql security invoker set search_path=public as $$
begin
 perform id from business_categories where business_id=p_business and type=p_type for update;
 if (select count(*) from business_categories where business_id=p_business and type=p_type) <> cardinality(p_ids)
 or (select count(distinct id) from unnest(p_ids) id) <> cardinality(p_ids)
 or exists(select 1 from unnest(p_ids) requested(id) where not exists(select 1 from business_categories c where c.id=requested.id and c.business_id=p_business and c.type=p_type)) then raise exception 'Category list changed; refresh and try again'; end if;
 update business_categories c set display_order=o.position-1,updated_at=now()
 from unnest(p_ids) with ordinality o(id,position) where c.id=o.id and c.business_id=p_business and c.type=p_type;
end $$;
revoke all on function public.reorder_categories(uuid,text,uuid[]) from public,anon,authenticated;
grant execute on function public.reorder_categories(uuid,text,uuid[]) to service_role;
commit;



-- Migration 011_bilingual_category_names.sql
-- Run after 010_category_folders.sql. Existing category names remain unchanged.
begin;
alter table public.business_categories
 add column if not exists name_mr text not null default '';
commit;



-- Migration 012_explore_catalog.sql
-- Public catalog projection. Keep grants service-only; Express exposes validated queries.
-- Requires migrations 010 and 011. Does not alter existing product assignments.
begin;
alter table public.products add column if not exists images jsonb not null default '[]'::jsonb;
alter table public.products add column if not exists specifications jsonb not null default '{}'::jsonb;
create or replace view public.explore_products as
select p.id, p.business_id, coalesce(nullif(p.name_en,''),p.name) as name,
 p.name_mr, coalesce(p.description_en,p.description,'') as description,
 p.description_mr, p.price, p.image_url as image, p.is_available as available,
 p.created_at, p.sort_order, p.images, p.specifications,
 coalesce(nullif(b.details->'category'->>'en',''),nullif(b.category,''),'Other') as category,
 coalesce(nullif(c.name,''),nullif(p.category_en,''),nullif(p.category,''),'Other') as subcategory,
 coalesce(nullif(c.image_url,''),p.image_url,'') as category_image,
 jsonb_build_object('id',b.id,'slug',b.slug,'name',b.business_name,
 'logo',coalesce(b.details->>'logo',b.logo_url,''),
 'phone',coalesce(b.details->>'phone',b.phone,''),
 'whatsapp',coalesce(b.details->>'whatsapp',b.whatsapp_number,''),
 'address',coalesce(b.details->'address',to_jsonb(b.address)),
 'verified',b.is_verified) as seller
from public.products p join public.businesses b on b.id=p.business_id
left join public.business_categories c on c.id=p.folder_category_id and c.business_id=p.business_id and c.type='product'
where b.is_published=true and p.is_published=true
and (p.folder_category_id is null or c.is_published=true)
and not exists (select 1 from public.business_section_visibility v where v.business_id=b.id and v.products=false);
revoke all on public.explore_products from anon, authenticated;
grant select on public.explore_products to service_role;
create or replace function public.explore_facets() returns jsonb
language sql stable security invoker set search_path=public as $$
 select coalesce(jsonb_agg(to_jsonb(f)),'[]'::jsonb) from (
 select category, subcategory, min(nullif(category_image,'')) as image,
 count(*) as count,
 jsonb_agg(distinct specifications->>'Metal') filter (where specifications->>'Metal' is not null) as metals,
 jsonb_agg(distinct specifications->>'Purity') filter (where specifications->>'Purity' is not null) as purities,
 jsonb_agg(distinct jsonb_build_object('id',business_id,'name',seller->>'name')) as sellers
 from public.explore_products group by category,subcategory order by category,subcategory
 ) f;
$$;
revoke all on function public.explore_facets() from public, anon, authenticated;
grant execute on function public.explore_facets() to service_role;
commit;



-- Migration 013_explore_services.sql
-- Service discovery using existing published services and service folders.
-- Apply after migrations 010–012. Safe to rerun.
begin;
create or replace view public.explore_services as
select p.id, p.business_id, coalesce(nullif(p.name_en,''),p.name) as name,
 p.name_mr, coalesce(p.details_en,p.details,'') as description,
 p.details_mr as description_mr, case when p.starting_price > 0 then p.starting_price else null end as price, p.cover_image as image, null::boolean as available,
 p.created_at, 0 as sort_order, '[]'::jsonb as images, jsonb_strip_nulls(jsonb_build_object('Duration',nullif(p.duration_en,''))) as specifications, 'service'::text as kind,
 coalesce(nullif(b.details->'category'->>'en',''),nullif(b.category,''),'Other') as category,
 coalesce(nullif(c.name,''),nullif(p.category_en,''),'Other') as subcategory,
 coalesce(nullif(c.image_url,''),p.cover_image,'') as category_image,
 jsonb_build_object('id',b.id,'slug',b.slug,'name',b.business_name,
 'logo',coalesce(b.details->>'logo',b.logo_url,''),
 'phone',coalesce(b.details->>'phone',b.phone,''),
 'whatsapp',coalesce(b.details->>'whatsapp',b.whatsapp_number,''),
 'address',coalesce(b.details->'address',to_jsonb(b.address)),
 'verified',b.is_verified) as seller
from public.services p join public.businesses b on b.id=p.business_id
left join public.business_categories c on c.id=p.folder_category_id and c.business_id=p.business_id and c.type='service'
where b.is_published=true and p.is_published=true
and (p.folder_category_id is null or c.is_published=true)
and not exists (select 1 from public.business_section_visibility v where v.business_id=b.id and v.services=false);
revoke all on public.explore_services from anon, authenticated;
grant select on public.explore_services to service_role;
create or replace function public.explore_service_facets() returns jsonb
language sql stable security invoker set search_path=public as $$
 select coalesce(jsonb_agg(to_jsonb(f)),'[]'::jsonb) from (
 select category, subcategory, min(nullif(category_image,'')) as image,
 count(*) as count,
 jsonb_agg(distinct jsonb_build_object('id',business_id,'name',seller->>'name')) as sellers
 from public.explore_services group by category,subcategory order by category,subcategory
 ) f;
$$;
revoke all on function public.explore_service_facets() from public, anon, authenticated;
grant execute on function public.explore_service_facets() to service_role;
commit;



-- Migration 014_business_packages.sql
-- Apply after 001-013. Transactional, rerunnable; never deletes existing content.
begin;
lock table public.businesses, public.products, public.services, public.events,
  public.offers, public.gallery_photos in share row exclusive mode;

-- The authoritative package matrix. NULL limit means enabled with no quota.
create table if not exists public.business_package_rules (
  plan_id text primary key,
  capabilities jsonb not null
);
insert into public.business_package_rules values
 ('basic', '{"products":0,"services":0,"gallery":20,"events":5,"offers":0,"themes":false,"verificationViews":null}'),
 ('standard', '{"products":20,"services":20,"gallery":20,"events":5,"offers":0,"themes":false,"verificationViews":10000}'),
 ('premium', '{"products":20,"services":20,"gallery":20,"events":5,"offers":null,"themes":true,"verificationViews":0}')
on conflict (plan_id) do update set capabilities = excluded.capabilities;
-- Legacy "free" has no independent entitlement; normalize to Basic. Unknown plans fail closed.
update public.businesses set plan_id = 'basic' where plan_id not in ('basic','standard','premium');
alter table public.businesses alter column plan_id set default 'basic';
alter table public.businesses drop constraint if exists businesses_package_fk;
alter table public.businesses add constraint businesses_package_fk foreign key (plan_id) references public.business_package_rules(plan_id);
alter table public.businesses add column if not exists profile_views bigint not null default 0 check (profile_views >= 0);

create table if not exists public.business_package_usage (
 business_id uuid not null references public.businesses(id) on delete cascade,
 resource text not null check (resource in ('products','services','gallery','events','offers')),
 used integer not null default 0 check (used >= 0), primary key (business_id,resource)
);
insert into public.business_package_usage(business_id,resource,used)
select b.id, r.resource, case r.resource
 when 'products' then (select count(*) from public.products p where p.business_id=b.id)
 when 'services' then (select count(*) from public.services p where p.business_id=b.id)
 when 'gallery' then (select count(*) from public.gallery_photos p where p.business_id=b.id and p.is_active and p.deleted_at is null)
 when 'events' then (select count(*) from public.events p where p.business_id=b.id and p.is_active and p.deleted_at is null)
 when 'offers' then (select count(*) from public.offers p where p.business_id=b.id and p.is_active and p.deleted_at is null) end
from public.businesses b cross join (values ('products'),('services'),('gallery'),('events'),('offers')) r(resource)
on conflict (business_id,resource) do update set used=excluded.used;

-- Direct Supabase writes must not bypass the trusted Express authorization path.
-- All writes use the service-role backend, which checks business ownership/admin status.
revoke insert, update, delete on public.businesses, public.products, public.services,
 public.events, public.offers, public.gallery_photos, public.business_categories,
 public.business_section_visibility from anon, authenticated;

alter table public.business_package_rules enable row level security;
alter table public.business_package_usage enable row level security;
revoke all on public.business_package_rules, public.business_package_usage from public, anon, authenticated;
grant select on public.business_package_rules, public.business_package_usage to service_role;

-- Shared database enforcement covers inserts, bulk inserts, restores and publication
-- transitions, including writes through future routes and service-role SQL/RPCs.
create or replace function public.enforce_business_package_content() returns trigger
language plpgsql security definer set search_path=public as $$
declare
 v_resource text := case when tg_table_name='gallery_photos' then 'gallery' else tg_table_name end;
 business uuid; caps jsonb; quota integer; before_counted boolean := false;
 after_counted boolean := false; publish_transition boolean := false; delta integer;
 old_row jsonb; new_row jsonb;
begin
 if tg_op <> 'INSERT' then old_row:=to_jsonb(old); end if;
 if tg_op <> 'DELETE' then new_row:=to_jsonb(new); end if;
 business:=coalesce((new_row->>'business_id')::uuid,(old_row->>'business_id')::uuid);
 if tg_op='UPDATE' and new.business_id <> old.business_id then
   raise exception 'Moving content between businesses is not supported';
 end if;
 -- Serializes quota changes with package activation/downgrade for this business.
 perform 1 from public.businesses where id=business for update;
 if not found and tg_op='DELETE' then return old; end if; -- parent cascade
 select r.capabilities into caps from public.businesses b join public.business_package_rules r using(plan_id) where b.id=business;
 if caps is null then raise exception 'Business package is unavailable'; end if;
 quota:=(caps->>v_resource)::integer;
 if v_resource in ('products','services') then
   before_counted:=tg_op <> 'INSERT'; after_counted:=tg_op <> 'DELETE';
   publish_transition:=tg_op='UPDATE' and not coalesce((old_row->>'is_published')::boolean,true)
      and coalesce((new_row->>'is_published')::boolean,true);
 else
   before_counted:=tg_op <> 'INSERT' and coalesce((old_row->>'is_active')::boolean,true) and old_row->>'deleted_at' is null;
   after_counted:=tg_op <> 'DELETE' and coalesce((new_row->>'is_active')::boolean,true) and new_row->>'deleted_at' is null;
   publish_transition:=after_counted and not before_counted;
 end if;
 if quota=0 and (tg_op='INSERT' or publish_transition) then
   raise exception '% requires %', initcap(v_resource), case when v_resource='offers' then 'Premium' else 'Standard or Premium' end;
 end if;
 -- A move out of a hidden folder is also a publication transition.
 if tg_op='UPDATE' and v_resource in ('products','services')
    and new_row->>'folder_category_id' is distinct from old_row->>'folder_category_id'
    and coalesce((new_row->>'is_published')::boolean,true)
    and exists(select 1 from public.business_categories c where c.id=(old_row->>'folder_category_id')::uuid and not c.is_published)
    and (new_row->>'folder_category_id' is null or exists(select 1 from public.business_categories c where c.id=(new_row->>'folder_category_id')::uuid and c.is_published))
    and quota=0 then raise exception '% requires Standard or Premium',initcap(v_resource); end if;
 delta:=after_counted::integer-before_counted::integer;
 insert into public.business_package_usage(business_id,resource,used) values(business,v_resource,0) on conflict do nothing;
 if delta > 0 then
   update public.business_package_usage u set used=used+delta
     where u.business_id=business and u.resource=v_resource
       and (quota is null or used+delta <= quota);
   if not found then raise exception '% limit reached (maximum %)',initcap(v_resource),quota; end if;
 elsif delta < 0 then
   update public.business_package_usage u set used=greatest(0,used+delta)
    where u.business_id=business and u.resource=v_resource;
 end if;
 if tg_op='DELETE' then return old; end if;
 return new;
end $$;

do $$ declare t text; begin
 foreach t in array array['products','services','gallery_photos','events','offers'] loop
   execute format('drop trigger if exists enforce_package on public.%I',t);
   execute format('create trigger enforce_package before insert or update or delete on public.%I for each row execute function public.enforce_business_package_content()',t);
 end loop;
end $$;

-- Re-enabling a hidden folder/section/profile must not republish excluded content.
create or replace function public.enforce_business_package_publication() returns trigger
language plpgsql security definer set search_path=public as $$
declare caps jsonb; business uuid; begin
 business:=case when tg_table_name='businesses' then (to_jsonb(new)->>'id')::uuid else (to_jsonb(new)->>'business_id')::uuid end;
 perform 1 from public.businesses where id=business for update;
 select r.capabilities into caps from public.businesses b join public.business_package_rules r using(plan_id) where b.id=business;
 if tg_table_name='businesses' then select capabilities into caps from public.business_package_rules where plan_id=new.plan_id; end if;
 if tg_table_name='business_categories' then
   if new.is_published and not old.is_published and (caps->>(new.type||'s'))::integer=0 then
     raise exception '% requires Standard or Premium',initcap(new.type||'s');
   end if;
 elsif tg_table_name='business_section_visibility' then
   if new.products and not old.products and (caps->>'products')::integer=0 and exists(select 1 from products where business_id=business and is_published) then raise exception 'Products requires Standard or Premium'; end if;
   if new.services and not old.services and (caps->>'services')::integer=0 and exists(select 1 from services where business_id=business and is_published) then raise exception 'Services requires Standard or Premium'; end if;
   if new.special_offers and not old.special_offers and (caps->>'offers')::integer=0 and exists(select 1 from offers where business_id=business and is_active and deleted_at is null) then raise exception 'Offers requires Premium'; end if;
 elsif new.is_published and not old.is_published then
   if (caps->>'products')::integer=0 and exists(select 1 from products where business_id=business and is_published) then raise exception 'Products requires Standard or Premium'; end if;
   if (caps->>'services')::integer=0 and exists(select 1 from services where business_id=business and is_published) then raise exception 'Services requires Standard or Premium'; end if;
   if (caps->>'offers')::integer=0 and exists(select 1 from offers where business_id=business and is_active and deleted_at is null) then raise exception 'Offers requires Premium'; end if;
 end if;
 return new;
end $$;
do $$ declare t text; begin
 foreach t in array array['businesses','business_categories','business_section_visibility'] loop
  execute format('drop trigger if exists enforce_package_publication on public.%I',t);
  execute format('create trigger enforce_package_publication before update on public.%I for each row execute function public.enforce_business_package_publication()',t);
 end loop;
end $$;
revoke all on function public.enforce_business_package_publication() from public,anon,authenticated;

-- Reuse is_verified (the same state used by the administrative verification click).
-- No downgrade or unrelated edit revokes a manual or package-granted badge.
create or replace function public.apply_business_package() returns trigger
language plpgsql security definer set search_path=public as $$
declare caps jsonb; threshold bigint; begin
 select capabilities into caps from public.business_package_rules where plan_id=new.plan_id;
 threshold:=(caps->>'verificationViews')::bigint;
 if threshold is not null and new.profile_views >= threshold then new.is_verified:=true; end if;
 if tg_op='INSERT' and caps->>'themes' <> 'true' and
   (coalesce(new.details->'themeConfig','null'::jsonb) <> 'null'::jsonb
    or coalesce(new.details->'themeDraft','null'::jsonb) <> 'null'::jsonb
    or coalesce(new.details->>'templateId','corporate-navy') <> 'corporate-navy'
    or coalesce(new.details->>'themeColor','#0f172a') <> '#0f172a'
    or coalesce(new.details->>'accentColor','#2563eb') <> '#2563eb'
    or coalesce(new.details->>'fontFamily','Outfit') <> 'Outfit') then
   raise exception 'Theme/template customization requires Premium';
 end if;
 if tg_op='UPDATE' and caps->>'themes' <> 'true' and
   (new.details->'themeConfig' is distinct from old.details->'themeConfig'
    or new.details->'themeDraft' is distinct from old.details->'themeDraft'
    or new.details->'templateId' is distinct from old.details->'templateId'
    or new.details->'themeColor' is distinct from old.details->'themeColor'
    or new.details->'accentColor' is distinct from old.details->'accentColor'
    or new.details->'fontFamily' is distinct from old.details->'fontFamily') then
   raise exception 'Theme/template customization requires Premium';
 end if;
 return new;
end $$;
drop trigger if exists apply_package on public.businesses;
create trigger apply_package before insert or update on public.businesses for each row execute function public.apply_business_package();
-- Idempotent reconciliation: uses only the trusted counter, never legacy details.stats.
update public.businesses set is_verified=true where not is_verified and
 exists (select 1 from public.business_package_rules r where r.plan_id=businesses.plan_id
 and r.capabilities->>'verificationViews' is not null
 and businesses.profile_views >= (r.capabilities->>'verificationViews')::bigint);

create table if not exists public.business_profile_view_visitors (
 business_id uuid not null references public.businesses(id) on delete cascade,
 visitor_hash text not null, view_day date not null default (now() at time zone 'UTC')::date,
 primary key(business_id,visitor_hash,view_day)
);
alter table public.business_profile_view_visitors alter column view_day set default (now() at time zone 'UTC')::date;
alter table public.business_profile_view_visitors enable row level security;
revoke all on public.business_profile_view_visitors from public,anon,authenticated;

create or replace function public.record_business_profile_view(p_slug text,p_visitor_hash text) returns jsonb
language plpgsql security definer set search_path=public as $$
declare b public.businesses; added integer; begin
 select * into b from public.businesses where slug=p_slug and is_published=true for update;
 if not found then raise exception 'Business not found'; end if;
 if p_visitor_hash !~ '^[a-f0-9]{64}$' then raise exception 'Invalid visitor hash'; end if;
 insert into public.business_profile_view_visitors(business_id,visitor_hash) values(b.id,p_visitor_hash) on conflict do nothing;
 get diagnostics added=row_count;
 if added > 0 then update public.businesses set profile_views=profile_views+1 where id=b.id returning * into b; end if;
 return jsonb_build_object('totalViews',b.profile_views,'isVerified',b.is_verified);
end $$;

create or replace function public.get_business_package(p_business uuid) returns jsonb
language sql stable security definer set search_path=public as $$
 select jsonb_build_object('planId',b.plan_id,'capabilities',r.capabilities,
  'usage','{"products":0,"services":0,"gallery":0,"events":0,"offers":0}'::jsonb || coalesce((select jsonb_object_agg(resource,used) from public.business_package_usage where business_id=b.id),'{}'::jsonb))
 from public.businesses b join public.business_package_rules r using(plan_id) where b.id=p_business;
$$;
revoke all on function public.get_business_package(uuid),public.record_business_profile_view(text,text),
 public.enforce_business_package_content(),public.apply_business_package() from public,anon,authenticated;
grant execute on function public.get_business_package(uuid),public.record_business_profile_view(text,text) to service_role;
commit;



-- Migration 015_auth_sessions.sql
-- Run before deploying the persistent authentication backend.
create table if not exists public.auth_sessions (
  id uuid primary key references auth.sessions(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  expires_at timestamptz not null,
  revoked_at timestamptz
);
alter table public.auth_sessions enable row level security;
revoke all on public.auth_sessions from anon, authenticated;
grant all on public.auth_sessions to service_role;
create index if not exists auth_sessions_user_idx on public.auth_sessions(user_id);



-- Migration 016_cloudinary_lifecycle.sql
begin;
-- Private upload ledger doubles as a durable cleanup outbox. Never seed it from
-- old public IDs: migration 007 guessed those IDs from URLs.
create table public.cloudinary_assets (
 public_id text primary key,
 secure_url text not null unique,
 owner_id uuid not null,
 state text not null default 'ready' check (state in ('ready','deleting','deleted')),
 cleanup_after timestamptz not null default (now() + interval '24 hours'),
 attempts integer not null default 0,
 last_error text,
 created_at timestamptz not null default now()
);
alter table public.cloudinary_assets enable row level security;
revoke all on public.cloudinary_assets from public, anon, authenticated;
grant all on public.cloudinary_assets to service_role;

-- Conservative substring matching also protects URL-only gallery entries and
-- transformed URLs. False positives retain storage; they never delete live media.
create function public.cloudinary_row_uses(row_data jsonb, asset public.cloudinary_assets)
returns boolean language sql immutable set search_path = public as $$
 select row_data is not null and position(asset.public_id in row_data::text) > 0
$$;

create function public.track_cloudinary_changes() returns trigger
language plpgsql security definer set search_path = public as $$
declare previous jsonb; upcoming jsonb; asset public.cloudinary_assets; pair text[]; url_value text; verified_id text;
begin
 perform pg_advisory_xact_lock(716016);
 if TG_OP <> 'INSERT' then previous := to_jsonb(OLD); end if;
 if TG_OP <> 'DELETE' then upcoming := to_jsonb(NEW); end if;
 if upcoming is not null then
   -- URL-only clients receive the exact ID returned by the upload API. Clear
   -- stale paired IDs when a URL changes; never infer identity from a URL path.
   foreach pair slice 1 in array array[
     ['logo_url','logo_public_id'], ['profile_image_url','profile_image_public_id'],
     ['image_url','image_public_id'], ['cover_image','cover_image_public_id'],
     ['poster_url','poster_public_id']
   ] loop
     if upcoming ? pair[1] and upcoming ? pair[2] then
       url_value := upcoming->>pair[1];
       select public_id into verified_id from public.cloudinary_assets where secure_url = url_value;
       if verified_id is not null or url_value is distinct from previous->>pair[1] then
         upcoming := jsonb_set(upcoming, array[pair[2]], coalesce(to_jsonb(verified_id), 'null'::jsonb));
       end if;
     end if;
   end loop;
   if TG_TABLE_NAME = 'businesses' then
     upcoming := jsonb_set(upcoming, '{details}', coalesce(upcoming->'details','{}') ||
       jsonb_build_object('logoPublicId',upcoming->'logo_public_id','profileImagePublicId',upcoming->'profile_image_public_id'));
   end if;
   NEW := jsonb_populate_record(NEW, upcoming);
 end if;
 if upcoming->>'deleted_at' is not null then upcoming := null; end if;
 for asset in select * from public.cloudinary_assets
 where public.cloudinary_row_uses(previous, cloudinary_assets)
    or public.cloudinary_row_uses(upcoming, cloudinary_assets)
 order by public_id for update loop
   if public.cloudinary_row_uses(upcoming, asset) then
     if asset.state <> 'ready' then
       raise exception 'Image is being deleted or has been deleted; upload it again';
     end if;
   elsif public.cloudinary_row_uses(previous, asset) and asset.state = 'ready' then
     update public.cloudinary_assets set cleanup_after = now() where public_id = asset.public_id;
   end if;
 end loop;
 if TG_OP = 'DELETE' then return OLD; end if;
 return NEW;
end $$;

do $$ declare tab text; begin
 foreach tab in array array['businesses','business_people','products','services','events','offers','gallery_photos','business_categories'] loop
 execute format('create trigger cloudinary_lifecycle before insert or update or delete on public.%I for each row execute function public.track_cloudinary_changes()', tab);
 end loop;
end $$;

create function public.claim_cloudinary_cleanup() returns setof public.cloudinary_assets
language plpgsql security definer set search_path = public as $$
declare asset public.cloudinary_assets; tab text; used boolean; found_ref boolean;
begin
 -- Same lock as writers. Once claimed, triggers prohibit new references, including
 -- while a timed-out Cloudinary request is being reconciled by an idempotent retry.
 perform pg_advisory_xact_lock(716016);
 for asset in select * from public.cloudinary_assets
 where state <> 'deleted' and cleanup_after <= now()
 order by cleanup_after limit 10 for update loop
   found_ref := false;
   foreach tab in array array['businesses','business_people','products','services','events','offers','gallery_photos','business_categories'] loop
     execute format('select exists(select 1 from public.%I r where to_jsonb(r)->>''deleted_at'' is null and public.cloudinary_row_uses(to_jsonb(r), $1))', tab)
       into used using asset;
     if used then found_ref := true; exit; end if;
   end loop;
   if found_ref then
     update public.cloudinary_assets set cleanup_after = now() + interval '24 hours' where public_id = asset.public_id;
   else
     update public.cloudinary_assets set state = 'deleting', attempts = attempts + 1,
       cleanup_after = now() + interval '5 minutes' where public_id = asset.public_id
       returning * into asset;
     return next asset;
   end if;
 end loop;
end $$;
revoke all on function public.cloudinary_row_uses(jsonb, public.cloudinary_assets) from public, anon, authenticated;
revoke all on function public.track_cloudinary_changes() from public, anon, authenticated;
revoke all on function public.claim_cloudinary_cleanup() from public, anon, authenticated;
grant execute on function public.claim_cloudinary_cleanup() to service_role;
commit;



-- Migration 017_user_management.sql
-- Run after 015. No password material is copied out of Supabase Auth.
begin;
create table public.user_management_audit (
 id uuid primary key default gen_random_uuid(), actor_id uuid, target_id uuid,
 action text not null, outcome text not null check(outcome in ('requested','success','failed','rejected')),
 created_at timestamptz not null default now()
);
create index on public.user_management_audit(target_id, created_at desc);
alter table public.user_management_audit enable row level security;
revoke all on public.user_management_audit from anon, authenticated;
grant select, insert on public.user_management_audit to service_role;

-- Trigger runs in the same transaction as provider changes, including revocation.
create function public.audit_auth_account() returns trigger language plpgsql security definer set search_path = '' as $$
begin
 if TG_OP = 'INSERT' then
  insert into public.user_management_audit(actor_id,target_id,action,outcome)
   values(nullif(new.raw_app_meta_data->>'created_by','')::uuid,new.id,'user_created','success');
 else
  if new.encrypted_password is distinct from old.encrypted_password then
   update public.auth_sessions set revoked_at = now() where user_id=new.id and revoked_at is null;
   insert into public.user_management_audit(actor_id,target_id,action,outcome) values(new.id,new.id,'password_changed','success');
  end if;
  if new.banned_until is distinct from old.banned_until then
   update public.auth_sessions set revoked_at = now() where user_id=new.id and revoked_at is null;
   insert into public.user_management_audit(target_id,action,outcome) values(new.id,'account_status_changed','success');
  end if;
 end if;
 return new;
end $$;
revoke all on function public.audit_auth_account() from public, anon, authenticated;
create trigger audit_auth_account after insert or update on auth.users for each row execute function public.audit_auth_account();

-- Service-only projection: never expose auth.users or its private fields through REST.
create function public.management_users(admin_emails text[], search_text text default '', role_filter text default '', status_filter text default '', date_from timestamptz default null, date_to timestamptz default null, sort_key text default 'created_at', descending boolean default true, page_number integer default 1, target uuid default null)
returns jsonb language sql stable security definer set search_path = '' as $$
 with accounts as (
 select u.id, coalesce(p.full_name,u.raw_user_meta_data->>'full_name','') full_name,u.email,
 case when lower(u.email)=any(admin_emails) then 'admin' else 'user' end role,
 case when u.banned_until > now() then 'inactive' else 'active' end status,
 u.created_at,u.last_sign_in_at last_login,
 u.raw_app_meta_data->>'created_by' created_by,
 u.email_confirmed_at is not null email_verified
 from auth.users u left join public.profiles p on p.id=u.id
 ), filtered as (
 select * from accounts where (target is null or id=target)
 and (search_text='' or position(lower(search_text) in lower(full_name||' '||coalesce(email,'')||' '||id::text))>0)
 and (role_filter='' or role=role_filter) and(status_filter='' or status=status_filter)
 and(date_from is null or created_at>=date_from) and(date_to is null or created_at<date_to)
 ), paged as (
 select * from filtered order by
 case when not descending and sort_key='name' then lower(full_name) end asc,
 case when descending and sort_key='name' then lower(full_name) end desc,
 case when not descending and sort_key='created_at' then created_at end asc,
 case when descending and sort_key='created_at' then created_at end desc,
 case when not descending and sort_key='last_login' then last_login end asc nulls last,
 case when descending and sort_key='last_login' then last_login end desc nulls last,id
 limit 25 offset (greatest(1,least(page_number,1000000))-1)*25
 ) select jsonb_build_object('users',coalesce((select jsonb_agg(to_jsonb(paged)) from paged),'[]'::jsonb),
 'total',(select count(*) from filtered),'summary',(select jsonb_build_object('total',count(*),'active',count(*) filter(where status='active'),'inactive',count(*) filter(where status='inactive'),'this_month',count(*) filter(where created_at>=date_trunc('month',now()))) from accounts));
$$;
revoke all on function public.management_users(text[],text,text,text,timestamptz,timestamptz,text,boolean,integer,uuid) from public,anon,authenticated;
grant execute on function public.management_users(text[],text,text,text,timestamptz,timestamptz,text,boolean,integer,uuid) to service_role;

create function public.management_update_profile(actor uuid,target uuid,new_name text) returns void language plpgsql security definer set search_path = '' as $$
begin
 insert into public.profiles(id,full_name) values(target,new_name) on conflict(id) do update set full_name=excluded.full_name;
 insert into public.user_management_audit(actor_id,target_id,action,outcome) values(actor,target,'profile_updated','success');
end $$;
revoke all on function public.management_update_profile(uuid,uuid,text) from public,anon,authenticated;
grant execute on function public.management_update_profile(uuid,uuid,text) to service_role;
commit;



-- Migration 018_global_category_architecture.sql
-- Replace business-owned folders with a global taxonomy without merging IDs or deleting data.
-- Apply after 017. Deploy the matching API/frontend together. No legacy seed data is imported.
begin;
lock table public.business_categories in access exclusive mode;
-- Global availability cannot be tied to the originating business's package.
-- Item creation, moves, and publication retain their existing package triggers.
drop trigger if exists enforce_package_publication on public.business_categories;
alter table public.business_categories
 alter column business_id drop not null,
 alter column type drop not null,
 add column if not exists parent_id uuid,
 add column if not exists icon text not null default 'Tag',
 add column if not exists status text not null default 'enabled',
 add column if not exists version bigint not null default 1;

-- Original business/type values remain provenance only. They must no longer scope
-- categories or cause global categories to disappear when a business is deleted.
do $$ declare c record; begin
 for c in select conname from pg_constraint where conrelid='public.business_categories'::regclass
  and contype='f' and confrelid='public.businesses'::regclass loop
  execute format('alter table public.business_categories drop constraint %I',c.conname);
 end loop;
 if not exists(select 1 from pg_constraint where conrelid='public.business_categories'::regclass and conname='global_category_parent_fk') then
  alter table public.business_categories add constraint global_category_parent_fk foreign key(parent_id) references public.business_categories(id) on delete restrict;
  alter table public.business_categories add constraint global_category_status check(status in ('enabled','disabled'));
  update public.business_categories set status=case when is_published then 'enabled' else 'disabled' end;
 end if;
end $$;
create index if not exists global_category_parent_idx on public.business_categories(parent_id);
create index if not exists global_category_path_lookup_idx on public.business_categories(parent_id,lower(trim(name)));
create index if not exists global_category_created_idx on public.business_categories(created_at,id);

-- Preserve the old shared taxonomy too. Existing FKs are redirected to the same
-- authoritative table. ID collisions abort rather than silently merge records.
do $$ declare c record; t text; begin
 if to_regclass('public.listing_categories') is not null then
  -- The installed FK marks completed conversion. Reruns must not resurrect
  -- categories that Super Admin deliberately deleted after replacement.
  if not exists(select 1 from pg_constraint where conname='products_global_taxonomy_fk' and conrelid='public.products'::regclass) then
   if exists(select 1 from public.listing_categories l join public.business_categories b on l.id=b.id) then
    raise exception 'Category ID collision: review existing taxonomy before migration';
   end if;
   insert into public.business_categories(id,name,name_mr,image_url,display_order,is_published,status,created_at)
    select l.id,coalesce(nullif(trim(l.name),''),'Imported category'),coalesce(to_jsonb(l)->>'name_mr',''),
     coalesce(to_jsonb(l)->>'image_url',''),coalesce((to_jsonb(l)->>'display_order')::integer,0),
     coalesce((to_jsonb(l)->>'is_active')::boolean,true),
     case when coalesce((to_jsonb(l)->>'is_active')::boolean,true) then 'enabled' else 'disabled' end,
     coalesce((to_jsonb(l)->>'created_at')::timestamptz,now())
    from public.listing_categories l;
  end if;
  -- Keep the old table as a read-only archive; no application code queries it.
  alter table public.listing_categories enable row level security;
  drop policy if exists "Retired taxonomy is read only" on public.listing_categories;
  create policy "Retired taxonomy is read only" on public.listing_categories as restrictive for all to anon,authenticated using(false) with check(false);
 end if;
 foreach t in array array['products','services'] loop
  for c in select conname from pg_constraint where conrelid=format('public.%I',t)::regclass and contype='f'
   and (confrelid='public.business_categories'::regclass or confrelid=to_regclass('public.listing_categories')) loop
   execute format('alter table public.%I drop constraint %I',t,c.conname);
  end loop;
  execute format('alter table public.%I add column if not exists category_id uuid',t);
  execute format('alter table public.%I add constraint %I foreign key(folder_category_id) references public.business_categories(id) on delete restrict',t,t||'_global_folder_fk');
  execute format('alter table public.%I add constraint %I foreign key(category_id) references public.business_categories(id) on delete restrict',t,t||'_global_taxonomy_fk');
 end loop;
end $$;

-- Add optional relations to other existing category-bearing records. Historical
-- free-text labels remain intact until their owner explicitly selects a category.
alter table public.businesses add column if not exists global_category_id uuid references public.business_categories(id) on delete restrict;
alter table public.gallery_photos add column if not exists global_category_id uuid references public.business_categories(id) on delete restrict;
create index if not exists businesses_global_category_idx on public.businesses(global_category_id);
create index if not exists gallery_global_category_idx on public.gallery_photos(global_category_id);
create index if not exists products_global_taxonomy_idx on public.products(category_id);
create index if not exists services_global_taxonomy_idx on public.services(category_id);

-- Ancestor status is authoritative for new selections and public publication.
create or replace function public.global_category_available(p_id uuid) returns boolean
language sql stable security definer set search_path=public as $$
 with recursive ancestors as (
  select id,parent_id,is_published,status from business_categories where id=p_id
  union all select c.id,c.parent_id,c.is_published,c.status from business_categories c join ancestors a on c.id=a.parent_id
 ) select count(*)>0 and bool_and(is_published and status='enabled') from ancestors;
$$;
revoke all on function public.global_category_available(uuid) from public;
grant execute on function public.global_category_available(uuid) to anon,authenticated,service_role;

create or replace function public.guard_global_category() returns trigger
language plpgsql set search_path=public as $$
begin
 perform pg_advisory_xact_lock(184712009);
 if new.parent_id=new.id or exists(
  with recursive ancestors as (
   select id,parent_id from business_categories where id=new.parent_id
   union all select c.id,c.parent_id from business_categories c join ancestors a on c.id=a.parent_id
  ) select 1 from ancestors where id=new.id
 ) then raise exception 'A category cannot be its own ancestor' using errcode='23514'; end if;
 if tg_op='INSERT' then
  if new.status not in ('enabled','disabled') then raise exception 'Invalid status' using errcode='23514'; end if;
  new.is_published := new.status='enabled';
 else
  if new.status is distinct from old.status then new.is_published := new.status='enabled';
  elsif new.is_published is distinct from old.is_published then new.status := case when new.is_published then 'enabled' else 'disabled' end; end if;
  new.version := old.version+1;
 end if;
 new.updated_at := clock_timestamp();
 return new;
end $$;
drop trigger if exists guard_global_category on public.business_categories;
create trigger guard_global_category before insert or update on public.business_categories for each row execute function public.guard_global_category();

-- Retain existing quotas and make the folder-move publication check ancestor-aware.
create or replace function public.enforce_business_package_content() returns trigger
language plpgsql security definer set search_path=public as $$
declare
 v_resource text := case when tg_table_name='gallery_photos' then 'gallery' else tg_table_name end;
 business uuid; caps jsonb; quota integer; before_counted boolean := false;
 after_counted boolean := false; publish_transition boolean := false; delta integer;
 old_row jsonb; new_row jsonb;
begin
 if tg_op <> 'INSERT' then old_row:=to_jsonb(old); end if;
 if tg_op <> 'DELETE' then new_row:=to_jsonb(new); end if;
 business:=coalesce((new_row->>'business_id')::uuid,(old_row->>'business_id')::uuid);
 if tg_op='UPDATE' and new.business_id <> old.business_id then
   raise exception 'Moving content between businesses is not supported';
 end if;
 -- Serializes quota changes with package activation/downgrade for this business.
 perform 1 from public.businesses where id=business for update;
 if not found and tg_op='DELETE' then return old; end if; -- parent cascade
 select r.capabilities into caps from public.businesses b join public.business_package_rules r using(plan_id) where b.id=business;
 if caps is null then raise exception 'Business package is unavailable'; end if;
 quota:=(caps->>v_resource)::integer;
 if v_resource in ('products','services') then
   before_counted:=tg_op <> 'INSERT'; after_counted:=tg_op <> 'DELETE';
   publish_transition:=tg_op='UPDATE' and not coalesce((old_row->>'is_published')::boolean,true)
      and coalesce((new_row->>'is_published')::boolean,true);
 else
   before_counted:=tg_op <> 'INSERT' and coalesce((old_row->>'is_active')::boolean,true) and old_row->>'deleted_at' is null;
   after_counted:=tg_op <> 'DELETE' and coalesce((new_row->>'is_active')::boolean,true) and new_row->>'deleted_at' is null;
   publish_transition:=after_counted and not before_counted;
 end if;
 if quota=0 and (tg_op='INSERT' or publish_transition) then
   raise exception '% requires %', initcap(v_resource), case when v_resource='offers' then 'Premium' else 'Standard or Premium' end;
 end if;
 -- A move out of a hidden folder is also a publication transition.
 if tg_op='UPDATE' and v_resource in ('products','services')
    and new_row->>'folder_category_id' is distinct from old_row->>'folder_category_id'
    and coalesce((new_row->>'is_published')::boolean,true)
    and not public.global_category_available((old_row->>'folder_category_id')::uuid)
    and (new_row->>'folder_category_id' is null or public.global_category_available((new_row->>'folder_category_id')::uuid))
    and quota=0 then raise exception '% requires Standard or Premium',initcap(v_resource); end if;
 delta:=after_counted::integer-before_counted::integer;
 insert into public.business_package_usage(business_id,resource,used) values(business,v_resource,0) on conflict do nothing;
 if delta > 0 then
   update public.business_package_usage u set used=used+delta
     where u.business_id=business and u.resource=v_resource
       and (quota is null or used+delta <= quota);
   if not found then raise exception '% limit reached (maximum %)',initcap(v_resource),quota; end if;
 elsif delta < 0 then
   update public.business_package_usage u set used=greatest(0,used+delta)
    where u.business_id=business and u.resource=v_resource;
 end if;
 if tg_op='DELETE' then return old; end if;
 return new;
end $$;

-- Enabling or reparenting a global node must retain the existing package
-- republication boundary for every affected business, including descendants.
create or replace function public.previous_global_category_available(p_id uuid,p_changed uuid,p_parent uuid,p_status text,p_published boolean)
returns boolean language sql stable security definer set search_path=public as $$
 with recursive previous_nodes as (
  select id,case when id=p_changed then p_parent else parent_id end as parent_id,
   case when id=p_changed then p_status else status end as status,
   case when id=p_changed then p_published else is_published end as is_published
  from business_categories
 ), ancestors as (
  select * from previous_nodes where id=p_id
  union all select c.* from previous_nodes c join ancestors a on c.id=a.parent_id
 ) select count(*)>0 and bool_and(is_published and status='enabled') from ancestors;
$$;
revoke all on function public.previous_global_category_available(uuid,uuid,uuid,text,boolean) from public,anon,authenticated;
create or replace function public.guard_global_category_publication() returns trigger
language plpgsql security definer set search_path=public as $$
declare affected record; caps jsonb;
begin
 if new.parent_id is not distinct from old.parent_id and new.status=old.status and new.is_published=old.is_published then return new;end if;
 for affected in
  with recursive descendants as (
   select new.id as id union all select c.id from business_categories c join descendants d on c.parent_id=d.id
  ), items as (
   select business_id,'products'::text as resource,folder_category_id from products where is_published
   union all select business_id,'services'::text,folder_category_id from services where is_published
  ) select distinct i.business_id,i.resource from items i join descendants d on d.id=i.folder_category_id
   where global_category_available(i.folder_category_id)
    and not previous_global_category_available(i.folder_category_id,old.id,old.parent_id,old.status,old.is_published)
   order by i.business_id,i.resource
 loop
  perform 1 from businesses where id=affected.business_id for update;
  select r.capabilities into caps from businesses b join business_package_rules r using(plan_id) where b.id=affected.business_id;
  if (caps->>affected.resource)::integer=0 then
   raise exception '% requires Standard or Premium',initcap(affected.resource);
  end if;
 end loop;
 return new;
end $$;
drop trigger if exists guard_global_category_publication on public.business_categories;
create trigger guard_global_category_publication after update on public.business_categories for each row execute function public.guard_global_category_publication();

-- This trigger also covers direct owner writes through Supabase, not just API calls.
-- Shared locks on every ancestor prevent disabling/deletion racing a new assignment.
create or replace function public.validate_global_category_reference() returns trigger
language plpgsql security definer set search_path=public as $$
declare selected uuid; previous uuid; current_id uuid; node record;
begin
 selected := (to_jsonb(new)->>tg_argv[0])::uuid;
 if tg_op='UPDATE' then previous := (to_jsonb(old)->>tg_argv[0])::uuid; end if;
 if selected is null or selected is not distinct from previous then return new; end if;
 current_id := selected;
 while current_id is not null loop
  select id,parent_id,is_published,status into node from business_categories where id=current_id for share;
  if not found or not node.is_published or node.status<>'enabled' then
   raise exception 'Category is unavailable for new selections' using errcode='23514';
  end if;
  current_id := node.parent_id;
 end loop;
 return new;
end $$;
do $$ declare t text; col text; begin
 foreach t in array array['products','services','businesses','gallery_photos'] loop
  col := case when t in ('products','services') then 'folder_category_id' else 'global_category_id' end;
  execute format('drop trigger if exists validate_global_category_reference on public.%I',t);
  execute format('create trigger validate_global_category_reference before insert or update on public.%I for each row execute function public.validate_global_category_reference(%L)',t,col);
  if t in ('products','services') then
   execute format('drop trigger if exists validate_global_taxonomy_reference on public.%I',t);
   execute format('create trigger validate_global_taxonomy_reference before insert or update on public.%I for each row execute function public.validate_global_category_reference(''category_id'')',t);
  end if;
 end loop;
end $$;

-- Category writes are backend-only: ADMIN_EMAILS is checked in the existing auth guard.
-- No authenticated JWT can mutate categories directly, including the old owner path.
drop policy if exists "Category owner access" on public.business_categories;
drop policy if exists "Published categories" on public.business_categories;
drop policy if exists "Authenticated category reads" on public.business_categories;
create policy "Authenticated category reads" on public.business_categories for select to authenticated using(true);
drop policy if exists "Category mutation boundary" on public.business_categories;
create policy "Category mutation boundary" on public.business_categories as restrictive for all to anon,authenticated using(auth.uid() is not null) with check(false);
revoke insert,update,delete on public.business_categories from anon,authenticated;
revoke select on public.business_categories from anon;
grant select on public.business_categories to authenticated;
grant all on public.business_categories to service_role;

-- Public items keep their existing publication boundary, without exposing a category list.
drop policy if exists "Product publication boundary" on public.products;
create policy "Product publication boundary" on public.products as restrictive for select using (
 exists(select 1 from public.businesses b where b.id=business_id and b.owner_id=auth.uid())
 or (is_published and (folder_category_id is null or public.global_category_available(folder_category_id)))
);
drop policy if exists "Service publication boundary" on public.services;
create policy "Service publication boundary" on public.services as restrictive for select using (
 exists(select 1 from public.businesses b where b.id=business_id and b.owner_id=auth.uid())
 or (is_published and (folder_category_id is null or public.global_category_available(folder_category_id)))
);

-- Old folder reorder must no longer offer an alternate mutation entry point.
drop function if exists public.reorder_categories(uuid,text,uuid[]);
create or replace function public.move_category_items(p_business uuid,p_type text,p_ids uuid[],p_category uuid)
returns void language plpgsql security invoker set search_path=public as $$
declare matched integer;
begin
 if p_type not in ('product','service') or cardinality(p_ids)<1 or cardinality(p_ids)<>(select count(distinct x) from unnest(p_ids) x) then raise exception 'Invalid move'; end if;
 if p_type='product' then
  perform id from products where business_id=p_business and id=any(p_ids) for update;
  select count(*) into matched from products where business_id=p_business and id=any(p_ids);
 else
  perform id from services where business_id=p_business and id=any(p_ids) for update;
  select count(*) into matched from services where business_id=p_business and id=any(p_ids);
 end if;
 if matched<>cardinality(p_ids) then raise exception 'Invalid items'; end if;
 if p_type='product' then update products set folder_category_id=p_category,category_id=p_category,updated_at=now() where business_id=p_business and id=any(p_ids);
 else update services set folder_category_id=p_category,category_id=p_category,updated_at=now() where business_id=p_business and id=any(p_ids); end if;
end $$;
revoke all on function public.move_category_items(uuid,text,uuid[],uuid) from public,anon,authenticated;
grant execute on function public.move_category_items(uuid,text,uuid[],uuid) to service_role;

-- Atomic category writes serialize hierarchy changes and compare versions.
create or replace function public.write_global_category(p_id uuid,p_version bigint,p_fields jsonb,p_delete boolean default false)
returns jsonb language plpgsql security invoker set search_path=public as $$
declare node business_categories; begin
 perform pg_advisory_xact_lock(184712009);
 if p_id is not null then
  select * into node from business_categories where id=p_id for update;
  if not found then raise exception 'Category not found' using errcode='P0002'; end if;
  if p_version is distinct from node.version then raise exception 'Category changed; reload before saving' using errcode='40001'; end if;
 end if;
 if p_delete then
  delete from business_categories where id=p_id;
  return jsonb_build_object('id',p_id);
 end if;
 if p_id is null then
  insert into business_categories(name,name_mr,parent_id,image_url,icon,status)
   values(trim(p_fields->>'name'),coalesce(p_fields->>'name_mr',''),(p_fields->>'parent_id')::uuid,
    coalesce(p_fields->>'image_url',''),coalesce(p_fields->>'icon','Tag'),coalesce(p_fields->>'status','enabled')) returning * into node;
 else
  update business_categories set
   name=case when p_fields?'name' then trim(p_fields->>'name') else name end,
   name_mr=case when p_fields?'name_mr' then p_fields->>'name_mr' else name_mr end,
   parent_id=case when p_fields?'parent_id' then (p_fields->>'parent_id')::uuid else parent_id end,
   image_url=case when p_fields?'image_url' then p_fields->>'image_url' else image_url end,
   icon=case when p_fields?'icon' then p_fields->>'icon' else icon end,
   status=case when p_fields?'status' then p_fields->>'status' else status end
  where id=p_id returning * into node;
 end if;
 return to_jsonb(node);
end $$;
revoke all on function public.write_global_category(uuid,bigint,jsonb,boolean) from public,anon,authenticated;
grant execute on function public.write_global_category(uuid,bigint,jsonb,boolean) to service_role;

-- Legacy JSON shape: object keys are categories, nested values/arrays are descendants.
-- Preview and commit use the same transaction and case-insensitive sibling matching.
create or replace function public.import_global_categories(p_paths jsonb,p_preview boolean default true)
returns jsonb language plpgsql security invoker set search_path=public as $$
declare path jsonb; label text; parent uuid; found_id uuid; created integer:=0; reused integer:=0;
 results jsonb:='[]'::jsonb; known jsonb:='{}'::jsonb; key text; depth integer;
begin
 perform pg_advisory_xact_lock(184712009);
 if jsonb_typeof(p_paths)<>'array' or jsonb_array_length(p_paths)>1000 then raise exception 'Invalid import' using errcode='23514'; end if;
 for path in select value from jsonb_array_elements(p_paths) order by jsonb_array_length(value) loop
  parent:=null; key:=''; depth:=0;
  for label in select value from jsonb_array_elements_text(path) loop
   label:=trim(label);
   if length(label) not between 1 and 100 or depth>=32 then raise exception 'Invalid category path' using errcode='23514'; end if;
   key:=key||'/'||encode(convert_to(lower(label),'UTF8'),'hex');
   if known ? key then parent:=(known->>key)::uuid; depth:=depth+1; continue; end if;
   select id into found_id from business_categories where parent_id is not distinct from parent and lower(trim(name))=lower(label) order by created_at,id limit 1;
   if found_id is null then
    created:=created+1;
    if p_preview then found_id:=gen_random_uuid();
    else insert into business_categories(name,parent_id) values(label,parent) returning id into found_id; end if;
   else reused:=reused+1; end if;
   results:=results||jsonb_build_array(jsonb_build_object('name',label,'depth',depth,'exists',exists(select 1 from business_categories where id=found_id),'path',path));
   known:=known||jsonb_build_object(key,found_id); parent:=found_id; depth:=depth+1;
  end loop;
 end loop;
 return jsonb_build_object('created',created,'reused',reused,'failed',0,'nodes',results);
end $$;
revoke all on function public.import_global_categories(jsonb,boolean) from public,anon,authenticated;
grant execute on function public.import_global_categories(jsonb,boolean) to service_role;

create or replace view public.explore_products as
select p.id, p.business_id, coalesce(nullif(p.name_en,''),p.name) as name,
 p.name_mr, coalesce(p.description_en,p.description,'') as description,
 p.description_mr, p.price, p.image_url as image, p.is_available as available,
 p.created_at, p.sort_order, p.images, p.specifications,
 coalesce((select name from public.business_categories where id=b.global_category_id),nullif(b.details->'category'->>'en',''),nullif(b.category,''),'Other') as category,
 coalesce(nullif(c.name,''),nullif(p.category_en,''),nullif(p.category,''),'Other') as subcategory,
 coalesce(nullif(c.image_url,''),p.image_url,'') as category_image,
 jsonb_build_object('id',b.id,'slug',b.slug,'name',b.business_name,
 'logo',coalesce(b.details->>'logo',b.logo_url,''),
 'phone',coalesce(b.details->>'phone',b.phone,''),
 'whatsapp',coalesce(b.details->>'whatsapp',b.whatsapp_number,''),
 'address',coalesce(b.details->'address',to_jsonb(b.address)),
 'verified',b.is_verified) as seller
from public.products p join public.businesses b on b.id=p.business_id
left join public.business_categories c on c.id=p.folder_category_id
where b.is_published=true and p.is_published=true
and (p.folder_category_id is null or public.global_category_available(c.id))
and not exists (select 1 from public.business_section_visibility v where v.business_id=b.id and v.products=false);

create or replace view public.explore_services as
select p.id, p.business_id, coalesce(nullif(p.name_en,''),p.name) as name,
 p.name_mr, coalesce(p.details_en,p.details,'') as description,
 p.details_mr as description_mr, case when p.starting_price > 0 then p.starting_price else null end as price, p.cover_image as image, null::boolean as available,
 p.created_at, 0 as sort_order, '[]'::jsonb as images, jsonb_strip_nulls(jsonb_build_object('Duration',nullif(p.duration_en,''))) as specifications, 'service'::text as kind,
 coalesce((select name from public.business_categories where id=b.global_category_id),nullif(b.details->'category'->>'en',''),nullif(b.category,''),'Other') as category,
 coalesce(nullif(c.name,''),nullif(p.category_en,''),'Other') as subcategory,
 coalesce(nullif(c.image_url,''),p.cover_image,'') as category_image,
 jsonb_build_object('id',b.id,'slug',b.slug,'name',b.business_name,
 'logo',coalesce(b.details->>'logo',b.logo_url,''),
 'phone',coalesce(b.details->>'phone',b.phone,''),
 'whatsapp',coalesce(b.details->>'whatsapp',b.whatsapp_number,''),
 'address',coalesce(b.details->'address',to_jsonb(b.address)),
 'verified',b.is_verified) as seller
from public.services p join public.businesses b on b.id=p.business_id
left join public.business_categories c on c.id=p.folder_category_id
where b.is_published=true and p.is_published=true
and (p.folder_category_id is null or public.global_category_available(c.id))
and not exists (select 1 from public.business_section_visibility v where v.business_id=b.id and v.services=false);

-- Freeze retired taxonomy writes even for older service-role deployments.
create or replace function public.reject_retired_category_write() returns trigger
language plpgsql as $$ begin raise exception 'Use the global Category Architecture Desk' using errcode='23514'; end $$;
do $$ begin
 if to_regclass('public.listing_categories') is not null then
  drop trigger if exists retired_category_read_only on public.listing_categories;
  create trigger retired_category_read_only before insert or update or delete on public.listing_categories for each row execute function public.reject_retired_category_write();
 end if;
end $$;
commit;



-- Migration 019_business_catalog_mapping.sql
-- Extend the canonical taxonomy; never infer business types from legacy rows.
begin;
lock table public.business_categories in access exclusive mode;
alter table public.business_categories add column if not exists catalog_kind text not null default 'legacy'
 check(catalog_kind in ('legacy','business','product','service'));
create index if not exists categories_kind_parent on public.business_categories(catalog_kind,parent_id);
create table if not exists public.business_catalog_mappings (
 business_category_id uuid not null references public.business_categories(id) on delete restrict,
 catalog_category_id uuid not null references public.business_categories(id) on delete restrict,
 created_at timestamptz not null default now(),
 primary key(business_category_id,catalog_category_id)
);
create index if not exists catalog_mapping_reverse on public.business_catalog_mappings(catalog_category_id);
alter table public.business_catalog_mappings enable row level security;
revoke all on public.business_catalog_mappings from public,anon,authenticated;
grant all on public.business_catalog_mappings to service_role;

create or replace function public.guard_catalog_kind() returns trigger
language plpgsql set search_path=public as $$
begin
 -- guard_global_category already serializes category writes using this same lock.
 perform pg_advisory_xact_lock(184712009);
 if new.catalog_kind='business' and new.parent_id is not null then
  raise exception 'Business categories must be roots' using errcode='23514'; end if;
 if new.parent_id is not null and new.catalog_kind<>'legacy' and not exists(
  select 1 from business_categories where id=new.parent_id and catalog_kind=new.catalog_kind
 ) then raise exception 'Parent and child must have the same category type' using errcode='23514';end if;
 if tg_op='UPDATE' and new.catalog_kind is distinct from old.catalog_kind then
  if exists(select 1 from business_categories where parent_id=new.id and catalog_kind not in ('legacy',new.catalog_kind))
   or exists(select 1 from business_catalog_mappings where business_category_id=new.id or catalog_category_id=new.id)
   or exists(select 1 from businesses where global_category_id=new.id)
   or exists(select 1 from products where folder_category_id=new.id or category_id=new.id)
   or exists(select 1 from services where folder_category_id=new.id or category_id=new.id)
  then raise exception 'Referenced category type cannot change; create a category or migrate references first' using errcode='23514';end if;
 end if;
 return new;
end $$;
drop trigger if exists guard_catalog_kind on public.business_categories;
create trigger guard_catalog_kind before insert or update on public.business_categories for each row execute function public.guard_catalog_kind();

-- Effective permission: active business type, active same-type ancestors, a mapped
-- ancestor (or self), and a structural leaf. p_roots supports preview without writes.
create or replace function public.catalog_category_allowed(p_business_category uuid,p_type text,p_category uuid,p_roots uuid[] default null)
returns boolean language sql stable security definer set search_path=public as $$
 with recursive ancestors as (
  select id,parent_id,catalog_kind,status,is_published from business_categories where id=p_category
  union all select c.id,c.parent_id,c.catalog_kind,c.status,c.is_published from business_categories c join ancestors a on c.id=a.parent_id
 ) select coalesce(
  p_type in ('product','service')
  and exists(select 1 from business_categories where id=p_business_category and catalog_kind='business' and status='enabled' and is_published)
  and exists(select 1 from ancestors)
  and (select bool_and(catalog_kind=p_type and status='enabled' and is_published) from ancestors)
  and not exists(select 1 from business_categories where parent_id=p_category)
  and exists(select 1 from ancestors a where case when p_roots is null then
   exists(select 1 from business_catalog_mappings m where m.business_category_id=p_business_category and m.catalog_category_id=a.id)
   else a.id=any(p_roots) end), false);
$$;
revoke all on function public.catalog_category_allowed(uuid,text,uuid,uuid[]) from public,anon,authenticated;
grant execute on function public.catalog_category_allowed(uuid,text,uuid,uuid[]) to service_role;

create or replace function public.validate_business_catalog_reference() returns trigger
language plpgsql security definer set search_path=public as $$
declare business_category uuid; selected uuid; previous uuid;
begin
 perform pg_advisory_xact_lock_shared(184712009);
 if tg_table_name='businesses' then
  selected:=new.global_category_id;
  if tg_op='UPDATE' and selected is not distinct from old.global_category_id then return new;end if;
  if not exists(select 1 from business_categories where id=selected and catalog_kind='business' and status='enabled' and is_published) then
   raise exception 'Select an active business category' using errcode='23514';end if;
 else
  select global_category_id into business_category from businesses where id=new.business_id for share;
  if not catalog_category_allowed(business_category,case when tg_table_name='products' then 'product' else 'service' end,new.folder_category_id)
   or new.category_id is distinct from new.folder_category_id then
   raise exception 'Select an active allowed leaf category for this business and listing type' using errcode='23514';end if;
 end if;
 return new;
end $$;
do $$ declare t text;begin
 foreach t in array array['businesses','products','services'] loop
  execute format('drop trigger if exists validate_business_catalog_reference on public.%I',t);
  execute format('create trigger validate_business_catalog_reference before insert or update on public.%I for each row execute function public.validate_business_catalog_reference()',t);
 end loop;
end $$;

-- Conservative impact preview for editing a category or turning a leaf into a group.
create or replace function public.catalog_category_impact(p_id uuid)
returns jsonb language sql stable security invoker set search_path=public as $$
 with recursive subtree as (
  select id from business_categories where id=p_id
  union all select c.id from business_categories c join subtree s on c.parent_id=s.id
 ), items as (
  select business_id,folder_category_id from products union all select business_id,folder_category_id from services
 ), affected as (
  select i.* from items i join businesses b on b.id=i.business_id
   where i.folder_category_id in (select id from subtree) or b.global_category_id in (select id from subtree)
 ) select jsonb_build_object('affectedListings',count(*),'affectedBusinesses',
  (select count(*) from businesses where global_category_id in (select id from subtree) or id in (select business_id from affected))) from affected;
$$;
revoke all on function public.catalog_category_impact(uuid) from public,anon,authenticated;
grant execute on function public.catalog_category_impact(uuid) to service_role;

-- Count affected existing records before mapping/business-assignment changes.
create or replace function public.catalog_assignment_impact(p_business_category uuid,p_business uuid default null,p_type text default null,p_categories uuid[] default null)
returns jsonb language sql stable security invoker set search_path=public as $$
 with items as (
  select business_id,'product'::text as kind,folder_category_id from products
  union all select business_id,'service'::text,folder_category_id from services
 ), affected as (
  select i.* from items i join businesses b on b.id=i.business_id
  where (case when p_business is null then b.global_category_id=p_business_category else b.id=p_business end)
   and (p_type is null or i.kind=p_type)
   and not catalog_category_allowed(p_business_category,i.kind,i.folder_category_id,p_categories)
 ) select jsonb_build_object('affectedListings',count(*),'affectedBusinesses',count(distinct business_id)) from affected;
$$;
revoke all on function public.catalog_assignment_impact(uuid,uuid,text,uuid[]) from public,anon,authenticated;
grant execute on function public.catalog_assignment_impact(uuid,uuid,text,uuid[]) to service_role;

create or replace function public.replace_business_catalog_mappings(p_business_category uuid,p_type text,p_categories uuid[],p_version bigint)
returns jsonb language plpgsql security invoker set search_path=public as $$
declare node business_categories;next_version bigint;
begin
 perform pg_advisory_xact_lock(184712009);
 select * into node from business_categories where id=p_business_category for update;
 if not found then raise exception 'Category not found' using errcode='P0002';end if;
 if node.catalog_kind<>'business' or p_type not in ('product','service') or p_categories is null or cardinality(p_categories)>1000
  or cardinality(p_categories)<>(select count(distinct id) from unnest(p_categories) id)
  or exists(select 1 from unnest(p_categories) roots(category_id) where not exists(select 1 from business_categories c where c.id=roots.category_id and c.catalog_kind=p_type))
 then raise exception 'Invalid business category mappings' using errcode='23514';end if;
 if node.version is distinct from p_version then raise exception 'Category changed; reload before saving' using errcode='40001';end if;
 delete from business_catalog_mappings m using business_categories c
  where m.business_category_id=p_business_category and m.catalog_category_id=c.id and c.catalog_kind=p_type;
 insert into business_catalog_mappings(business_category_id,catalog_category_id)
  select p_business_category,id from unnest(p_categories) id;
 update business_categories set updated_at=now() where id=p_business_category returning version into next_version;
 return jsonb_build_object('version',next_version);
end $$;
revoke all on function public.replace_business_catalog_mappings(uuid,text,uuid[],bigint) from public,anon,authenticated;
grant execute on function public.replace_business_catalog_mappings(uuid,text,uuid[],bigint) to service_role;

create or replace function public.write_global_category(p_id uuid,p_version bigint,p_fields jsonb,p_delete boolean default false)
returns jsonb language plpgsql security invoker set search_path=public as $$
declare node business_categories; begin
 perform pg_advisory_xact_lock(184712009);
 if p_id is not null then
  select * into node from business_categories where id=p_id for update;
  if not found then raise exception 'Category not found' using errcode='P0002'; end if;
  if p_version is distinct from node.version then raise exception 'Category changed; reload before saving' using errcode='40001'; end if;
 end if;
 if p_delete then
  delete from business_categories where id=p_id;
  return jsonb_build_object('id',p_id);
 end if;
 if p_id is null then
  insert into business_categories(name,name_mr,parent_id,image_url,icon,status,catalog_kind)
   values(trim(p_fields->>'name'),coalesce(p_fields->>'name_mr',''),(p_fields->>'parent_id')::uuid,
    coalesce(p_fields->>'image_url',''),coalesce(p_fields->>'icon','Tag'),coalesce(p_fields->>'status','enabled'),coalesce(p_fields->>'catalog_kind','legacy')) returning * into node;
 else
  update business_categories set
   catalog_kind=case when p_fields?'catalog_kind' then p_fields->>'catalog_kind' else catalog_kind end,
   name=case when p_fields?'name' then trim(p_fields->>'name') else name end,
   name_mr=case when p_fields?'name_mr' then p_fields->>'name_mr' else name_mr end,
   parent_id=case when p_fields?'parent_id' then (p_fields->>'parent_id')::uuid else parent_id end,
   image_url=case when p_fields?'image_url' then p_fields->>'image_url' else image_url end,
   icon=case when p_fields?'icon' then p_fields->>'icon' else icon end,
   status=case when p_fields?'status' then p_fields->>'status' else status end
  where id=p_id returning * into node;
 end if;
 if p_fields?'map_business_category_id' then
  if p_id is not null or node.catalog_kind not in ('product','service') or not exists(
   select 1 from business_categories where id=(p_fields->>'map_business_category_id')::uuid and catalog_kind='business'
  ) then raise exception 'Invalid contextual category mapping' using errcode='23514';end if;
  insert into business_catalog_mappings(business_category_id,catalog_category_id)
   values((p_fields->>'map_business_category_id')::uuid,node.id);
  update business_categories set updated_at=now() where id=(p_fields->>'map_business_category_id')::uuid;
 end if;
 return to_jsonb(node);
end $$;
revoke all on function public.write_global_category(uuid,bigint,jsonb,boolean) from public,anon,authenticated;
grant execute on function public.write_global_category(uuid,bigint,jsonb,boolean) to service_role;

create or replace function public.import_catalog_categories(p_paths jsonb,p_preview boolean,p_kind text)
returns jsonb language plpgsql security invoker set search_path=public as $$
declare path jsonb; label text; parent uuid; found_id uuid; created integer:=0; reused integer:=0;
 results jsonb:='[]'::jsonb; known jsonb:='{}'::jsonb; key text; depth integer;
begin
 perform pg_advisory_xact_lock(184712009);
 if p_kind not in ('legacy','product','service') then raise exception 'Import product or service trees separately' using errcode='23514';end if;
 if jsonb_typeof(p_paths)<>'array' or jsonb_array_length(p_paths)>1000 then raise exception 'Invalid import' using errcode='23514'; end if;
 for path in select value from jsonb_array_elements(p_paths) order by jsonb_array_length(value) loop
  parent:=null; key:=''; depth:=0;
  for label in select value from jsonb_array_elements_text(path) loop
   label:=trim(label);
   if length(label) not between 1 and 100 or depth>=32 then raise exception 'Invalid category path' using errcode='23514'; end if;
   key:=key||'/'||encode(convert_to(lower(label),'UTF8'),'hex');
   if known ? key then parent:=(known->>key)::uuid; depth:=depth+1; continue; end if;
   select id into found_id from business_categories where catalog_kind=p_kind and parent_id is not distinct from parent and lower(trim(name))=lower(label) order by created_at,id limit 1;
   if found_id is null then
    created:=created+1;
    if p_preview then found_id:=gen_random_uuid();
    else insert into business_categories(name,parent_id,catalog_kind) values(label,parent,p_kind) returning id into found_id; end if;
   else reused:=reused+1; end if;
   results:=results||jsonb_build_array(jsonb_build_object('name',label,'depth',depth,'exists',exists(select 1 from business_categories where id=found_id),'path',path));
   known:=known||jsonb_build_object(key,found_id); parent:=found_id; depth:=depth+1;
  end loop;
 end loop;
 return jsonb_build_object('created',created,'reused',reused,'failed',0,'nodes',results);
end $$;
revoke all on function public.import_catalog_categories(jsonb,boolean,text) from public,anon,authenticated;
grant execute on function public.import_catalog_categories(jsonb,boolean,text) to service_role;


commit;



-- Migration 020_marketplace_category_hierarchy.sql
-- Preserve the full category ancestry in public catalog projections.
-- Apply after 019. Existing listing assignments/publication rules are unchanged.
begin;
create or replace function public.explore_category_path(p_id uuid) returns jsonb
language sql stable security invoker set search_path=public as $$
 with recursive ancestors as (
  select id,parent_id,name,name_mr,image_url,0 as depth,array[id] as seen
   from business_categories where id=p_id
  union all
  select c.id,c.parent_id,c.name,c.name_mr,c.image_url,a.depth+1,a.seen||c.id
   from business_categories c join ancestors a on c.id=a.parent_id where not c.id=any(a.seen)
 ) select coalesce(jsonb_agg(jsonb_build_object('id',id,'name',name,'name_mr',name_mr,'image_url',image_url) order by depth desc),'[]'::jsonb) from ancestors;
$$;
revoke all on function public.explore_category_path(uuid) from public,anon,authenticated;
grant execute on function public.explore_category_path(uuid) to service_role;

create or replace view public.explore_products as
select p.id, p.business_id, coalesce(nullif(p.name_en,''),p.name) as name,
 p.name_mr, coalesce(p.description_en,p.description,'') as description,
 p.description_mr, p.price, p.image_url as image, p.is_available as available,
 p.created_at, p.sort_order, p.images, p.specifications,
 coalesce((select name from public.business_categories where id=b.global_category_id),nullif(b.details->'category'->>'en',''),nullif(b.category,''),'Other') as category,
 coalesce(nullif(c.name,''),nullif(p.category_en,''),nullif(p.category,''),'Other') as subcategory,
 coalesce(nullif(c.image_url,''),p.image_url,'') as category_image,
 jsonb_build_object('id',b.id,'slug',b.slug,'name',b.business_name,
 'logo',coalesce(b.details->>'logo',b.logo_url,''),
 'phone',coalesce(b.details->>'phone',b.phone,''),
 'whatsapp',coalesce(b.details->>'whatsapp',b.whatsapp_number,''),
 'address',coalesce(b.details->'address',to_jsonb(b.address)),
 'verified',b.is_verified) as seller,
 p.folder_category_id as catalog_category_id,
 public.explore_category_path(p.folder_category_id) as category_path
from public.products p join public.businesses b on b.id=p.business_id
left join public.business_categories c on c.id=p.folder_category_id
where b.is_published=true and p.is_published=true
and (p.folder_category_id is null or public.global_category_available(c.id))
and not exists (select 1 from public.business_section_visibility v where v.business_id=b.id and v.products=false);

create or replace view public.explore_services as
select p.id, p.business_id, coalesce(nullif(p.name_en,''),p.name) as name,
 p.name_mr, coalesce(p.details_en,p.details,'') as description,
 p.details_mr as description_mr, case when p.starting_price > 0 then p.starting_price else null end as price, p.cover_image as image, null::boolean as available,
 p.created_at, 0 as sort_order, '[]'::jsonb as images, jsonb_strip_nulls(jsonb_build_object('Duration',nullif(p.duration_en,''))) as specifications, 'service'::text as kind,
 coalesce((select name from public.business_categories where id=b.global_category_id),nullif(b.details->'category'->>'en',''),nullif(b.category,''),'Other') as category,
 coalesce(nullif(c.name,''),nullif(p.category_en,''),'Other') as subcategory,
 coalesce(nullif(c.image_url,''),p.cover_image,'') as category_image,
 jsonb_build_object('id',b.id,'slug',b.slug,'name',b.business_name,
 'logo',coalesce(b.details->>'logo',b.logo_url,''),
 'phone',coalesce(b.details->>'phone',b.phone,''),
 'whatsapp',coalesce(b.details->>'whatsapp',b.whatsapp_number,''),
 'address',coalesce(b.details->'address',to_jsonb(b.address)),
 'verified',b.is_verified) as seller,
 p.folder_category_id as catalog_category_id,
 public.explore_category_path(p.folder_category_id) as category_path
from public.services p join public.businesses b on b.id=p.business_id
left join public.business_categories c on c.id=p.folder_category_id
where b.is_published=true and p.is_published=true
and (p.folder_category_id is null or public.global_category_available(c.id))
and not exists (select 1 from public.business_section_visibility v where v.business_id=b.id and v.services=false);


revoke all on public.explore_products from anon,authenticated;
grant select on public.explore_products to service_role;
create or replace function public.explore_facets() returns jsonb
language sql stable security invoker set search_path=public as $$
 select coalesce(jsonb_agg(to_jsonb(f)),'[]'::jsonb) from (
 select category,subcategory,catalog_category_id,category_path,min(nullif(category_image,'')) as image,
 count(*) as count,
 jsonb_agg(distinct specifications->>'Metal') filter (where specifications->>'Metal' is not null) as metals,
 jsonb_agg(distinct specifications->>'Purity') filter (where specifications->>'Purity' is not null) as purities,
 jsonb_agg(distinct jsonb_build_object('id',business_id,'name',seller->>'name')) as sellers
 from public.explore_products group by category,subcategory,catalog_category_id,category_path order by category,subcategory,catalog_category_id
 ) f;
$$;
revoke all on function public.explore_facets() from public,anon,authenticated;
grant execute on function public.explore_facets() to service_role;

revoke all on public.explore_services from anon,authenticated;
grant select on public.explore_services to service_role;
create or replace function public.explore_service_facets() returns jsonb
language sql stable security invoker set search_path=public as $$
 select coalesce(jsonb_agg(to_jsonb(f)),'[]'::jsonb) from (
 select category,subcategory,catalog_category_id,category_path,min(nullif(category_image,'')) as image,
 count(*) as count,
 
 jsonb_agg(distinct jsonb_build_object('id',business_id,'name',seller->>'name')) as sellers
 from public.explore_services group by category,subcategory,catalog_category_id,category_path order by category,subcategory,catalog_category_id
 ) f;
$$;
revoke all on function public.explore_service_facets() from public,anon,authenticated;
grant execute on function public.explore_service_facets() to service_role;

commit;



-- Migration 021_delete_unused_category_branches.sql
-- Delete unused branches and their catalog mappings atomically.
-- Business, listing, and gallery references still prevent deletion.
begin;
create or replace function public.write_global_category(p_id uuid,p_version bigint,p_fields jsonb,p_delete boolean default false)
returns jsonb language plpgsql security invoker set search_path=public as $$
declare node business_categories; branch uuid[]; removed record; begin
 perform pg_advisory_xact_lock(184712009);
 if p_id is not null then
  select * into node from business_categories where id=p_id for update;
  if not found then raise exception 'Category not found' using errcode='P0002'; end if;
  if p_version is distinct from node.version then raise exception 'Category changed; reload before saving' using errcode='40001'; end if;
 end if;
 if p_delete then
  -- Mappings are configuration; real records remain protected by restrictive FKs.
  with recursive descendants as (
   select id from business_categories where id=p_id
   union all select c.id from business_categories c join descendants d on c.parent_id=d.id
  ) select array_agg(id) into branch from descendants;
  update business_categories set updated_at=now()
   where not (id=any(branch)) and id in (
    select business_category_id from business_catalog_mappings where catalog_category_id=any(branch)
   );
  delete from business_catalog_mappings
   where business_category_id=any(branch) or catalog_category_id=any(branch);
  -- Delete leaves first to satisfy immediate parent constraints.
  for removed in
   with recursive descendants as (
    select id,0 as depth from business_categories where id=p_id
    union all select c.id,d.depth+1 from business_categories c join descendants d on c.parent_id=d.id
   ) select id from descendants order by depth desc,id
  loop
   delete from business_categories where id=removed.id;
  end loop;
  return jsonb_build_object('id',p_id);
 end if;
 if p_id is null then
  insert into business_categories(name,name_mr,parent_id,image_url,icon,status,catalog_kind)
   values(trim(p_fields->>'name'),coalesce(p_fields->>'name_mr',''),(p_fields->>'parent_id')::uuid,
    coalesce(p_fields->>'image_url',''),coalesce(p_fields->>'icon','Tag'),coalesce(p_fields->>'status','enabled'),coalesce(p_fields->>'catalog_kind','legacy')) returning * into node;
 else
  update business_categories set
   catalog_kind=case when p_fields?'catalog_kind' then p_fields->>'catalog_kind' else catalog_kind end,
   name=case when p_fields?'name' then trim(p_fields->>'name') else name end,
   name_mr=case when p_fields?'name_mr' then p_fields->>'name_mr' else name_mr end,
   parent_id=case when p_fields?'parent_id' then (p_fields->>'parent_id')::uuid else parent_id end,
   image_url=case when p_fields?'image_url' then p_fields->>'image_url' else image_url end,
   icon=case when p_fields?'icon' then p_fields->>'icon' else icon end,
   status=case when p_fields?'status' then p_fields->>'status' else status end
  where id=p_id returning * into node;
 end if;
 if p_fields?'map_business_category_id' then
  if p_id is not null or node.catalog_kind not in ('product','service') or not exists(
   select 1 from business_categories where id=(p_fields->>'map_business_category_id')::uuid and catalog_kind='business'
  ) then raise exception 'Invalid contextual category mapping' using errcode='23514';end if;
  insert into business_catalog_mappings(business_category_id,catalog_category_id)
   values((p_fields->>'map_business_category_id')::uuid,node.id);
  update business_categories set updated_at=now() where id=(p_fields->>'map_business_category_id')::uuid;
 end if;
 return to_jsonb(node);
end $$;
revoke all on function public.write_global_category(uuid,bigint,jsonb,boolean) from public,anon,authenticated;
grant execute on function public.write_global_category(uuid,bigint,jsonb,boolean) to service_role;

commit;

