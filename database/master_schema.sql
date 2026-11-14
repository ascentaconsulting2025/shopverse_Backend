-- Shopverse consolidated Supabase master schema
-- Source of truth: schema.sql followed by forward migrations 001-047.
-- Intended for a fresh Supabase project SQL Editor. Do not run against production.


-- ============================================================================
-- Source: schema.sql
-- ============================================================================
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

-- ============================================================================
-- Source: migrations/001_create_services.sql
-- ============================================================================
-- Services are first-class business records. Existing services in businesses.details remain untouched.
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

-- ============================================================================
-- Source: migrations/002_create_events_offers_gallery.sql
-- ============================================================================
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

-- ============================================================================
-- Source: migrations/003_unique_business_slugs.sql
-- ============================================================================
-- Keep public digital-card URLs unique for all existing installations.
create unique index if not exists idx_businesses_slug on public.businesses(slug);

-- ============================================================================
-- Source: migrations/004_create_business_visibility.sql
-- ============================================================================
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

-- ============================================================================
-- Source: migrations/005_add_business_marathi_fields.sql
-- ============================================================================
-- Add nullable Marathi values without changing existing English data.
alter table public.businesses add column if not exists business_name_mr text;
alter table public.businesses add column if not exists category_mr text;
alter table public.businesses add column if not exists owner_name_mr text;
alter table public.businesses add column if not exists designation_mr text;
alter table public.businesses add column if not exists tagline_mr text;
alter table public.businesses add column if not exists description_mr text;

-- ============================================================================
-- Source: migrations/006_add_logo_public_id.sql
-- ============================================================================
alter table public.businesses add column if not exists logo_public_id text;

-- ============================================================================
-- Source: migrations/007_add_image_public_ids.sql
-- ============================================================================
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

-- ============================================================================
-- Source: migrations/008_add_dynamic_social_links.sql
-- ============================================================================
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

-- ============================================================================
-- Source: migrations/009_optional_prices_and_business_people.sql
-- ============================================================================
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

-- ============================================================================
-- Source: migrations/010_category_folders.sql
-- ============================================================================
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

-- ============================================================================
-- Source: migrations/011_bilingual_category_names.sql
-- ============================================================================
-- Run after 010_category_folders.sql. Existing category names remain unchanged.
begin;
alter table public.business_categories
 add column if not exists name_mr text not null default '';
commit;

-- ============================================================================
-- Source: migrations/012_explore_catalog.sql
-- ============================================================================
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

-- ============================================================================
-- Source: migrations/013_explore_services.sql
-- ============================================================================
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

-- ============================================================================
-- Source: migrations/014_business_packages.sql
-- ============================================================================
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

-- ============================================================================
-- Source: migrations/015_auth_sessions.sql
-- ============================================================================
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

-- ============================================================================
-- Source: migrations/016_cloudinary_lifecycle.sql
-- ============================================================================
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

-- ============================================================================
-- Source: migrations/017_user_management.sql
-- ============================================================================
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

-- ============================================================================
-- Source: migrations/018_global_category_architecture.sql
-- ============================================================================
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

-- ============================================================================
-- Source: migrations/019_business_catalog_mapping.sql
-- ============================================================================
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
  -- Unrelated listing updates (for example fleet metadata backfills) must not
  -- revalidate unchanged legacy catalog assignments.
  if tg_op='UPDATE'
   and new.business_id is not distinct from old.business_id
   and new.folder_category_id is not distinct from old.folder_category_id
   and new.category_id is not distinct from old.category_id then return new;end if;
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

-- ============================================================================
-- Source: migrations/020_marketplace_category_hierarchy.sql
-- ============================================================================
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

-- ============================================================================
-- Source: migrations/021_delete_unused_category_branches.sql
-- ============================================================================
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

-- ============================================================================
-- Source: migrations/022_customer_cart.sql
-- ============================================================================
-- Account-owned cart for WhatsApp enquiries. Run before deploying the cart API.
begin;
create table if not exists public.customer_cart_items (
  customer_id uuid not null references auth.users(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete cascade,
  quantity integer not null check (quantity between 1 and 999),
  updated_at timestamptz not null default now(),
  primary key (customer_id, product_id)
);
alter table public.customer_cart_items enable row level security;
revoke all on public.customer_cart_items from anon, authenticated;
grant all on public.customer_cart_items to service_role;
create or replace function public.cart_add_item(p_customer uuid, p_product uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  insert into customer_cart_items(customer_id,product_id,quantity) values(p_customer,p_product,1)
  on conflict(customer_id,product_id) do update set quantity=least(customer_cart_items.quantity+1,999),updated_at=now();
end $$;
revoke all on function public.cart_add_item(uuid,uuid) from public, anon, authenticated;
grant execute on function public.cart_add_item(uuid,uuid) to service_role;
commit;

-- ============================================================================
-- Source: migrations/023_store_orders.sql
-- ============================================================================
-- Order records for seller confirmation. This migration does not create checkout.
begin;
create table if not exists public.marketplace_orders (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid references auth.users(id) on delete set null,
  order_number text not null unique,
  customer_name text not null,
  customer_phone text not null,
  delivery_address text not null,
  created_at timestamptz not null default now()
);
create table if not exists public.marketplace_store_orders (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.marketplace_orders(id) on delete restrict,
  business_id uuid references public.businesses(id) on delete set null,
  business_name text not null,
  store_order_number text not null unique,
  status text not null default 'PENDING' check (status in ('PENDING','ACCEPTED','PROCESSING','READY_FOR_DISPATCH','OUT_FOR_DELIVERY','DELIVERED','REJECTED','CANCELLED')),
  subtotal numeric(12,2),
  confirmed_at timestamptz,
  created_at timestamptz not null default now(),
  unique(order_id,business_id)
);
create table if not exists public.marketplace_order_items (
  id uuid primary key default gen_random_uuid(),
  store_order_id uuid not null references public.marketplace_store_orders(id) on delete restrict,
  product_id uuid references public.products(id) on delete set null,
  product_name text not null,
  quantity integer not null check (quantity > 0),
  unit_price numeric(12,2)
);
create table if not exists public.marketplace_order_status_history (
  id uuid primary key default gen_random_uuid(),
  store_order_id uuid not null references public.marketplace_store_orders(id) on delete restrict,
  previous_status text not null,
  new_status text not null,
  changed_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);
create index if not exists marketplace_store_orders_business_created_idx on public.marketplace_store_orders(business_id,created_at desc);
create index if not exists marketplace_store_orders_confirmed_idx on public.marketplace_store_orders(confirmed_at desc) where confirmed_at is not null;
create index if not exists marketplace_order_items_store_idx on public.marketplace_order_items(store_order_id);
alter table public.marketplace_orders enable row level security;
alter table public.marketplace_store_orders enable row level security;
alter table public.marketplace_order_items enable row level security;
alter table public.marketplace_order_status_history enable row level security;
revoke all on public.marketplace_orders,public.marketplace_store_orders,public.marketplace_order_items,public.marketplace_order_status_history from public,anon,authenticated;
grant all on public.marketplace_orders,public.marketplace_store_orders,public.marketplace_order_items,public.marketplace_order_status_history to service_role;
create or replace function public.confirm_marketplace_store_order(p_order uuid,p_actor uuid)
returns boolean language plpgsql security definer set search_path=public as $$
declare target marketplace_store_orders%rowtype;
begin
 select * into target from marketplace_store_orders where id=p_order for update;
 if not found or not exists(select 1 from businesses where id=target.business_id and owner_id=p_actor) then return false; end if;
 if target.status <> 'PENDING' then return false; end if;
 update marketplace_store_orders set status='ACCEPTED',confirmed_at=now() where id=target.id;
 insert into marketplace_order_status_history(store_order_id,previous_status,new_status,changed_by) values(target.id,'PENDING','ACCEPTED',p_actor);
 return true;
end $$;
revoke all on function public.confirm_marketplace_store_order(uuid,uuid) from public,anon,authenticated;
grant execute on function public.confirm_marketplace_store_order(uuid,uuid) to service_role;
commit;

-- ============================================================================
-- Source: migrations/024_whatsapp_order_requests.sql
-- ============================================================================
begin;
alter table public.marketplace_orders add column if not exists request_key uuid;
create unique index if not exists marketplace_orders_customer_request_key on public.marketplace_orders(customer_id,request_key) where request_key is not null;

-- A saved request is not a stock reservation or payment confirmation.
create or replace function public.place_whatsapp_store_request(p_customer uuid,p_store uuid,p_key uuid,p_name text,p_phone text,p_address text,p_expected jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare prior uuid; parent_id uuid; store_id uuid; reference text; b record; line record; total numeric(12,2); item_count integer;
begin
  if p_customer is null or p_store is null or p_key is null or length(trim(p_name)) not between 1 and 120 or p_phone !~ '^91[6-9][0-9]{9}$' or length(trim(p_address)) not between 1 and 500 or jsonb_typeof(p_expected) <> 'array' or jsonb_array_length(p_expected) not between 1 and 100 then
    raise exception 'Invalid request';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(p_customer::text || ':' || p_key::text,0));
  select id into prior from marketplace_orders where customer_id=p_customer and request_key=p_key;
  if prior is not null then
    select id into store_id from marketplace_store_orders where order_id=prior and business_id=p_store;
    if store_id is null then raise exception 'Request key already used'; end if;
    return jsonb_build_object('store_order_id',store_id,'replayed',true);
  end if;
  select id,business_name,coalesce(nullif(details->>'whatsapp',''),whatsapp_number) as whatsapp into b from businesses where id=p_store and is_published=true for share;
  if not found or b.whatsapp is null then raise exception 'Store unavailable'; end if;
  perform 1 from customer_cart_items c join products p on p.id=c.product_id where c.customer_id=p_customer and p.business_id=p_store order by p.id for update of c,p;
  select count(*),sum(p.price*c.quantity) into item_count,total from customer_cart_items c join products p on p.id=c.product_id where c.customer_id=p_customer and p.business_id=p_store;
  if item_count=0 or item_count <> jsonb_array_length(p_expected) then raise exception 'Cart changed'; end if;
  for line in select c.product_id,c.quantity,p.price,p.is_available,p.is_published from customer_cart_items c join products p on p.id=c.product_id where c.customer_id=p_customer and p.business_id=p_store loop
    if line.is_available is false or line.is_published is not true or not exists(select 1 from explore_products e where e.id=line.product_id) or not exists (select 1 from jsonb_array_elements(p_expected) x where x->>'id'=line.product_id::text and (x->>'quantity')::int=line.quantity and (x->>'price')::numeric is not distinct from line.price) then raise exception 'Cart or price changed'; end if;
  end loop;
  if (select count(distinct x->>'id') from jsonb_array_elements(p_expected) x) <> item_count then raise exception 'Invalid cart'; end if;
  reference := 'ORD-' || upper(replace(gen_random_uuid()::text,'-',''));
  insert into marketplace_orders(customer_id,order_number,customer_name,customer_phone,delivery_address,request_key) values(p_customer,reference,trim(p_name),p_phone,trim(p_address),p_key) returning id into parent_id;
  insert into marketplace_store_orders(order_id,business_id,business_name,store_order_number,subtotal) values(parent_id,b.id,b.business_name,reference || '-1',case when exists(select 1 from customer_cart_items c join products p on p.id=c.product_id where c.customer_id=p_customer and p.business_id=p_store and p.price is null) then null else total end) returning id into store_id;
  insert into marketplace_order_items(store_order_id,product_id,product_name,quantity,unit_price) select store_id,p.id,coalesce(nullif(p.name_en,''),p.name),c.quantity,p.price from customer_cart_items c join products p on p.id=c.product_id where c.customer_id=p_customer and p.business_id=p_store;
  delete from customer_cart_items c using products p where c.product_id=p.id and c.customer_id=p_customer and p.business_id=p_store;
  return jsonb_build_object('store_order_id',store_id,'replayed',false);
end $$;
revoke all on function public.place_whatsapp_store_request(uuid,uuid,uuid,text,text,text,jsonb) from public,anon,authenticated;
grant execute on function public.place_whatsapp_store_request(uuid,uuid,uuid,text,text,text,jsonb) to service_role;

commit;

-- ============================================================================
-- Source: migrations/025_remove_order_rejection.sql
-- ============================================================================
-- Clean up installations that already ran the earlier rejection implementation.
-- Preserve recorded reasons if they exist; dropping them would erase order history.
begin;
drop function if exists public.reject_marketplace_store_order(uuid,uuid,text);
do $$
declare has_reasons boolean;
begin
  if exists (select 1 from information_schema.columns where table_schema='public' and table_name='marketplace_store_orders' and column_name='rejection_reason') then
    execute 'select exists(select 1 from public.marketplace_store_orders where rejection_reason is not null)' into has_reasons;
    if has_reasons then
      raise notice 'Keeping rejection_reason to preserve recorded order history';
    else
      alter table public.marketplace_store_orders drop column rejection_reason;
    end if;
  end if;
end $$;
commit;

-- ============================================================================
-- Source: migrations/026_reject_store_order.sql
-- ============================================================================
-- Allow the owning seller to reject a pending store order, with an audit entry.
-- This does not send a customer notification or collect a reason.
begin;
create or replace function public.reject_store_order(p_order uuid, p_actor uuid)
returns boolean language plpgsql security definer set search_path = public as $$
declare target public.marketplace_store_orders%rowtype;
begin
  select * into target from public.marketplace_store_orders where id = p_order for update;
  if not found or not exists (select 1 from public.businesses where id = target.business_id and owner_id = p_actor) then
    return false;
  end if;
  if target.status <> 'PENDING' then return false; end if;
  update public.marketplace_store_orders set status = 'REJECTED' where id = target.id;
  insert into public.marketplace_order_status_history(store_order_id, previous_status, new_status, changed_by)
  values(target.id, 'PENDING', 'REJECTED', p_actor);
  return true;
end $$;
revoke all on function public.reject_store_order(uuid,uuid) from public, anon, authenticated;
grant execute on function public.reject_store_order(uuid,uuid) to service_role;
commit;

-- ============================================================================
-- Source: migrations/027_admin_store_order_actions.sql
-- ============================================================================
-- Only the trusted backend may call this function. It derives p_is_admin from
-- the verified session, never from customer-supplied request data.
begin;
create or replace function public.manage_store_order(p_order uuid, p_actor uuid, p_is_admin boolean, p_action text)
returns boolean language plpgsql security definer set search_path = public as $$
declare target public.marketplace_store_orders%rowtype; next_status text;
begin
  if p_actor is null or p_action not in ('accept', 'reject') then return false; end if;
  select * into target from public.marketplace_store_orders where id = p_order for update;
  if not found or (p_is_admin is not true and not exists
    (select 1 from public.businesses where id = target.business_id and owner_id = p_actor)) then
    return false;
  end if;
  if target.status <> 'PENDING' then return false; end if;
  next_status := case when p_action = 'accept' then 'ACCEPTED' else 'REJECTED' end;
  update public.marketplace_store_orders
    set status = next_status, confirmed_at = case when p_action = 'accept' then now() else null end
    where id = target.id;
  insert into public.marketplace_order_status_history(store_order_id, previous_status, new_status, changed_by)
    values(target.id, 'PENDING', next_status, p_actor);
  return true;
end $$;
revoke all on function public.manage_store_order(uuid,uuid,boolean,text) from public, anon, authenticated;
grant execute on function public.manage_store_order(uuid,uuid,boolean,text) to service_role;
commit;

-- ============================================================================
-- Source: migrations/028_customer_addresses.sql
-- ============================================================================
begin;
create table public.customer_addresses (
 id uuid primary key default gen_random_uuid(), user_id uuid not null references auth.users(id) on delete cascade,
 full_name text not null check(length(trim(full_name)) between 1 and 120), phone_number text not null check(length(trim(phone_number)) between 7 and 25),
 address_line_1 text not null check(length(trim(address_line_1)) between 1 and 150), address_line_2 text not null check(length(trim(address_line_2)) between 1 and 150), landmark text,
 city text not null check(length(trim(city)) between 1 and 100), state text not null check(length(trim(state)) between 1 and 100), postal_code text not null check(length(trim(postal_code)) between 1 and 20), country text not null check(length(trim(country)) between 1 and 100),
 address_type text not null check(address_type in ('Home','Office','Other')), custom_label text, latitude numeric check(latitude between -90 and 90), longitude numeric check(longitude between -180 and 180),
 is_default boolean not null default false, created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 check(address_type <> 'Other' or length(trim(coalesce(custom_label,''))) > 0), check((latitude is null) = (longitude is null)),
 check(lower(trim(country)) not in ('india','in') or postal_code ~ '^[1-9][0-9]{5}$')
);
create index customer_addresses_user_idx on public.customer_addresses(user_id);
create unique index customer_addresses_default_idx on public.customer_addresses(user_id) where is_default;
alter table public.customer_addresses enable row level security;
create policy address_read on public.customer_addresses for select to authenticated using (user_id=auth.uid());
-- Writes go through the authenticated backend and serialized functions below.
revoke all on public.customer_addresses from public, anon, authenticated;
grant select on public.customer_addresses to authenticated;
grant all on public.customer_addresses to service_role;
alter table public.marketplace_orders add column delivery_address_snapshot jsonb;
create function public.save_customer_address(p_user uuid,p_id uuid,p_data jsonb) returns jsonb language plpgsql security definer set search_path=public as $$
declare result customer_addresses%rowtype; make_default boolean;
begin
 perform pg_advisory_xact_lock(hashtextextended('address:' || p_user::text,0));
 if p_id is not null and not exists(select 1 from customer_addresses where id=p_id and user_id=p_user) then raise exception 'Address not found'; end if;
 make_default := coalesce((p_data->>'is_default')::boolean,false) or not exists(select 1 from customer_addresses where user_id=p_user);
 if make_default then update customer_addresses set is_default=false where user_id=p_user and is_default and id is distinct from p_id; end if;
 if p_id is null then
 insert into customer_addresses(user_id,full_name,phone_number,address_line_1,address_line_2,landmark,city,state,postal_code,country,address_type,custom_label,latitude,longitude,is_default)
 values(p_user,p_data->>'full_name',p_data->>'phone_number',p_data->>'address_line_1',p_data->>'address_line_2',nullif(p_data->>'landmark',''),p_data->>'city',p_data->>'state',p_data->>'postal_code',p_data->>'country',p_data->>'address_type',nullif(p_data->>'custom_label',''),(p_data->>'latitude')::numeric,(p_data->>'longitude')::numeric,make_default) returning * into result;
 else
 update customer_addresses set full_name=p_data->>'full_name',phone_number=p_data->>'phone_number',address_line_1=p_data->>'address_line_1',address_line_2=p_data->>'address_line_2',landmark=nullif(p_data->>'landmark',''),city=p_data->>'city',state=p_data->>'state',postal_code=p_data->>'postal_code',country=p_data->>'country',address_type=p_data->>'address_type',custom_label=nullif(p_data->>'custom_label',''),latitude=(p_data->>'latitude')::numeric,longitude=(p_data->>'longitude')::numeric,is_default=make_default,updated_at=now() where id=p_id and user_id=p_user returning * into result;
 end if;
 if not exists(select 1 from customer_addresses where user_id=p_user and is_default) then update customer_addresses set is_default=true where id=result.id returning * into result; end if;
 return to_jsonb(result);
end $$;
create function public.delete_customer_address(p_user uuid,p_id uuid) returns boolean language plpgsql security definer set search_path=public as $$
declare was_default boolean;
begin
 perform pg_advisory_xact_lock(hashtextextended('address:' || p_user::text,0));
 delete from customer_addresses where user_id=p_user and id=p_id returning is_default into was_default;
 if not found then return false; end if;
 if was_default then update customer_addresses set is_default=true where id=(select id from customer_addresses where user_id=p_user order by created_at,id limit 1); end if;
 return true;
end $$;
create function public.place_saved_address_request(p_customer uuid,p_store uuid,p_key uuid,p_address_id uuid,p_expected jsonb) returns jsonb language plpgsql security definer set search_path=public as $$
declare a customer_addresses%rowtype; result jsonb; address_text text; prior uuid;
begin
 perform pg_advisory_xact_lock(hashtextextended(p_customer::text || ':' || p_key::text,0));
 select id into prior from marketplace_orders where customer_id=p_customer and request_key=p_key;
 if prior is not null then
   select id into prior from marketplace_store_orders where order_id=prior and business_id=p_store;
   if prior is null then raise exception 'Request key already used'; end if;
   return jsonb_build_object('store_order_id',prior,'replayed',true);
 end if;
 select * into a from customer_addresses where user_id=p_customer and id=p_address_id for share;
 if not found then raise exception 'Address unavailable'; end if;
 address_text := concat_ws(', ',a.address_line_1,a.address_line_2,nullif(a.landmark,''),a.city,a.state,a.postal_code,a.country);
 result := place_whatsapp_store_request(p_customer,p_store,p_key,a.full_name,case when regexp_replace(a.phone_number,'[^0-9]','','g') ~ '^[6-9][0-9]{9}$' then '91' || regexp_replace(a.phone_number,'[^0-9]','','g') else regexp_replace(a.phone_number,'[^0-9]','','g') end,address_text,p_expected);
 update marketplace_orders set delivery_address_snapshot=to_jsonb(a)-'user_id'-'created_at'-'updated_at'-'is_default' where id=(select order_id from marketplace_store_orders where id=(result->>'store_order_id')::uuid);
 return result;
end $$;
revoke all on function public.save_customer_address(uuid,uuid,jsonb), public.delete_customer_address(uuid,uuid), public.place_saved_address_request(uuid,uuid,uuid,uuid,jsonb) from public,anon,authenticated;
grant execute on function public.save_customer_address(uuid,uuid,jsonb), public.delete_customer_address(uuid,uuid), public.place_saved_address_request(uuid,uuid,uuid,uuid,jsonb) to service_role;
commit;

-- ============================================================================
-- Source: migrations/029_delivery_partner_drafts.sql
-- ============================================================================
-- Partner application drafts only. No verification or allocation is enabled.
begin;
create table public.delivery_partner_profiles (
 id uuid primary key default gen_random_uuid(),
 user_id uuid not null unique references auth.users(id) on delete restrict,
 partner_type text not null default 'independent' check (partner_type in ('independent','salaried')),
 verification_status text not null default 'draft' check (verification_status in ('draft','pending_verification','under_review','additional_information_required','approved','rejected','suspended','deactivated')),
 full_name text, phone text, email text, current_address text, city text, service_area text,
 emergency_contact text, vehicle_type text, vehicle_registration text, vehicle_capacity text,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
alter table public.delivery_partner_profiles enable row level security;
revoke all on public.delivery_partner_profiles from public, anon, authenticated;
grant all on public.delivery_partner_profiles to service_role;

-- A draft save cannot change partner type or verification status. Locking serializes review.
create function public.save_delivery_partner_draft(p_user uuid, p_data jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare profile public.delivery_partner_profiles%rowtype;
begin
 if p_user is null or jsonb_typeof(p_data) is distinct from 'object' then raise exception 'Invalid draft'; end if;
 insert into public.delivery_partner_profiles(user_id) values(p_user) on conflict(user_id) do nothing;
 select * into profile from public.delivery_partner_profiles where user_id=p_user for update;
 if profile.partner_type <> 'independent' or profile.verification_status not in ('draft','additional_information_required') then
  raise exception 'Application is not editable';
 end if;
 update public.delivery_partner_profiles set
  full_name=p_data->>'full_name', phone=p_data->>'phone', email=p_data->>'email',
  current_address=p_data->>'current_address', city=p_data->>'city', service_area=p_data->>'service_area',
  emergency_contact=p_data->>'emergency_contact', vehicle_type=p_data->>'vehicle_type',
  vehicle_registration=p_data->>'vehicle_registration', vehicle_capacity=p_data->>'vehicle_capacity', updated_at=now()
 where id=profile.id returning * into profile;
 return to_jsonb(profile);
end $$;
revoke all on function public.save_delivery_partner_draft(uuid,jsonb) from public, anon, authenticated;
grant execute on function public.save_delivery_partner_draft(uuid,jsonb) to service_role;
commit;

-- ============================================================================
-- Source: migrations/030_delivery_partner_availability.sql
-- ============================================================================
-- Operational state is private and separate from application data.
begin;
create table public.delivery_partner_availability (
 partner_id uuid primary key references public.delivery_partner_profiles(id) on delete restrict,
 is_online boolean not null default false,
 latitude double precision check (latitude between -90 and 90),
 longitude double precision check (longitude between -180 and 180),
 accuracy_m double precision check (accuracy_m >= 0),
 location_recorded_at timestamptz,
 updated_at timestamptz not null default now(),
 check ((latitude is null) = (longitude is null)),
 check ((latitude is null) = (location_recorded_at is null))
);
alter table public.delivery_partner_availability enable row level security;
revoke all on public.delivery_partner_availability from public, anon, authenticated;
grant all on public.delivery_partner_availability to service_role;

create function public.set_delivery_partner_operational_state(p_user uuid, p_online boolean, p_lat double precision, p_lon double precision, p_accuracy double precision)
returns jsonb language plpgsql security definer set search_path = public as $$
declare profile public.delivery_partner_profiles%rowtype; state public.delivery_partner_availability%rowtype;
begin
 select * into profile from public.delivery_partner_profiles where user_id=p_user for update;
 if not found or profile.verification_status <> 'approved' then raise exception 'Approved profile required'; end if;
 -- Salaried shift rules are not yet configured; do not permit self-managed availability.
 if p_online is not null and profile.partner_type <> 'independent' then raise exception 'Availability managed by admin'; end if;
 if (p_lat is null) <> (p_lon is null) or (p_lat is not null and (p_lat not between -90 and 90 or p_lon not between -180 and 180 or p_accuracy is null or p_accuracy < 0)) then raise exception 'Invalid location'; end if;
 insert into public.delivery_partner_availability(partner_id) values(profile.id) on conflict do nothing;
 update public.delivery_partner_availability set
  is_online=coalesce(p_online,is_online), latitude=case when p_lat is null then latitude else p_lat end,
  longitude=case when p_lon is null then longitude else p_lon end,
  accuracy_m=case when p_lat is null then accuracy_m else p_accuracy end,
  location_recorded_at=case when p_lat is null then location_recorded_at else now() end,
  updated_at=now() where partner_id=profile.id returning * into state;
 return to_jsonb(state);
end $$;
revoke all on function public.set_delivery_partner_operational_state(uuid,boolean,double precision,double precision,double precision) from public, anon, authenticated;
grant execute on function public.set_delivery_partner_operational_state(uuid,boolean,double precision,double precision,double precision) to service_role;
commit;

-- ============================================================================
-- Source: migrations/031_delivery_partner_review.sql
-- ============================================================================
-- Application review transitions. Approval requires a recorded identity document;
-- document ingestion and policy-specific requirements must be configured separately.
begin;
create table public.delivery_partner_documents (
 id uuid primary key default gen_random_uuid(),
 partner_id uuid not null references public.delivery_partner_profiles(id) on delete restrict,
 document_type text not null check(document_type in ('identity','driving_licence','vehicle_registration','vehicle_photo','profile_photo')),
 storage_path text not null unique,
 created_at timestamptz not null default now()
);
create table public.delivery_partner_verifications (
 id uuid primary key default gen_random_uuid(),
 partner_id uuid not null references public.delivery_partner_profiles(id) on delete restrict,
 actor_id uuid not null references auth.users(id) on delete restrict,
 previous_status text not null, new_status text not null, reason text,
 created_at timestamptz not null default now()
);
alter table public.delivery_partner_documents enable row level security;
alter table public.delivery_partner_verifications enable row level security;
revoke all on public.delivery_partner_documents, public.delivery_partner_verifications from public, anon, authenticated;
grant all on public.delivery_partner_documents, public.delivery_partner_verifications to service_role;
create function public.submit_delivery_partner_application(p_user uuid) returns jsonb language plpgsql security definer set search_path=public as $$
declare profile public.delivery_partner_profiles%rowtype;
begin
 select * into profile from public.delivery_partner_profiles where user_id=p_user for update;
 if not found or profile.partner_type <> 'independent' or profile.verification_status not in ('draft','additional_information_required','rejected') then raise exception 'Application cannot be submitted'; end if;
 if coalesce(trim(profile.full_name),'')='' or coalesce(trim(profile.phone),'')='' or coalesce(trim(profile.current_address),'')='' or coalesce(trim(profile.city),'')='' or coalesce(trim(profile.service_area),'')='' or coalesce(trim(profile.emergency_contact),'')='' or coalesce(trim(profile.vehicle_type),'')='' or coalesce(trim(profile.vehicle_capacity),'')='' then raise exception 'Complete required application details'; end if;
 if not exists(select 1 from public.delivery_partner_documents where partner_id=profile.id and document_type='identity') then raise exception 'Identity document required'; end if;
 update public.delivery_partner_profiles set verification_status='pending_verification',updated_at=now() where id=profile.id returning * into profile;
 return to_jsonb(profile);
end $$;
create function public.review_delivery_partner_application(p_partner uuid,p_actor uuid,p_decision text,p_reason text) returns jsonb language plpgsql security definer set search_path=public as $$
declare profile public.delivery_partner_profiles%rowtype; old_status text;
begin
 if p_actor is null or p_decision not in ('approved','rejected','additional_information_required') then raise exception 'Invalid review'; end if;
 if p_decision <> 'approved' and coalesce(length(trim(p_reason)),0)=0 then raise exception 'Reason required'; end if;
 select * into profile from public.delivery_partner_profiles where id=p_partner for update;
 if not found or profile.verification_status not in ('pending_verification','under_review') then raise exception 'Application is not awaiting review'; end if;
 if p_decision='approved' and not exists(select 1 from public.delivery_partner_documents where partner_id=profile.id and document_type='identity') then raise exception 'Identity document required'; end if;
 old_status := profile.verification_status;
 update public.delivery_partner_profiles set verification_status=p_decision,updated_at=now() where id=profile.id returning * into profile;
 insert into public.delivery_partner_verifications(partner_id,actor_id,previous_status,new_status,reason) values(profile.id,p_actor,old_status,p_decision,nullif(trim(p_reason),''));
 return to_jsonb(profile);
end $$;
revoke all on function public.submit_delivery_partner_application(uuid), public.review_delivery_partner_application(uuid,uuid,text,text) from public,anon,authenticated;
grant execute on function public.submit_delivery_partner_application(uuid), public.review_delivery_partner_application(uuid,uuid,text,text) to service_role;
commit;

-- ============================================================================
-- Source: migrations/032_delivery_partner_private_documents.sql
-- ============================================================================
-- Private identity documents; all access is mediated by the backend.
begin;
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values ('delivery-partner-documents','delivery-partner-documents',false,5242880,array['image/jpeg','image/png'])
on conflict(id) do nothing;
-- Refuse to operate if an existing bucket is public or has different security settings.
do $$ begin
 if not exists(select 1 from storage.buckets where id='delivery-partner-documents' and public=false and file_size_limit=5242880 and allowed_mime_types = array['image/jpeg','image/png']) then
  raise exception 'Delivery document bucket configuration differs';
 end if;
end $$;
create function public.register_delivery_identity_document(p_user uuid,p_path text) returns jsonb language plpgsql security definer set search_path=public as $$
declare profile public.delivery_partner_profiles%rowtype; doc public.delivery_partner_documents%rowtype;
begin
 select * into profile from public.delivery_partner_profiles where user_id=p_user for update;
 if not found or profile.partner_type <> 'independent' or profile.verification_status not in ('draft','additional_information_required') then raise exception 'Application is not editable'; end if;
 if p_path is null or p_path not like profile.id::text || '/%' then raise exception 'Invalid document path'; end if;
 insert into public.delivery_partner_documents(partner_id,document_type,storage_path) values(profile.id,'identity',p_path) returning * into doc;
 return jsonb_build_object('id',doc.id,'created_at',doc.created_at);
end $$;
revoke all on function public.register_delivery_identity_document(uuid,text) from public,anon,authenticated;
grant execute on function public.register_delivery_identity_document(uuid,text) to service_role;
commit;

-- ============================================================================
-- Source: migrations/033_delivery_partner_admin_controls.sql
-- ============================================================================
-- Super-admin mediated partner suspension/reactivation; no delivery tasks are changed.
begin;
create function public.manage_delivery_partner_status(p_partner uuid,p_actor uuid,p_action text,p_reason text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare profile public.delivery_partner_profiles%rowtype; old_status text; next_status text;
begin
 if p_actor is null or p_action not in ('suspend','reactivate') or length(trim(coalesce(p_reason,''))) not between 1 and 1000 then raise exception 'Invalid action'; end if;
 select * into profile from public.delivery_partner_profiles where id=p_partner for update;
 if not found then raise exception 'Partner not found'; end if;
 old_status := profile.verification_status;
 if (p_action='suspend' and old_status <> 'approved') or (p_action='reactivate' and old_status <> 'suspended') then raise exception 'Partner status changed'; end if;
 next_status := case when p_action='suspend' then 'suspended' else 'approved' end;
 update public.delivery_partner_profiles set verification_status=next_status,updated_at=now() where id=profile.id returning * into profile;
 if p_action='suspend' then update public.delivery_partner_availability set is_online=false,updated_at=now() where partner_id=profile.id; end if;
 insert into public.delivery_partner_verifications(partner_id,actor_id,previous_status,new_status,reason) values(profile.id,p_actor,old_status,next_status,trim(p_reason));
 return jsonb_build_object('id',profile.id,'verification_status',profile.verification_status);
end $$;
revoke all on function public.manage_delivery_partner_status(uuid,uuid,text,text) from public,anon,authenticated;
grant execute on function public.manage_delivery_partner_status(uuid,uuid,text,text) to service_role;
commit;

-- ============================================================================
-- Source: migrations/034_logistics_operations.sql
-- ============================================================================
-- Additive logistics core. Apply after 033. No historical order is enrolled automatically.
begin;
alter table public.delivery_partner_profiles
 add column max_active_orders integer check(max_active_orders between 1 and 50),
 add column capacity_kg numeric check(capacity_kg > 0 and capacity_kg <= 10000),
 add column capacity_litres numeric check(capacity_litres > 0 and capacity_litres <= 100000),
 add column employee_id text unique,
 add column employment_active boolean not null default false,
 add column shift_start timestamptz,
 add column shift_end timestamptz,
 add constraint delivery_partner_shift_pair check((shift_start is null and shift_end is null) or (shift_start is not null and shift_end > shift_start));
create table public.delivery_settings (
 id boolean primary key default true check(id), config jsonb, updated_by uuid references auth.users(id), updated_at timestamptz not null default now()
);
insert into public.delivery_settings(id) values(true);
create table public.delivery_settings_history (
 id uuid primary key default gen_random_uuid(), actor_id uuid references auth.users(id), old_config jsonb, new_config jsonb not null, created_at timestamptz not null default now()
);
create table public.delivery_tasks (
 id uuid primary key default gen_random_uuid(), store_order_id uuid not null unique references public.marketplace_store_orders(id) on delete restrict,
 status text not null check(status in ('independent_allocation','salaried_allocation','admin_intervention','assigned','accepted','reached_pickup','picked_up','on_the_way','awaiting_customer_confirmation','completed','cancelled')),
 partner_id uuid references public.delivery_partner_profiles(id), assignment_type text check(assignment_type in ('independent','salaried','manual')),
 pickup_address text not null, pickup_lat double precision not null check(pickup_lat between -90 and 90), pickup_lon double precision not null check(pickup_lon between -180 and 180),
 destination_address text not null, destination_lat double precision not null check(destination_lat between -90 and 90), destination_lon double precision not null check(destination_lon between -180 and 180),
 service_area text not null, package_description text not null, weight_kg numeric not null check(weight_kg>0), volume_litres numeric not null check(volume_litres>0), eligible_vehicles text[] not null check(cardinality(eligible_vehicles)>0), urgency text not null check(urgency in ('standard','urgent')),
 config jsonb not null, independent_deadline timestamptz not null, confirmation_deadline timestamptz,
 created_by uuid not null references auth.users(id), created_at timestamptz not null default now(), updated_at timestamptz not null default now(), completed_at timestamptz
);
create index delivery_tasks_status_due_idx on public.delivery_tasks(status,independent_deadline);
create index delivery_tasks_partner_idx on public.delivery_tasks(partner_id,status);
create table public.delivery_assignments (
 id uuid primary key default gen_random_uuid(), task_id uuid not null references public.delivery_tasks(id), partner_id uuid not null references public.delivery_partner_profiles(id),
 assignment_type text not null check(assignment_type in ('independent','salaried','manual')), status text not null check(status in ('awaiting_ack','accepted','expired','rejected','reassigned','completed','cancelled')),
 score numeric, assigned_at timestamptz not null default now(), acknowledged_at timestamptz, acknowledgement_deadline timestamptz, ended_at timestamptz
);
create unique index delivery_one_live_assignment on public.delivery_assignments(task_id) where ended_at is null;
create index delivery_assignment_workload_idx on public.delivery_assignments(partner_id) where ended_at is null;
create table public.delivery_allocation_attempts (
 id uuid primary key default gen_random_uuid(), task_id uuid not null references public.delivery_tasks(id), partner_id uuid not null references public.delivery_partner_profiles(id),
 kind text not null check(kind in ('independent','salaried')), status text not null check(status in ('offered','accepted','rejected','expired','unavailable')), score numeric, offered_at timestamptz not null default now(), responded_at timestamptz, expires_at timestamptz,
 unique(task_id,partner_id,kind)
);
create table public.delivery_status_history (
 id uuid primary key default gen_random_uuid(), task_id uuid not null references public.delivery_tasks(id), actor_id uuid references auth.users(id), event text not null, old_status text, new_status text, remarks text,
 latitude double precision check(latitude between -90 and 90), longitude double precision check(longitude between -180 and 180), created_at timestamptz not null default now()
);
create table public.delivery_exceptions (
 id uuid primary key default gen_random_uuid(), task_id uuid not null references public.delivery_tasks(id), code text not null, reason text not null, opened_by uuid references auth.users(id), created_at timestamptz not null default now(), resolved_by uuid references auth.users(id), resolved_at timestamptz, resolution text
);
create unique index delivery_open_exception_idx on public.delivery_exceptions(task_id,code) where resolved_at is null;
create table public.delivery_notifications (
 id uuid primary key default gen_random_uuid(), recipient_id uuid references auth.users(id), for_admin boolean not null default false, task_id uuid references public.delivery_tasks(id), message text not null, dedupe_key text not null unique, created_at timestamptz not null default now(), read_at timestamptz,
 check(recipient_id is not null or for_admin)
);
create index delivery_notification_user_idx on public.delivery_notifications(recipient_id,created_at desc);
create table public.delivery_compensation_records (
 id uuid primary key default gen_random_uuid(), task_id uuid not null unique references public.delivery_tasks(id), partner_id uuid not null references public.delivery_partner_profiles(id), partner_type text not null,
 completed_deliveries integer not null default 1 check(completed_deliveries=1), settlement_status text not null default 'deferred' check(settlement_status='deferred'), created_at timestamptz not null default now()
);
create table public.delivery_worker_health (id boolean primary key default true check(id), last_success_at timestamptz, processed integer);
insert into public.delivery_worker_health(id) values(true);
do $$ declare t text; begin foreach t in array array['delivery_settings','delivery_settings_history','delivery_tasks','delivery_assignments','delivery_allocation_attempts','delivery_status_history','delivery_exceptions','delivery_notifications','delivery_compensation_records','delivery_worker_health'] loop
 execute format('alter table public.%I enable row level security',t);
 execute format('revoke all on public.%I from public,anon,authenticated',t);
 execute format('grant all on public.%I to service_role',t);
 end loop; end $$;

create function public.delivery_distance_km(a double precision,b double precision,c double precision,d double precision) returns double precision language sql immutable strict set search_path=public as $$
 select 6371.0*2*asin(sqrt(least(1.0,power(sin(radians(c-a)/2),2)+cos(radians(a))*cos(radians(c))*power(sin(radians(d-b)/2),2))))
$$;
create function public.delivery_notice(p_task uuid,p_user uuid,p_admin boolean,p_message text,p_key text) returns void language sql security definer set search_path=public as $$
 insert into delivery_notifications(task_id,recipient_id,for_admin,message,dedupe_key) values(p_task,p_user,p_admin,p_message,p_key) on conflict(dedupe_key) do nothing
$$;
create function public.delivery_log(p_task uuid,p_actor uuid,p_event text,p_old text,p_new text,p_reason text default null) returns void language sql security definer set search_path=public as $$
 insert into delivery_status_history(task_id,actor_id,event,old_status,new_status,remarks,latitude,longitude)
 select p_task,p_actor,p_event,p_old,p_new,p_reason,a.latitude,a.longitude from (select 1) seed
 left join delivery_partner_profiles p on p.user_id=p_actor and p.id=(select partner_id from delivery_tasks where id=p_task)
 left join delivery_partner_availability a on a.partner_id=p.id and a.is_online and a.location_recorded_at>=now()-interval '5 minutes'
$$;
create function public.delivery_raise_exception(p_task uuid,p_code text,p_reason text,p_actor uuid default null) returns void language plpgsql security definer set search_path=public as $$
declare x uuid;
begin
 insert into delivery_exceptions(task_id,code,reason,opened_by) values(p_task,p_code,p_reason,p_actor) on conflict(task_id,code) where resolved_at is null do nothing returning id into x;
 if x is not null then perform delivery_notice(p_task,null,true,p_reason,'exception:'||x); end if;
end $$;

-- Eligibility is rechecked under the partner lock when reserving capacity.
create function public.delivery_candidates(p_task uuid,p_type text default null) returns table(partner_id uuid,user_id uuid,full_name text,partner_type text,vehicle_type text,distance_km double precision,active_orders bigint,score double precision) language sql stable security definer set search_path=public as $$
 with eligible as (
 select p.id,p.user_id,p.full_name,p.partner_type,p.vehicle_type,
 delivery_distance_km(a.latitude,a.longitude,t.pickup_lat,t.pickup_lon) as distance_km,
 (select count(*) from delivery_assignments x where x.partner_id=p.id and x.ended_at is null) as workload,
 least(p.max_active_orders,(t.config->>'max_active_orders')::integer) as capacity,t.config,
 coalesce((select avg(delivery_distance_km(q.destination_lat,q.destination_lon,t.pickup_lat,t.pickup_lon))
   from delivery_assignments x join delivery_tasks q on q.id=x.task_id where x.partner_id=p.id and x.ended_at is null),
   delivery_distance_km(a.latitude,a.longitude,t.pickup_lat,t.pickup_lon)) as route_km
 from delivery_tasks t join marketplace_store_orders so on so.id=t.store_order_id join marketplace_orders o on o.id=so.order_id
 cross join delivery_partner_profiles p join delivery_partner_availability a on a.partner_id=p.id
 where t.id=p_task and p.verification_status='approved' and (p_type is null or p.partner_type=p_type)
 and p.user_id is distinct from o.customer_id and a.is_online and a.latitude is not null
 and a.location_recorded_at >= now()-make_interval(secs=>(t.config->>'location_max_age_seconds')::integer)
 and a.accuracy_m <= (t.config->>'max_location_accuracy_m')::numeric
 and lower(trim(p.service_area))=lower(trim(t.service_area)) and lower(trim(p.vehicle_type))=any(t.eligible_vehicles)
 and p.capacity_kg>=t.weight_kg+coalesce((select sum(q.weight_kg) from delivery_assignments x join delivery_tasks q on q.id=x.task_id where x.partner_id=p.id and x.ended_at is null),0)
 and p.capacity_litres>=t.volume_litres+coalesce((select sum(q.volume_litres) from delivery_assignments x join delivery_tasks q on q.id=x.task_id where x.partner_id=p.id and x.ended_at is null),0) and p.max_active_orders is not null
 and (p.partner_type='independent' or (p.employment_active and p.shift_start<=now() and p.shift_end>now()))
 ) select id,user_id,full_name,partner_type,vehicle_type,distance_km,workload,
 100*((config->'weights'->>'distance')::double precision/(1+distance_km)+
 (config->'weights'->>'workload')::double precision*(1-workload::double precision/capacity)+
 (config->'weights'->>'route')::double precision/(1+route_km)+
 (config->'weights'->>'availability')::double precision+(config->'weights'->>'vehicle')::double precision)/100
 from eligible where workload<capacity and distance_km <= (select max(value::double precision) from jsonb_array_elements_text(config->'search_radii_km'))
 order by 8 desc,6,1
$$;
create function public.delivery_publish_offers(p_task uuid) returns void language plpgsql security definer set search_path=public as $$
declare t delivery_tasks%rowtype; c record; offer uuid;
begin
 select * into t from delivery_tasks where id=p_task;
 if t.status<>'independent_allocation' or t.independent_deadline<=now() then return; end if;
 for c in select * from delivery_candidates(p_task,'independent') loop
  offer:=null;
  insert into delivery_allocation_attempts(task_id,partner_id,kind,status,score,expires_at) values(p_task,c.partner_id,'independent','offered',c.score,t.independent_deadline) on conflict do nothing returning id into offer;
  if offer is not null then perform delivery_notice(p_task,c.user_id,false,'A delivery opportunity is available.','offer:'||offer); end if;
 end loop;
end $$;

create function public.delivery_select_order(p_store_order uuid,p_actor uuid,p_admin boolean,p_details jsonb) returns uuid language plpgsql security definer set search_path=public as $$
declare so marketplace_store_orders%rowtype; o marketplace_orders%rowtype; cfg jsonb; result uuid;
begin
 perform pg_advisory_xact_lock(74901);
 select * into so from marketplace_store_orders where id=p_store_order for update;
 if not found or (p_admin is not true and not exists(select 1 from businesses where id=so.business_id and owner_id=p_actor)) then raise exception 'Delivery access denied'; end if;
 select id into result from delivery_tasks where store_order_id=so.id; if result is not null then return result; end if;
 if so.confirmed_at is null or so.status not in ('ACCEPTED','PROCESSING','READY_FOR_DISPATCH') then raise exception 'Confirm this seller order before selecting delivery'; end if;
 select config into cfg from delivery_settings where id;
 if cfg is null or not coalesce((cfg->>'enabled')::boolean,false) then raise exception 'Configure and enable allocation settings first'; end if;
 select * into o from marketplace_orders where id=so.order_id;
 if o.customer_id is null then raise exception 'Customer account required for receipt confirmation'; end if;
 insert into delivery_tasks(store_order_id,status,pickup_address,pickup_lat,pickup_lon,destination_address,destination_lat,destination_lon,service_area,package_description,weight_kg,volume_litres,eligible_vehicles,urgency,config,independent_deadline,created_by)
 values(so.id,'independent_allocation',p_details->>'pickup_address',(p_details->>'pickup_lat')::double precision,(p_details->>'pickup_lon')::double precision,o.delivery_address,(p_details->>'destination_lat')::double precision,(p_details->>'destination_lon')::double precision,p_details->>'service_area',p_details->>'package_description',(p_details->>'weight_kg')::numeric,(p_details->>'volume_litres')::numeric,array(select lower(trim(value)) from jsonb_array_elements_text(p_details->'eligible_vehicles')),p_details->>'urgency',cfg,now()+make_interval(secs=>(cfg->>'independent_timeout_seconds')::integer),p_actor) returning id into result;
 perform delivery_log(result,p_actor,'delivery_selected',null,'independent_allocation');
 perform delivery_publish_offers(result);
 return result;
end $$;

create function public.delivery_reserve(p_task uuid,p_partner uuid,p_type text,p_actor uuid) returns uuid language plpgsql security definer set search_path=public as $$
declare t delivery_tasks%rowtype; p delivery_partner_profiles%rowtype; c record; aid uuid; due timestamptz;
begin
 perform pg_advisory_xact_lock(74901);
 select * into t from delivery_tasks where id=p_task for update;
 select * into p from delivery_partner_profiles where id=p_partner for update;
 select * into c from delivery_candidates(p_task,null) where partner_id=p_partner;
 if not found then raise exception 'Partner is no longer eligible'; end if;
 if exists(select 1 from delivery_assignments where task_id=p_task and ended_at is null) then raise exception 'Delivery no longer available'; end if;
 due:=now()+make_interval(secs=>(t.config->>'acknowledgement_timeout_seconds')::integer);
 insert into delivery_assignments(task_id,partner_id,assignment_type,status,score,acknowledgement_deadline,acknowledged_at)
 values(p_task,p_partner,p_type,case when p_type='independent' then 'accepted' else 'awaiting_ack' end,c.score,case when p_type='independent' then null else due end,case when p_type='independent' then now() else null end) returning id into aid;
 update delivery_tasks set partner_id=p_partner,assignment_type=p_type,status=case when p_type='independent' then 'accepted' else 'assigned' end,updated_at=now() where id=p_task;
 perform delivery_log(p_task,p_actor,'partner_assigned',t.status,case when p_type='independent' then 'accepted' else 'assigned' end,p_type);
 perform delivery_notice(p_task,p.user_id,false,'Delivery assigned. Open your active deliveries.','assignment:'||aid);
 perform delivery_notice(p_task,o.customer_id,false,'A delivery partner has been assigned.','customer-assignment:'||aid) from marketplace_orders o join marketplace_store_orders so on so.order_id=o.id where so.id=t.store_order_id;
 perform delivery_notice(p_task,b.owner_id,false,'A delivery partner has been assigned.','seller-assignment:'||aid) from businesses b join marketplace_store_orders so on so.business_id=b.id where so.id=t.store_order_id and b.owner_id is not null;
 return aid;
end $$;
create function public.delivery_accept(p_task uuid,p_user uuid) returns uuid language plpgsql security definer set search_path=public as $$
declare t delivery_tasks%rowtype; pid uuid; aid uuid;
begin
 perform pg_advisory_xact_lock(74901);
 select * into t from delivery_tasks where id=p_task for update;
 select id into pid from delivery_partner_profiles where user_id=p_user and partner_type='independent';
 if t.partner_id=pid and t.status='accepted' then select id into aid from delivery_assignments where task_id=p_task and ended_at is null; return aid; end if;
 if t.id is null or t.status<>'independent_allocation' or t.independent_deadline<=now() or pid is null then raise exception 'Delivery no longer available'; end if;
 if exists(select 1 from delivery_allocation_attempts where task_id=p_task and partner_id=pid and kind='independent' and status='rejected') then raise exception 'Offer was declined'; end if;
 aid:=delivery_reserve(p_task,pid,'independent',p_user);
 insert into delivery_allocation_attempts(task_id,partner_id,kind,status,responded_at) values(p_task,pid,'independent','accepted',now()) on conflict(task_id,partner_id,kind) do update set status='accepted',responded_at=now();
 update delivery_allocation_attempts set status='unavailable',responded_at=now() where task_id=p_task and partner_id<>pid and status='offered';
 return aid;
end $$;
create function public.delivery_decline(p_task uuid,p_user uuid) returns void language plpgsql security definer set search_path=public as $$
declare pid uuid;
begin
 perform pg_advisory_xact_lock(74901);
 select id into pid from delivery_partner_profiles where user_id=p_user and partner_type='independent';
 if pid is null or not exists(select 1 from delivery_tasks where id=p_task and status='independent_allocation' and independent_deadline>now()) or not exists(select 1 from delivery_candidates(p_task,'independent') where partner_id=pid) then raise exception 'Offer unavailable'; end if;
 insert into delivery_allocation_attempts(task_id,partner_id,kind,status,responded_at) values(p_task,pid,'independent','rejected',now()) on conflict(task_id,partner_id,kind) do update set status='rejected',responded_at=now();
 perform delivery_log(p_task,p_user,'offer_declined',null,null);
end $$;
create function public.delivery_fallback(p_task uuid) returns void language plpgsql security definer set search_path=public as $$
declare t delivery_tasks%rowtype; c record; radius double precision; aid uuid;
begin
 select * into t from delivery_tasks where id=p_task for update;
 if t.status<>'salaried_allocation' or t.independent_deadline>now() then return; end if;
 for radius in select value::double precision from jsonb_array_elements_text(t.config->'search_radii_km') order by 1 loop
  for c in select * from delivery_candidates(p_task,'salaried') x where distance_km<=radius and not exists(select 1 from delivery_allocation_attempts a where a.task_id=p_task and a.partner_id=x.partner_id and a.kind='salaried') loop
   begin
    aid:=delivery_reserve(p_task,c.partner_id,'salaried',null);
    insert into delivery_allocation_attempts(task_id,partner_id,kind,status,score,expires_at) select p_task,c.partner_id,'salaried','offered',c.score,acknowledgement_deadline from delivery_assignments where id=aid;
    return;
   exception when raise_exception then
    if sqlerrm <> 'Partner is no longer eligible' then raise; end if;
   end;
  end loop;
 end loop;
 update delivery_tasks set status='admin_intervention',partner_id=null,updated_at=now() where id=p_task;
 perform delivery_log(p_task,null,'allocation_exhausted',t.status,'admin_intervention');
 perform delivery_raise_exception(p_task,'unassigned','No eligible salaried partner is available.');
end $$;
create function public.process_delivery_jobs() returns integer language plpgsql security definer set search_path=public as $$
declare t delivery_tasks%rowtype; a delivery_assignments%rowtype; n integer:=0; p delivery_partner_profiles%rowtype;
begin
 -- Across all server instances: one short database transaction owns allocation.
 if not pg_try_advisory_xact_lock(74901) then return 0; end if;
 for t in select * from delivery_tasks where status in ('independent_allocation','salaried_allocation','assigned','accepted','reached_pickup','picked_up','on_the_way','awaiting_customer_confirmation') order by updated_at limit 200 for update skip locked loop
  n:=n+1;
  if t.status='independent_allocation' then
   if t.independent_deadline<=now() then
    update delivery_allocation_attempts set status='expired',responded_at=now() where task_id=t.id and status='offered';
    update delivery_tasks set status='salaried_allocation',updated_at=now() where id=t.id;
    perform delivery_log(t.id,null,'independent_window_expired','independent_allocation','salaried_allocation');
    perform delivery_fallback(t.id);
   else perform delivery_publish_offers(t.id); end if;
  elsif t.status='salaried_allocation' then perform delivery_fallback(t.id);
  elsif t.status='assigned' then
   select * into a from delivery_assignments where task_id=t.id and ended_at is null;
   select * into p from delivery_partner_profiles where id=t.partner_id;
   if a.acknowledgement_deadline<=now() or p.verification_status<>'approved' then
    update delivery_assignments set status='expired',ended_at=now() where id=a.id;
    update delivery_allocation_attempts set status='expired',responded_at=now() where task_id=t.id and partner_id=t.partner_id and status='offered';
    update delivery_tasks set status='salaried_allocation',partner_id=null,updated_at=now() where id=t.id;
    perform delivery_log(t.id,null,'acknowledgement_expired','assigned','salaried_allocation');
    perform delivery_fallback(t.id);
   end if;
  elsif t.status='awaiting_customer_confirmation' and t.confirmation_deadline<=now() then
   perform delivery_raise_exception(t.id,'customer_confirmation_overdue','Customer has not confirmed receipt.');
  end if;
  if exists(select 1 from delivery_tasks current_task join delivery_partner_profiles current_profile on current_profile.id=current_task.partner_id where current_task.id=t.id and current_profile.verification_status<>'approved') then
   perform delivery_raise_exception(t.id,'partner_unavailable','Assigned partner is no longer approved; administrator intervention required.');
  end if;
  -- Rotate scanned rows fairly when the queue exceeds the batch size.
  update delivery_tasks set updated_at=now() where id=t.id;
 end loop;
 insert into delivery_worker_health(id,last_success_at,processed) values(true,now(),n) on conflict(id) do update set last_success_at=now(),processed=n;
 return n;
end $$;

create function public.delivery_partner_transition(p_task uuid,p_user uuid,p_action text,p_reason text default null) returns void language plpgsql security definer set search_path=public as $$
declare t delivery_tasks%rowtype; p delivery_partner_profiles%rowtype; a delivery_assignments%rowtype; next_status text;
begin
 perform pg_advisory_xact_lock(74901);
 select * into t from delivery_tasks where id=p_task for update;
 select * into p from delivery_partner_profiles where user_id=p_user;
 if t.id is null or p.id is null or t.partner_id is distinct from p.id or p.verification_status<>'approved' then raise exception 'Delivery access denied'; end if;
 select * into a from delivery_assignments where task_id=t.id and ended_at is null for update;
 if a.id is null then raise exception 'No active assignment'; end if;
 if p_action='reject' then
  if t.status not in ('assigned','accepted','reached_pickup') or length(trim(coalesce(p_reason,'')))=0 then raise exception 'Report an exception after pickup; a reason is required'; end if;
  update delivery_assignments set status='rejected',ended_at=now() where id=a.id;
  update delivery_allocation_attempts set status='rejected',responded_at=now() where task_id=t.id and partner_id=p.id;
  update delivery_tasks set status='admin_intervention',partner_id=null,updated_at=now() where id=t.id;
  perform delivery_log(t.id,p_user,'partner_cancelled',t.status,'admin_intervention',p_reason);
  perform delivery_raise_exception(t.id,'partner_cancelled',p_reason,p_user);
  if a.assignment_type='salaried' then
   update delivery_tasks set status='salaried_allocation' where id=t.id;
   perform delivery_fallback(t.id);
  end if;
  return;
 end if;
 next_status:=case
 when p_action='acknowledge' and t.status='assigned' and a.acknowledgement_deadline>now() then 'accepted'
 when p_action='reached_pickup' and t.status='accepted' then 'reached_pickup'
 when p_action='picked_up' and t.status='reached_pickup' then 'picked_up'
 when p_action='on_the_way' and t.status='picked_up' then 'on_the_way'
 when p_action='reached_customer' and t.status='on_the_way' then 'awaiting_customer_confirmation' else null end;
 if next_status is null then raise exception 'Invalid or expired delivery transition'; end if;
 if p_action='acknowledge' then
  update delivery_assignments set status='accepted',acknowledged_at=now() where id=a.id;
  update delivery_allocation_attempts set status='accepted',responded_at=now() where task_id=t.id and partner_id=p.id and status='offered';
 end if;
 update delivery_tasks set status=next_status,updated_at=now(),confirmation_deadline=case when next_status='awaiting_customer_confirmation' then now()+make_interval(secs=>(config->>'confirmation_timeout_seconds')::integer) else confirmation_deadline end where id=t.id;
 perform delivery_log(t.id,p_user,p_action,t.status,next_status,p_reason);
 if next_status='on_the_way' then
  insert into marketplace_order_status_history(store_order_id,previous_status,new_status,changed_by) select id,status,'OUT_FOR_DELIVERY',p_user from marketplace_store_orders where id=t.store_order_id;
  update marketplace_store_orders set status='OUT_FOR_DELIVERY' where id=t.store_order_id;
 end if;
 if next_status in ('picked_up','on_the_way','awaiting_customer_confirmation') then
  perform delivery_notice(t.id,o.customer_id,false,case when next_status='awaiting_customer_confirmation' then 'Your partner has arrived. Confirm receipt after receiving your order.' else 'Delivery update: '||replace(next_status,'_',' ') end,'customer-status:'||t.id||':'||next_status) from marketplace_orders o join marketplace_store_orders so on so.order_id=o.id where so.id=t.store_order_id;
 end if;
end $$;
create function public.delivery_customer_confirm(p_task uuid,p_user uuid) returns void language plpgsql security definer set search_path=public as $$
declare t delivery_tasks%rowtype; so marketplace_store_orders%rowtype; p delivery_partner_profiles%rowtype;
begin
 perform pg_advisory_xact_lock(74901);
 select * into t from delivery_tasks where id=p_task for update;
 select * into so from marketplace_store_orders where id=t.store_order_id;
 if t.id is null or not exists(select 1 from marketplace_orders where id=so.order_id and customer_id=p_user) then raise exception 'Delivery access denied'; end if;
 if t.status='completed' then return; end if;
 if t.status<>'awaiting_customer_confirmation' then raise exception 'Delivery is not awaiting your confirmation'; end if;
 select * into p from delivery_partner_profiles where id=t.partner_id;
 if p.user_id=p_user then raise exception 'Partner cannot confirm customer receipt'; end if;
 update delivery_tasks set status='completed',completed_at=now(),updated_at=now() where id=t.id;
 update delivery_assignments set status='completed',ended_at=now() where task_id=t.id and ended_at is null;
 update marketplace_store_orders set status='DELIVERED' where id=so.id;
 insert into marketplace_order_status_history(store_order_id,previous_status,new_status,changed_by) values(so.id,so.status,'DELIVERED',p_user);
 perform delivery_log(t.id,p_user,'customer_confirmed',t.status,'delivered');
 perform delivery_log(t.id,p_user,'delivery_completed','delivered','completed');
 insert into delivery_compensation_records(task_id,partner_id,partner_type) values(t.id,p.id,p.partner_type) on conflict(task_id) do nothing;
 update delivery_exceptions set resolved_at=now(),resolved_by=p_user,resolution='Customer confirmed receipt' where task_id=t.id and code='customer_confirmation_overdue' and resolved_at is null;
 perform delivery_notice(t.id,p.user_id,false,'Customer confirmed receipt. Delivery completed.','completed-partner:'||t.id);
 perform delivery_notice(t.id,p_user,false,'Delivery completed. Thank you for confirming receipt.','completed-customer:'||t.id);
 perform delivery_notice(t.id,b.owner_id,false,'Delivery completed.','completed-seller:'||t.id) from businesses b where b.id=so.business_id and b.owner_id is not null;
end $$;
create function public.delivery_manual_assign(p_task uuid,p_partner uuid,p_actor uuid,p_reason text) returns uuid language plpgsql security definer set search_path=public as $$
declare t delivery_tasks%rowtype; aid uuid;
begin
 perform pg_advisory_xact_lock(74901);
 select * into t from delivery_tasks where id=p_task for update;
 if t.id is null or t.status not in ('admin_intervention','salaried_allocation','assigned','accepted','reached_pickup') or t.independent_deadline>now() then raise exception 'Independent priority window must finish; reassignment is allowed only before pickup'; end if;
 if length(trim(coalesce(p_reason,'')))=0 then raise exception 'Reason required'; end if;
 if t.partner_id=p_partner then raise exception 'Partner is already assigned'; end if;
 perform delivery_notice(t.id,p.user_id,false,'This delivery has been reassigned by an administrator.','reassigned:'||a.id) from delivery_assignments a join delivery_partner_profiles p on p.id=a.partner_id where a.task_id=t.id and a.ended_at is null;
 update delivery_allocation_attempts set status='unavailable',responded_at=now() where task_id=t.id and status='offered';
 update delivery_assignments set status='reassigned',ended_at=now() where task_id=t.id and ended_at is null;
 aid:=delivery_reserve(t.id,p_partner,'manual',p_actor);
 perform delivery_log(t.id,p_actor,'manual_assignment',t.status,'assigned',p_reason);
 update delivery_exceptions set resolved_at=now(),resolved_by=p_actor,resolution=p_reason where task_id=t.id and code in ('unassigned','partner_cancelled') and resolved_at is null;
 return aid;
end $$;
create function public.delivery_admin_cancel(p_task uuid,p_actor uuid,p_reason text) returns void language plpgsql security definer set search_path=public as $$
declare t delivery_tasks%rowtype;
begin
 perform pg_advisory_xact_lock(74901);
 select * into t from delivery_tasks where id=p_task for update;
 if t.id is null or t.status in ('picked_up','on_the_way','awaiting_customer_confirmation','completed','cancelled') then raise exception 'Cancellation is only allowed before pickup'; end if;
 if length(trim(coalesce(p_reason,'')))=0 then raise exception 'Reason required'; end if;
 perform delivery_notice(t.id,p.user_id,false,'This delivery has been cancelled by an administrator.','cancelled-partner:'||t.id) from delivery_partner_profiles p where p.id=t.partner_id;
 update delivery_assignments set status='cancelled',ended_at=now() where task_id=t.id and ended_at is null;
 update delivery_allocation_attempts set status='unavailable',responded_at=now() where task_id=t.id and status='offered';
 update delivery_tasks set status='cancelled',updated_at=now() where id=t.id;
 perform delivery_log(t.id,p_actor,'delivery_cancelled',t.status,'cancelled',p_reason);
 perform delivery_notice(t.id,o.customer_id,false,'Delivery allocation cancelled. Please contact the seller.','cancelled-customer:'||t.id) from marketplace_orders o join marketplace_store_orders so on so.order_id=o.id where so.id=t.store_order_id;
end $$;

create function public.delivery_save_settings(p_actor uuid,p_config jsonb) returns void language plpgsql security definer set search_path=public as $$
declare old jsonb;
begin
 perform pg_advisory_xact_lock(74901);
 select config into old from delivery_settings where id for update;
 update delivery_settings set config=p_config,updated_by=p_actor,updated_at=now() where id;
 insert into delivery_settings_history(actor_id,old_config,new_config) values(p_actor,old,p_config);
end $$;
create function public.delivery_configure_partner(p_partner uuid,p_actor uuid,p_data jsonb) returns void language plpgsql security definer set search_path=public as $$
declare p delivery_partner_profiles%rowtype;
begin
 perform pg_advisory_xact_lock(74901);
 select * into p from delivery_partner_profiles where id=p_partner for update;
 if not found or p.verification_status<>'approved' then raise exception 'Approved profile required'; end if;
 if exists(select 1 from delivery_assignments where partner_id=p.id and ended_at is null) then raise exception 'Finish active deliveries before changing partner configuration'; end if;
 update delivery_partner_profiles set partner_type=p_data->>'partner_type',max_active_orders=(p_data->>'max_active_orders')::integer,
 capacity_kg=(p_data->>'capacity_kg')::numeric,capacity_litres=(p_data->>'capacity_litres')::numeric,
 employee_id=nullif(p_data->>'employee_id',''),employment_active=(p_data->>'employment_active')::boolean,
 shift_start=(p_data->>'shift_start')::timestamptz,shift_end=(p_data->>'shift_end')::timestamptz,updated_at=now() where id=p.id;
 insert into delivery_partner_availability(partner_id,is_online) values(p.id,false) on conflict(partner_id) do update set is_online=false;
 insert into delivery_partner_verifications(partner_id,actor_id,previous_status,new_status,reason) values(p.id,p_actor,p.verification_status,p.verification_status,'Operations configuration: '||p_data::text);
end $$;
create or replace function public.set_delivery_partner_operational_state(p_user uuid,p_online boolean,p_lat double precision,p_lon double precision,p_accuracy double precision) returns jsonb language plpgsql security definer set search_path=public as $$
declare p delivery_partner_profiles%rowtype; a delivery_partner_availability%rowtype;
begin
 select * into p from delivery_partner_profiles where user_id=p_user for update;
 if not found or p.verification_status<>'approved' then raise exception 'Approved profile required'; end if;
 if p_online is true and p.partner_type='salaried' and not coalesce(p.employment_active and p.shift_start<=now() and p.shift_end>now(),false) then raise exception 'An active shift is required to go online'; end if;
 if (p_lat is null)<>(p_lon is null) or (p_lat is not null and (p_lat not between -90 and 90 or p_lon not between -180 and 180 or p_accuracy is null or p_accuracy<0)) then raise exception 'Invalid location'; end if;
 insert into delivery_partner_availability(partner_id) values(p.id) on conflict do nothing;
 select * into a from delivery_partner_availability where partner_id=p.id for update;
 if p_lat is not null and not a.is_online then raise exception 'Go online before sharing location'; end if;
 update delivery_partner_availability set is_online=coalesce(p_online,is_online),
 latitude=case when p_online is false then null when p_lat is not null then p_lat else latitude end,
 longitude=case when p_online is false then null when p_lon is not null then p_lon else longitude end,
 accuracy_m=case when p_online is false then null when p_lat is not null then p_accuracy else accuracy_m end,
 location_recorded_at=case when p_online is false then null when p_lat is not null then now() else location_recorded_at end,updated_at=now() where partner_id=p.id returning * into a;
 return to_jsonb(a);
end $$;
create function public.delivery_offers(p_user uuid) returns jsonb language sql stable security definer set search_path=public as $$
 select coalesce(jsonb_agg(x),'[]') from (
 select t.id,t.pickup_address,t.service_area,t.package_description,t.weight_kg,t.volume_litres,t.urgency,t.independent_deadline,c.distance_km,
 delivery_distance_km(t.pickup_lat,t.pickup_lon,t.destination_lat,t.destination_lon) as route_km
 from delivery_tasks t cross join lateral delivery_candidates(t.id,'independent') c
 where c.user_id=p_user and t.status='independent_allocation' and t.independent_deadline>now()
 and not exists(select 1 from delivery_allocation_attempts a where a.task_id=t.id and a.partner_id=c.partner_id and a.status='rejected')
 order by t.independent_deadline limit 50) x
$$;

-- Every function with actor parameters is service-only. The HTTP layer supplies the verified identity and checks admin ownership.
do $$ declare f record; begin for f in select p.oid::regprocedure as signature from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and (p.proname like 'delivery_%' or p.proname='process_delivery_jobs') loop
 execute format('revoke all on function %s from public,anon,authenticated',f.signature);
 execute format('grant execute on function %s to service_role',f.signature);
 end loop; end $$;
commit;

-- ============================================================================
-- Source: migrations/035_business_access.sql
-- ============================================================================
-- Review against the live catalog and restore-tested backup before production use.
-- Keep BUSINESS_ACCESS_ENABLED=false until migration, admin allowlist and tests pass.
begin;
create table public.business_access_admins (
 email text primary key check (email=lower(btrim(email)))
);
revoke all on public.business_access_admins from public,anon,authenticated,service_role;
grant select,insert,delete on public.business_access_admins to service_role;
alter table public.business_access_admins enable row level security;

alter table public.businesses alter column owner_id drop not null;
alter table public.businesses add column created_by uuid references public.profiles(id) on delete set null;
alter table public.businesses add column ownership_review_required boolean not null default true;
-- Never guess historical creators or intended owners. Preserve all current links.
create table public.business_members (
 id uuid primary key default gen_random_uuid(),
 business_id uuid not null references public.businesses(id) on delete cascade,
 user_id uuid not null references public.profiles(id) on delete cascade,
 role text not null check(role in ('owner','manager')),
 status text not null default 'active' check(status in ('active','inactive')),
 assigned_by uuid references public.profiles(id) on delete set null,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 unique(business_id,user_id)
);
create unique index business_one_active_owner on public.business_members(business_id) where role='owner' and status='active';
create index business_member_user on public.business_members(user_id,status,business_id);
insert into public.business_members(business_id,user_id,role)
 select id,owner_id,'owner' from public.businesses where owner_id is not null;
-- Per-creator request keys make retried wizard submissions safe after a lost response.
create table public.business_creation_requests (
 actor_user_id uuid not null, request_id uuid not null, payload_hash text not null,
 business_id uuid, created_at timestamptz not null default now(),
 primary key(actor_user_id,request_id)
);
alter table public.business_creation_requests enable row level security;
revoke all on public.business_creation_requests from public,anon,authenticated,service_role;
grant select,insert,update on public.business_creation_requests to authenticated;

create table public.business_user_lookup_rate (
 actor_user_id uuid not null, window_start timestamptz not null, attempts integer not null,
 primary key(actor_user_id,window_start)
);
alter table public.business_user_lookup_rate enable row level security;
revoke all on public.business_user_lookup_rate from public,anon,authenticated,service_role;

create table public.business_invitations (
 id uuid primary key default gen_random_uuid(),
 business_id uuid not null references public.businesses(id) on delete cascade,
 invited_email text not null check(invited_email=lower(btrim(invited_email))),
 invited_by uuid references public.profiles(id) on delete set null,
 token_hash text not null unique check(token_hash ~ '^[a-f0-9]{64}$'),
 status text not null default 'pending' check(status in ('pending','accepted','revoked','expired')),
 expires_at timestamptz not null, accepted_at timestamptz,
 delivery_status text not null default 'pending' check(delivery_status in ('pending','sent','failed')),
 created_at timestamptz not null default now()
);
create unique index business_pending_invitation on public.business_invitations(business_id,invited_email) where status='pending';
create table public.business_access_logs (
 id uuid primary key default gen_random_uuid(), business_id uuid not null,
 actor_user_id uuid, target_user_id uuid, action text not null,
 details jsonb not null default '{}', created_at timestamptz not null default now()
);
create index business_access_history on public.business_access_logs(business_id,created_at desc,id);
-- Keep business content when an account is deleted; require explicit reassignment first.
do $$ declare c record; begin
 for c in select conname from pg_constraint where conrelid='public.businesses'::regclass and contype='f'
 and conkey=array[(select attnum from pg_attribute where attrelid='public.businesses'::regclass and attname='owner_id')]::smallint[] loop
 execute format('alter table public.businesses drop constraint %I',c.conname);
 end loop;
end $$;
alter table public.businesses add constraint businesses_primary_owner_fk foreign key(owner_id) references public.profiles(id) on delete restrict;

create function public.business_actor() returns uuid language sql stable security definer set search_path='' as $$
 select u.id from auth.users u join public.auth_sessions s on s.user_id=u.id
 where u.id=auth.uid() and s.id=nullif(auth.jwt()->>'session_id','')::uuid
 and s.revoked_at is null and s.expires_at>now()
 and (u.banned_until is null or u.banned_until<=now())
$$;
create function public.business_is_admin() returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from auth.users u join public.business_access_admins a on a.email=lower(u.email)
 where u.id=public.business_actor() and u.email_confirmed_at is not null)
$$;
create function public.business_role(p_business uuid) returns text language sql stable security definer set search_path='' as $$
 select m.role from public.business_members m where m.business_id=p_business and m.user_id=public.business_actor() and m.status='active'
$$;
create function public.business_can_manage(p_business uuid) returns boolean language sql stable security definer set search_path='' as $$
 select public.business_is_admin() or public.business_role(p_business) is not null
$$;
create function public.business_can_access_team(p_business uuid) returns boolean language sql stable security definer set search_path='' as $$
 select public.business_is_admin() or coalesce(public.business_role(p_business)='owner',false)
$$;

-- Verify owner eligibility at the database boundary as well as in the API.
create function public.business_assignable_account(p_user uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select (public.business_is_admin() or p_user=public.business_actor()) and exists (
  select 1 from auth.users u join public.profiles p on p.id=u.id
  where u.id=p_user and u.email_confirmed_at is not null and (u.banned_until is null or u.banned_until<=now())
 )
$$;
revoke all on function public.business_assignable_account(uuid) from public,anon,authenticated;
grant execute on function public.business_assignable_account(uuid) to authenticated;


create policy business_creation_requests_self on public.business_creation_requests for all to authenticated
 using(actor_user_id=public.business_actor()) with check(actor_user_id=public.business_actor());

-- All ownership writes synchronize the single owner membership in the same transaction.
create function public.business_sync_owner() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if TG_OP='UPDATE' and new.owner_id is not distinct from old.owner_id then return new; end if;
 update public.business_members set status='inactive',updated_at=now()
 where business_id=new.id and role='owner' and status='active';
 if new.owner_id is not null then
 insert into public.business_members(business_id,user_id,role,status,assigned_by)
 values(new.id,new.owner_id,'owner','active',public.business_actor())
 on conflict(business_id,user_id) do update set role='owner',status='active',assigned_by=excluded.assigned_by,updated_at=now();
 end if;
 if TG_OP='INSERT' then
 insert into public.business_access_logs(business_id,actor_user_id,target_user_id,action)
 values(new.id,public.business_actor(),new.owner_id,case when new.owner_id is null then 'create_unassigned' else 'create_owner' end);
 end if;
 return new;
end $$;
create trigger business_sync_owner after insert or update of owner_id on public.businesses for each row execute function public.business_sync_owner();
create function public.business_member_invariant() returns trigger language plpgsql security definer set search_path='' as $$
declare bid uuid; oid uuid; owners integer; matching integer;
begin
 bid:=coalesce(new.business_id,old.business_id);
 select owner_id into oid from public.businesses where id=bid;
 if not found then return null; end if;
 select count(*),count(*) filter(where user_id=oid) into owners,matching from public.business_members where business_id=bid and role='owner' and status='active';
 if (oid is null and owners<>0) or (oid is not null and (owners<>1 or matching<>1)) then
 raise exception 'Owner membership invariant violated' using errcode='23514'; end if;
 return null;
end $$;
create constraint trigger business_member_invariant after insert or update or delete on public.business_members
 deferrable initially deferred for each row execute function public.business_member_invariant();

-- Block arbitrary ownership/creator/package edits, including direct PostgREST requests.
create function public.business_protect_fields() returns trigger language plpgsql set search_path='' as $$
begin
 if current_user in ('authenticated','anon') then
 if public.business_actor() is null then raise exception 'Session required' using errcode='42501'; end if;
 if TG_OP='INSERT' then
 if not public.business_is_admin() and new.owner_id is distinct from public.business_actor() then raise exception 'Invalid owner' using errcode='42501'; end if;
 if new.owner_id is not null and not public.business_assignable_account(new.owner_id) then raise exception 'Select an active verified owner' using errcode='22023'; end if;
 new.created_by:=public.business_actor(); new.ownership_review_required:=false;
 if not public.business_is_admin() and (new.is_verified or new.plan_id<>'basic') then raise exception 'Protected business fields' using errcode='42501'; end if;
 elsif not public.business_can_manage(old.id) then
 raise exception 'Business access denied' using errcode='42501';
 elsif new.id is distinct from old.id or new.created_at is distinct from old.created_at or new.profile_views is distinct from old.profile_views
 or coalesce(new.details->'stats','{}'::jsonb) is distinct from coalesce(old.details->'stats','{}'::jsonb)
 or new.owner_id is distinct from old.owner_id or new.created_by is distinct from old.created_by
 or new.ownership_review_required is distinct from old.ownership_review_required
 or (not public.business_is_admin() and (new.plan_id is distinct from old.plan_id or new.is_verified is distinct from old.is_verified)) then
 raise exception 'Use the authorized access operation' using errcode='42501';
 end if;
 end if;
 return new;
end $$;
create trigger business_protect_fields before insert or update on public.businesses for each row execute function public.business_protect_fields();
create function public.business_protect_delete() returns trigger language plpgsql set search_path='' as $$
begin
 if current_user in ('authenticated','anon') and not public.business_can_access_team(old.id) then
  raise exception 'Business access denied' using errcode='42501';
 end if;
 return old;
end $$;
revoke all on function public.business_protect_delete() from public,anon,authenticated;
create trigger business_protect_delete before delete on public.businesses for each row execute function public.business_protect_delete();

create function public.business_change_access(p_business uuid,p_action text,p_target uuid,p_expected_owner uuid,
 p_previous_owner text,p_pending_invitations text) returns void language plpgsql security definer set search_path='' as $$
declare b public.businesses; actor uuid:=public.business_actor();
begin
 select * into b from public.businesses where id=p_business for update;
 if not found or actor is null or not public.business_can_access_team(p_business) then raise exception 'Access denied' using errcode='42501'; end if;
 if p_action not in ('assign_owner','transfer_owner','add_manager','remove_manager') then raise exception 'Invalid action' using errcode='22023'; end if;
 if p_action in ('assign_owner','add_manager') and not public.business_is_admin() then raise exception 'Administrator required' using errcode='42501'; end if;
 if p_action<>'remove_manager' and not exists(select 1 from auth.users u join public.profiles p on p.id=u.id where u.id=p_target and u.email_confirmed_at is not null and (u.banned_until is null or u.banned_until<=now())) then
 raise exception 'Select an active verified account' using errcode='22023'; end if;
 if p_action in ('assign_owner','transfer_owner') then
 if b.owner_id is distinct from p_expected_owner or (p_action='assign_owner' and b.owner_id is not null) or (p_action='transfer_owner' and b.owner_id is null) or b.owner_id=p_target then
 raise exception 'Ownership changed; reload before confirming' using errcode='40001'; end if;
 if p_previous_owner is null or p_previous_owner not in ('remove','manager') or p_pending_invitations is null or p_pending_invitations not in ('revoke','keep') then raise exception 'Choose transfer outcomes' using errcode='22023'; end if;
 update public.businesses set owner_id=p_target,ownership_review_required=false,updated_at=now() where id=p_business;
 if b.owner_id is not null and p_previous_owner='manager' then
 update public.business_members set role='manager',status='active',assigned_by=actor,updated_at=now() where business_id=p_business and user_id=b.owner_id;
 end if;
 if p_pending_invitations='revoke' then
  with revoked as (update public.business_invitations set status='revoked' where business_id=p_business and status='pending' returning id)
  insert into public.business_access_logs(business_id,actor_user_id,action,details)
  select p_business,actor,'revoke_invitation',jsonb_build_object('invitation_id',id,'reason','ownership_transfer') from revoked;
 end if;
 -- An owner must never later accept a pending manager invitation for this business.
 with revoked as (update public.business_invitations set status='revoked' where business_id=p_business and status='pending' and invited_email=(select lower(email) from auth.users where id=p_target) returning id)
 insert into public.business_access_logs(business_id,actor_user_id,target_user_id,action,details)
 select p_business,actor,p_target,'revoke_invitation',jsonb_build_object('invitation_id',id,'reason','owner_assigned') from revoked;
 elsif p_action='add_manager' then
 if b.owner_id=p_target then raise exception 'This account is already the Owner' using errcode='22023'; end if;
 insert into public.business_members(business_id,user_id,role,status,assigned_by) values(p_business,p_target,'manager','active',actor)
 on conflict(business_id,user_id) do update set role='manager',status='active',assigned_by=actor,updated_at=now();
 with revoked as (update public.business_invitations set status='revoked' where business_id=p_business and status='pending' and invited_email=(select lower(email) from auth.users where id=p_target) returning id)
 insert into public.business_access_logs(business_id,actor_user_id,target_user_id,action,details)
 select p_business,actor,p_target,'revoke_invitation',jsonb_build_object('invitation_id',id,'reason','manager_assigned') from revoked;
 else
 update public.business_members set status='inactive',updated_at=now() where business_id=p_business and user_id=p_target and role='manager' and status='active';
 if not found then raise exception 'Active Manager not found' using errcode='22023'; end if;
 end if;
 insert into public.business_access_logs(business_id,actor_user_id,target_user_id,action,details)
 values(p_business,actor,p_target,p_action,
  case when p_action in ('assign_owner','transfer_owner') then
   jsonb_build_object('previous_owner',b.owner_id,'new_owner',p_target,'previous_owner_access',p_previous_owner,'pending_invitations',p_pending_invitations)
  else '{}'::jsonb end);
end $$;

create function public.business_find_user(p_business uuid,p_email text) returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare actor uuid:=public.business_actor(); attempts integer;
begin
 if actor is null or (not public.business_is_admin() and (p_business is null or not public.business_can_access_team(p_business))) then raise exception 'Access denied' using errcode='42501'; end if;
 if p_email is null or length(p_email)>254 or p_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then raise exception 'Invalid email' using errcode='22023'; end if;
 delete from public.business_user_lookup_rate where actor_user_id=actor and window_start<now()-interval '1 day';
 insert into public.business_user_lookup_rate(actor_user_id,window_start,attempts) values(actor,date_trunc('minute',now()),1)
 on conflict(actor_user_id,window_start) do update set attempts=business_user_lookup_rate.attempts+1 returning business_user_lookup_rate.attempts into attempts;
 if attempts>30 then raise exception 'Too many account searches. Try again shortly.' using errcode='P4290'; end if;
 return (select jsonb_build_object('id',u.id,'name',p.full_name,'email',u.email,'verified',u.email_confirmed_at is not null)
 from auth.users u join public.profiles p on p.id=u.id where lower(u.email)=lower(btrim(p_email)) and u.email_confirmed_at is not null and (u.banned_until is null or u.banned_until<=now()) limit 1);
end $$;
create function public.business_access_details(p_business uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not public.business_can_access_team(p_business) then raise exception 'Access denied' using errcode='42501'; end if;
 return jsonb_build_object(
 'business',(select jsonb_build_object('id',b.id,'name',b.business_name,'status',b.status,'created_by',b.created_by,
 'created_by_name',coalesce(nullif(cp.full_name,''),cu.email,b.created_by::text),'created_at',b.created_at,'review_required',b.ownership_review_required)
 from public.businesses b left join public.profiles cp on cp.id=b.created_by left join auth.users cu on cu.id=b.created_by where b.id=p_business),
 'owner',(select jsonb_build_object('id',u.id,'name',p.full_name,'email',u.email) from public.businesses b join auth.users u on u.id=b.owner_id join public.profiles p on p.id=u.id where b.id=p_business),
 'managers',coalesce((select jsonb_agg(jsonb_build_object('id',m.user_id,'name',p.full_name,'email',u.email,'status',m.status)) from public.business_members m join auth.users u on u.id=m.user_id join public.profiles p on p.id=u.id where m.business_id=p_business and m.role='manager' and m.status='active'),'[]'),
 'invitations',coalesce((select jsonb_agg(jsonb_build_object('id',id,'email',invited_email,'expires_at',expires_at,'status',case when expires_at<=now() then 'expired' else status end,'delivery_status',delivery_status)) from public.business_invitations where business_id=p_business and status='pending'),'[]'),
 'history',coalesce((select jsonb_agg(to_jsonb(h)) from (
 select l.id,l.actor_user_id,l.target_user_id,l.action,l.details,l.created_at,
 coalesce(nullif(ap.full_name,''),au.email,l.actor_user_id::text) as actor_name,
 coalesce(nullif(op.full_name,''),ou.email,l.details->>'previous_owner') as previous_owner_name,
 coalesce(nullif(np.full_name,''),nu.email,l.details->>'new_owner') as new_owner_name
 from public.business_access_logs l
 left join public.profiles ap on ap.id=l.actor_user_id left join auth.users au on au.id=l.actor_user_id
 left join public.profiles op on op.id=nullif(l.details->>'previous_owner','')::uuid left join auth.users ou on ou.id=op.id
 left join public.profiles np on np.id=nullif(l.details->>'new_owner','')::uuid left join auth.users nu on nu.id=np.id
 where l.business_id=p_business order by l.created_at desc,l.id desc limit 100) h),'[]'));
end $$;

create function public.business_invite(p_business uuid,p_email text,p_hash text,p_days integer) returns uuid language plpgsql security definer set search_path='' as $$
declare invitation uuid; actor uuid:=public.business_actor();
begin
 perform 1 from public.businesses where id=p_business for update;
 if not found or not public.business_can_access_team(p_business) then raise exception 'Access denied' using errcode='42501'; end if;
 p_email:=lower(btrim(p_email));
 if p_email is null or length(p_email)>254 or p_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' or p_days is null or p_days<1 or p_days>30 then raise exception 'Invalid invitation' using errcode='22023'; end if;
 if exists(select 1 from public.business_members m join auth.users u on u.id=m.user_id where m.business_id=p_business and m.status='active' and lower(u.email)=p_email) then raise exception 'Account already has access' using errcode='23505'; end if;
 with expired as (update public.business_invitations set status='expired' where business_id=p_business and status='pending' and expires_at<=now() returning id)
 insert into public.business_access_logs(business_id,actor_user_id,action,details)
 select p_business,actor,'expire_invitation',jsonb_build_object('invitation_id',id) from expired;
 insert into public.business_invitations(business_id,invited_email,invited_by,token_hash,expires_at) values(p_business,p_email,actor,p_hash,now()+make_interval(days=>p_days)) returning id into invitation;
 insert into public.business_access_logs(business_id,actor_user_id,action,details) values(p_business,actor,'invite',jsonb_build_object('invitation_id',invitation));
 return invitation;
end $$;
create function public.business_revoke_invitation(p_business uuid,p_invitation uuid) returns void language plpgsql security definer set search_path='' as $$
begin
 perform 1 from public.businesses where id=p_business for update;
 if not public.business_can_access_team(p_business) then raise exception 'Access denied' using errcode='42501'; end if;
 update public.business_invitations set status='revoked' where id=p_invitation and business_id=p_business and status='pending';
 if not found then raise exception 'Pending invitation not found' using errcode='22023'; end if;
 insert into public.business_access_logs(business_id,actor_user_id,action,details) values(p_business,public.business_actor(),'revoke_invitation',jsonb_build_object('invitation_id',p_invitation));
end $$;
create function public.business_accept_invitation(p_hash text) returns uuid language plpgsql security definer set search_path='' as $$
declare inv public.business_invitations; bid uuid; actor uuid:=public.business_actor(); verified_email text;
begin
 select business_id into bid from public.business_invitations where token_hash=p_hash;
 perform 1 from public.businesses where id=bid for update;
 select * into inv from public.business_invitations where token_hash=p_hash for update;
 select lower(email) into verified_email from auth.users where id=actor and email_confirmed_at is not null;
 if actor is null or verified_email is null or inv.id is null or inv.status<>'pending' or inv.expires_at<=now() or inv.invited_email<>verified_email then raise exception 'Invitation is invalid, expired or belongs to another account' using errcode='42501'; end if;
 if exists(select 1 from public.business_members where business_id=bid and user_id=actor and status='active') then raise exception 'Account already has access' using errcode='23505'; end if;
 insert into public.business_members(business_id,user_id,role,status,assigned_by) values(bid,actor,'manager','active',inv.invited_by)
 on conflict(business_id,user_id) do update set role='manager',status='active',assigned_by=excluded.assigned_by,updated_at=now();
 update public.business_invitations set status='accepted',accepted_at=now() where id=inv.id;
 insert into public.business_access_logs(business_id,actor_user_id,target_user_id,action,details) values(bid,actor,actor,'accept_invitation',jsonb_build_object('invitation_id',inv.id));
 return bid;
end $$;

alter table public.business_members enable row level security;
alter table public.business_invitations enable row level security;
alter table public.business_access_logs enable row level security;
revoke all on public.business_members,public.business_invitations,public.business_access_logs from public,anon,authenticated,service_role;
grant select on public.business_members,public.business_access_logs to authenticated;
-- Tokens and invitee emails are only returned through owner-scoped RPC projections.
create policy business_members_private on public.business_members for select to authenticated using (user_id=public.business_actor() or public.business_can_access_team(business_id));
create policy business_history_private on public.business_access_logs for select to authenticated using (public.business_can_access_team(business_id));
grant select,update on public.business_invitations to service_role;
grant select on public.business_members,public.business_access_logs to service_role;

-- Content writes use caller JWTs, never a service-role fallback when enabled.
create policy business_member_read on public.businesses for select to authenticated using(owner_id=public.business_actor() or public.business_can_manage(id));
create policy business_member_update on public.businesses for update to authenticated using(public.business_can_manage(id)) with check(public.business_can_manage(id));
create policy business_account_create on public.businesses for insert to authenticated with check(public.business_actor() is not null and (owner_id=public.business_actor() or public.business_is_admin()));
create policy business_delete_owner on public.businesses for delete to authenticated using(public.business_can_access_team(id));
-- Restrictive gates constrain older permissive owner policies, including expired sessions.
create policy business_write_update_gate on public.businesses as restrictive for update to authenticated using(public.business_can_manage(id)) with check(public.business_can_manage(id));
create policy business_write_insert_gate on public.businesses as restrictive for insert to authenticated with check(public.business_actor() is not null and (owner_id=public.business_actor() or public.business_is_admin()));
create policy business_write_delete_gate on public.businesses as restrictive for delete to authenticated using(public.business_can_access_team(id));

do $$ declare t text; begin
 foreach t in array array['products','services','events','offers','gallery_photos','business_people','business_section_visibility'] loop
 execute format('create policy business_member_content on public.%I for all to authenticated using(public.business_can_manage(business_id)) with check(public.business_can_manage(business_id))',t);
 execute format('create policy business_content_insert_gate on public.%I as restrictive for insert to authenticated with check(public.business_can_manage(business_id))',t);
 execute format('create policy business_content_update_gate on public.%I as restrictive for update to authenticated using(public.business_can_manage(business_id)) with check(public.business_can_manage(business_id))',t);
 execute format('create policy business_content_delete_gate on public.%I as restrictive for delete to authenticated using(public.business_can_manage(business_id))',t);
 execute format('grant select,insert,update,delete on public.%I to authenticated',t);
 end loop;
end $$;
grant select,insert,update,delete on public.businesses to authenticated;
-- Extend the existing restrictive publication rules without changing public behavior.
do $$ declare t text; p record; begin
 foreach t in array array['products','services'] loop
 for p in select policyname,qual from pg_policies where schemaname='public' and tablename=t and permissive='RESTRICTIVE' and cmd='SELECT' loop
 execute format('alter policy %I on public.%I using ((%s) or public.business_can_manage(business_id))',p.policyname,t,p.qual);
 end loop; end loop;
end $$;

-- Explicit grants; PostgreSQL grants PUBLIC execution by default.
do $$ declare f record; begin
 for f in select p.oid::regprocedure as signature,p.proname from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where n.nspname='public' and p.proname in ('business_actor','business_is_admin','business_role','business_can_manage','business_can_access_team','business_sync_owner','business_member_invariant','business_protect_fields','business_change_access','business_find_user','business_access_details','business_invite','business_revoke_invitation','business_accept_invitation') loop
 execute format('revoke all on function %s from public,anon,authenticated',f.signature);
 if f.proname not in ('business_sync_owner','business_member_invariant','business_protect_fields') then execute format('grant execute on function %s to authenticated',f.signature); end if;
 -- Anonymous public content policies invoke this helper; it returns false without a session.
 if f.proname='business_can_manage' then execute format('grant execute on function %s to anon',f.signature); end if;
 end loop;
end $$;
-- Atomic business, owner membership, creation audit and optional leadership rows.
-- The invoker's RLS and all existing triggers still apply.
create function public.business_create_with_people(p_business jsonb,p_people jsonb default '[]'::jsonb,p_request_id uuid default null)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare columns_sql text; values_sql text; result jsonb; person jsonb; owner_id uuid; actor uuid:=public.business_actor(); fingerprint text; previous_hash text; previous_business uuid;
 allowed constant text[]:=array['owner_id','business_name','business_name_mr','slug','global_category_id',
 'category','category_mr','owner_name_mr','designation_mr','tagline_mr','description','description_mr',
 'logo_url','logo_public_id','profile_image_url','profile_image_public_id','phone','whatsapp_number',
 'address','social_links','status','is_verified','plan_id','is_published','details'];
 allowed_person constant text[]:=array['full_name_en','full_name_mr','designation_en','designation_mr','description_en','description_mr',
 'profile_image_url','profile_image_public_id','display_order','is_primary','is_active'];
begin
 if public.business_actor() is null then raise exception 'Session required' using errcode='42501'; end if;
 if jsonb_typeof(p_business) is distinct from 'object' or jsonb_typeof(p_people) is distinct from 'array' or jsonb_array_length(p_people)>50 then
  raise exception 'Invalid business creation payload' using errcode='22023'; end if;
 if exists(select 1 from jsonb_object_keys(p_business) key where not key=any(allowed)) then
  raise exception 'Invalid business fields' using errcode='22023'; end if;
 if not p_business ?& array['business_name','slug','owner_id'] then raise exception 'Business name, slug, and owner are required' using errcode='22023'; end if;
 owner_id:=nullif(p_business->>'owner_id','')::uuid;
 if owner_id is not null and not public.business_assignable_account(owner_id) then raise exception 'Select an active verified owner' using errcode='22023'; end if;
 if p_request_id is not null then
  fingerprint:=md5(((p_business-'slug') #- '{details,slug}' #- '{details,id}' #- '{details,createdAt}')::text || p_people::text);
  perform pg_advisory_xact_lock(hashtextextended(actor::text || p_request_id::text,0));
  select payload_hash,business_id into previous_hash,previous_business from public.business_creation_requests
   where actor_user_id=actor and request_id=p_request_id for update;
  if found then
   if previous_hash<>fingerprint then raise exception 'Creation request was already used for different details' using errcode='40001'; end if;
   if previous_business is not null then
    select to_jsonb(b) into result from public.businesses b where b.id=previous_business and b.created_by=actor and public.business_can_manage(b.id);
    if result is null then raise exception 'The previous creation is unavailable' using errcode='40001'; end if;
    return result;
   end if;
  else
   insert into public.business_creation_requests(actor_user_id,request_id,payload_hash) values(actor,p_request_id,fingerprint);
  end if;
 end if;
 if exists(select 1 from jsonb_array_elements(p_people) item where jsonb_typeof(item) is distinct from 'object') then
  raise exception 'Invalid business person' using errcode='22023'; end if;
 for person in select * from jsonb_array_elements(p_people) loop
  if exists(select 1 from jsonb_object_keys(person) key where not key=any(allowed_person)) or nullif(btrim(person->>'full_name_en'),'') is null then
   raise exception 'Invalid business person' using errcode='22023'; end if;
 end loop;
 if (select count(*) from jsonb_array_elements(p_people) item where coalesce((item->>'is_active')::boolean,true))>0
 and (select count(*) from jsonb_array_elements(p_people) item where coalesce((item->>'is_active')::boolean,true) and coalesce((item->>'is_primary')::boolean,false))<>1 then
  raise exception 'Exactly one active primary person is required' using errcode='22023'; end if;
 select string_agg(format('%I',key),',' order by key),string_agg(format('r.%I',key),',' order by key)
 into columns_sql,values_sql from jsonb_object_keys(p_business) key;
 execute format('insert into public.businesses (%s) select %s from jsonb_populate_record(null::public.businesses,$1) r returning to_jsonb(businesses)',columns_sql,values_sql)
 into result using p_business;
 insert into public.business_people (business_id,full_name_en,full_name_mr,designation_en,designation_mr,description_en,description_mr,
 profile_image_url,profile_image_public_id,display_order,is_primary,is_active)
 select (result->>'id')::uuid,p.full_name_en,p.full_name_mr,p.designation_en,p.designation_mr,p.description_en,p.description_mr,
 p.profile_image_url,p.profile_image_public_id,coalesce(p.display_order,0),coalesce(p.is_primary,false),coalesce(p.is_active,true)
 from jsonb_to_recordset(p_people) as p(full_name_en text,full_name_mr text,designation_en text,designation_mr text,description_en text,description_mr text,
 profile_image_url text,profile_image_public_id text,display_order integer,is_primary boolean,is_active boolean);
 if p_request_id is not null then update public.business_creation_requests set business_id=(result->>'id')::uuid where actor_user_id=actor and request_id=p_request_id; end if;
 return result;
end $$;
revoke all on function public.business_create_with_people(jsonb,jsonb,uuid) from public,anon,authenticated;
grant execute on function public.business_create_with_people(jsonb,jsonb,uuid) to authenticated;

-- Serialize member content writes with transfer/removal. Re-check after the lock.
create function public.business_lock_content() returns trigger language plpgsql security definer set search_path='' as $$
declare bid uuid;
begin
 if current_setting('role',true) not in ('authenticated','anon') then return coalesce(new,old); end if;
 bid:=case when TG_OP='DELETE' then old.business_id else new.business_id end;
 if TG_OP='UPDATE' and old.business_id is distinct from new.business_id then raise exception 'Content cannot change business' using errcode='42501'; end if;
 perform 1 from public.businesses where id=bid for update;
 if not found or not public.business_can_manage(bid) then raise exception 'Business access denied' using errcode='42501'; end if;
 return coalesce(new,old);
end $$;
revoke all on function public.business_lock_content() from public,anon,authenticated;
do $$ declare t text; begin
 foreach t in array array['products','services','events','offers','gallery_photos','business_people','business_section_visibility'] loop
 execute format('create trigger business_lock_content before insert or update or delete on public.%I for each row execute function public.business_lock_content()',t);
 end loop;
end $$;
create policy business_private_read_gate on public.businesses as restrictive for select to authenticated
 using(is_published or owner_id=public.business_actor() or public.business_can_manage(id));
-- Existing permissive owner policies must not leak inactive content to revoked sessions.
do $$ declare t text; begin
 foreach t in array array['products','services','events','offers','gallery_photos','business_people','business_section_visibility'] loop
 execute format('create policy business_private_content_gate on public.%I as restrictive for select to authenticated using(public.business_can_manage(business_id) or (exists(select 1 from public.businesses b where b.id=business_id and b.is_published) and coalesce((to_jsonb(%I)->>''is_active'')::boolean,true) and coalesce((to_jsonb(%I)->>''is_published'')::boolean,true) and to_jsonb(%I)->>''deleted_at'' is null))',t,t,t,t);
 end loop;
end $$;
create function public.business_my_invitations() returns jsonb language sql stable security definer set search_path='' as $$
 select coalesce(jsonb_agg(jsonb_build_object('id',i.id,'businessName',b.business_name,'expiresAt',i.expires_at)),'[]')
 from public.business_invitations i join public.businesses b on b.id=i.business_id
 join auth.users u on lower(u.email)=i.invited_email
 where u.id=public.business_actor() and u.email_confirmed_at is not null and i.status='pending' and i.expires_at>now()
$$;
revoke all on function public.business_my_invitations() from public,anon,authenticated;
grant execute on function public.business_my_invitations() to authenticated;

do $$ begin
 if to_regprocedure('public.move_category_items(uuid,text,uuid[],uuid)') is not null then
 if (select prosecdef from pg_proc where oid='public.move_category_items(uuid,text,uuid[],uuid)'::regprocedure) then raise exception 'Review move_category_items security before migration'; end if;
 grant execute on function public.move_category_items(uuid,text,uuid[],uuid) to authenticated;
 end if;
end $$;
commit;

-- ============================================================================
-- Source: migrations/036_fulfillment_fleet_and_pickup.sql
-- ============================================================================
-- ============================================================================
-- Source: migrations/036_pending_order_editing.sql
-- ============================================================================
-- Pending order edits preserve both existing order identifiers and do not create revision history.
begin;
alter table public.marketplace_store_orders
  add column if not exists edit_token uuid not null default gen_random_uuid(),
  add column if not exists has_pending_edits boolean not null default false;

create function public.edit_pending_store_order(p_order uuid, p_customer uuid, p_expected_token uuid, p_items jsonb)
returns jsonb language plpgsql security definer set search_path=public as $$
declare target marketplace_store_orders%rowtype; row_item jsonb; product_row products%rowtype;
        product_ids uuid[] := array[]::uuid[]; quantity_value integer; total numeric(12,2) := 0;
        incomplete boolean := false; new_token uuid;
begin
  if p_customer is null or p_expected_token is null or jsonb_typeof(p_items) is distinct from 'array'
     or jsonb_array_length(p_items) not between 1 and 100 then
    raise exception 'Invalid items';
  end if;
  select so.* into target from marketplace_store_orders so
    join marketplace_orders o on o.id=so.order_id
    where so.id=p_order and o.customer_id=p_customer for update of so;
  if not found then raise exception 'Order unavailable'; end if;
  if target.status <> 'PENDING' or target.edit_token <> p_expected_token then
    raise exception 'Order changed';
  end if;
  if not exists(select 1 from businesses where id=target.business_id and is_published=true) then
    raise exception 'Store unavailable';
  end if;
  -- Lock product rows in a stable order so prices cannot change while rebuilding the snapshot.
  perform p.id from products p where p.id in
    (select (value->>'id')::uuid from jsonb_array_elements(p_items)) order by p.id for share;
  for row_item in select value from jsonb_array_elements(p_items) loop
    if jsonb_typeof(row_item) <> 'object' or not (row_item ? 'id') or not (row_item ? 'quantity') then
      raise exception 'Invalid items';
    end if;
    quantity_value := (row_item->>'quantity')::integer;
    if quantity_value not between 1 and 999 or (row_item->>'id')::uuid = any(product_ids) then
      raise exception 'Invalid items';
    end if;
    select * into product_row from products where id=(row_item->>'id')::uuid
      and business_id=target.business_id and is_published=true and is_available is not false;
    if not found or not exists(select 1 from explore_products where id=product_row.id) then
      raise exception 'Product unavailable';
    end if;
    product_ids := array_append(product_ids,product_row.id);
    if product_row.price is null then incomplete := true;
    else total := total + product_row.price * quantity_value; end if;
  end loop;
  delete from marketplace_order_items where store_order_id=target.id;
  insert into marketplace_order_items(store_order_id,product_id,product_name,quantity,unit_price)
    select target.id,p.id,coalesce(nullif(p.name_en,''),p.name), (v.value->>'quantity')::integer,p.price
    from jsonb_array_elements(p_items) v join products p on p.id=(v.value->>'id')::uuid;
  new_token := gen_random_uuid();
  update marketplace_store_orders set subtotal=case when incomplete then null else total end, edit_token=new_token, has_pending_edits=true where id=target.id;
  return jsonb_build_object('id',target.id,'edit_token',new_token,'subtotal',case when incomplete then null else total end);
exception when invalid_text_representation or numeric_value_out_of_range then
  raise exception 'Invalid items';
end $$;
-- Serialize confirmation against edits and require review of an edited order.
create function public.confirm_reviewed_store_order(p_order uuid,p_actor uuid,p_is_admin boolean,p_expected_token uuid)
returns boolean language plpgsql security definer set search_path=public as $$
declare target marketplace_store_orders%rowtype;
begin
 select * into target from marketplace_store_orders where id=p_order for update;
 if not found or (p_is_admin is not true and not exists(select 1 from businesses where id=target.business_id and owner_id=p_actor)) then return false; end if;
 if target.status <> 'PENDING' then return false; end if;
 if (target.has_pending_edits and p_expected_token is null) or (p_expected_token is not null and p_expected_token <> target.edit_token) then
   raise exception 'Order changed';
 end if;
 return manage_store_order(p_order,p_actor,p_is_admin,'accept');
end $$;
revoke all on function public.confirm_reviewed_store_order(uuid,uuid,boolean,uuid) from public,anon,authenticated;
grant execute on function public.confirm_reviewed_store_order(uuid,uuid,boolean,uuid) to service_role;
revoke all on function public.edit_pending_store_order(uuid,uuid,uuid,jsonb) from public,anon,authenticated;
grant execute on function public.edit_pending_store_order(uuid,uuid,uuid,jsonb) to service_role;
commit;

-- ============================================================================
-- Source: migrations/037_closing_price.sql
-- ============================================================================
-- The agreed product price is recorded at seller confirmation, not as payment.
begin;
alter table public.marketplace_store_orders add column if not exists closing_price numeric(12,2);
alter table public.marketplace_store_orders add constraint marketplace_closing_price_valid
  check (closing_price is null or (closing_price > 0 and subtotal is not null and closing_price <= subtotal));
create or replace function public.confirm_reviewed_store_order(p_order uuid,p_actor uuid,p_is_admin boolean,p_expected_token uuid,p_closing_price numeric)
returns boolean language plpgsql security definer set search_path=public as $$
declare target marketplace_store_orders%rowtype;
begin
 select * into target from marketplace_store_orders where id=p_order for update;
 if not found or (p_is_admin is not true and not exists(select 1 from businesses where id=target.business_id and owner_id=p_actor)) then return false; end if;
 if target.status <> 'PENDING' then return false; end if;
 if p_expected_token is null or p_expected_token <> target.edit_token then raise exception 'Order changed'; end if;
 if target.subtotal is null or target.subtotal <= 0 then raise exception 'Product subtotal unavailable'; end if;
 if p_closing_price is null or p_closing_price <= 0 or p_closing_price > target.subtotal or p_closing_price <> round(p_closing_price,2) then raise exception 'Invalid closing price'; end if;
 update marketplace_store_orders set closing_price=p_closing_price where id=target.id;
 return manage_store_order(p_order,p_actor,p_is_admin,'accept');
end $$;
-- Prevent bypassing the required closing price through the previous service-role RPC.
revoke all on function public.confirm_reviewed_store_order(uuid,uuid,boolean,uuid) from public,anon,authenticated,service_role;
revoke all on function public.confirm_reviewed_store_order(uuid,uuid,boolean,uuid,numeric) from public,anon,authenticated;
grant execute on function public.confirm_reviewed_store_order(uuid,uuid,boolean,uuid,numeric) to service_role;
commit;

-- ============================================================================
-- Source: migrations/038_fleet_types.sql
-- ============================================================================
-- Fleet types are retained when referenced; products default to Bike.
begin;
create table public.fleet_types (
 id uuid primary key default gen_random_uuid(), code text not null unique check(code ~ '^[a-z][a-z0-9_]{0,39}$'),
 name text not null check(length(trim(name)) between 1 and 80), sort_rank integer not null check(sort_rank between 1 and 10000),
 active boolean not null default true, created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
insert into public.fleet_types(code,name,sort_rank) values ('scooter','Scooter',10),('bike','Bike',20),('small_tempo','Small Tempo',30),('truck','Truck',40);
alter table public.fleet_types enable row level security;
revoke all on public.fleet_types from public,anon,authenticated;
grant all on public.fleet_types to service_role;
alter table public.products add column fleet_type_id uuid references public.fleet_types(id) on delete restrict;
update public.products set fleet_type_id=(select id from public.fleet_types where code='bike');
alter table public.products alter column fleet_type_id set not null;
create function public.validate_product_fleet() returns trigger language plpgsql set search_path=public as $$
begin
 if new.fleet_type_id is null then select id into new.fleet_type_id from fleet_types where code='bike' and active; end if;
 if (tg_op='INSERT' or new.fleet_type_id is distinct from old.fleet_type_id) and not exists(select 1 from fleet_types where id=new.fleet_type_id and active) then raise exception 'Fleet type unavailable'; end if;
 return new;
end $$;
create trigger product_fleet_valid before insert or update of fleet_type_id on public.products for each row execute function public.validate_product_fleet();
commit;

-- ============================================================================
-- Source: migrations/039_delivery_pricing.sql
-- ============================================================================
-- Pricing is configured explicitly; no charges or delivery areas are invented.
begin;
create table public.delivery_pricing_config (
 id boolean primary key default true check(id), config jsonb not null default '{}'::jsonb,
 updated_by uuid references auth.users(id), updated_at timestamptz not null default now()
);
insert into public.delivery_pricing_config(id) values(true);
create table public.delivery_pricing_config_history (
 id uuid primary key default gen_random_uuid(), actor_id uuid references auth.users(id), old_config jsonb not null, new_config jsonb not null, created_at timestamptz not null default now()
);
alter table public.delivery_pricing_config enable row level security;
alter table public.delivery_pricing_config_history enable row level security;
revoke all on public.delivery_pricing_config,public.delivery_pricing_config_history from public,anon,authenticated;
grant all on public.delivery_pricing_config,public.delivery_pricing_config_history to service_role;
create function public.save_delivery_pricing_config(p_actor uuid,p_config jsonb) returns void language plpgsql security definer set search_path=public as $$
declare old_config jsonb;
begin
 select config into old_config from delivery_pricing_config where id=true for update;
 update delivery_pricing_config set config=p_config,updated_by=p_actor,updated_at=now() where id=true;
 insert into delivery_pricing_config_history(actor_id,old_config,new_config) values(p_actor,old_config,p_config);
end $$;
revoke all on function public.save_delivery_pricing_config(uuid,jsonb) from public,anon,authenticated;
grant execute on function public.save_delivery_pricing_config(uuid,jsonb) to service_role;
commit;

-- ============================================================================
-- Source: migrations/040_pickup_settings.sql
-- ============================================================================
begin;
create table public.pickup_settings (id boolean primary key default true check(id),lead_minutes integer not null default 30 check(lead_minutes between 0 and 10080),updated_by uuid references auth.users(id),updated_at timestamptz not null default now());
insert into public.pickup_settings(id) values(true);
alter table public.pickup_settings enable row level security;
revoke all on public.pickup_settings from public,anon,authenticated;
grant all on public.pickup_settings to service_role;
commit;

-- ============================================================================
-- Source: migrations/041_pickup_orders.sql
-- ============================================================================
begin;
alter table public.marketplace_store_orders
 add column fulfillment_method text check(fulfillment_method in ('pickup','standard_4_6h','standard_24h','urgent')),
 add column pickup_start timestamptz,
 add column pickup_end timestamptz,
 add column pickup_timezone text,
 add column pickup_store_address jsonb,
 add constraint pickup_order_schedule_valid check(fulfillment_method is distinct from 'pickup' or (pickup_start is not null and pickup_end=pickup_start+interval '1 hour' and pickup_timezone is not null and pickup_store_address is not null));
create function public.place_pickup_store_request(p_customer uuid,p_store uuid,p_key uuid,p_name text,p_phone text,p_expected jsonb,p_start timestamptz,p_end timestamptz,p_hours jsonb,p_address jsonb,p_address_text text,p_lead integer)
returns jsonb language plpgsql security definer set search_path=public as $$
declare prior marketplace_store_orders%rowtype; result jsonb; b record; lead integer;
begin
 perform pg_advisory_xact_lock(hashtextextended(p_customer::text || ':' || p_key::text,0));
 select so.* into prior from marketplace_orders o join marketplace_store_orders so on so.order_id=o.id where o.customer_id=p_customer and o.request_key=p_key;
 if found then
  if prior.business_id is distinct from p_store or prior.fulfillment_method is distinct from 'pickup' or prior.pickup_start is distinct from p_start or prior.pickup_end is distinct from p_end then raise exception 'Request key already used'; end if;
  return jsonb_build_object('store_order_id',prior.id,'replayed',true);
 end if;
 select details,is_published into b from businesses where id=p_store for share;
 select lead_minutes into lead from pickup_settings where id=true for share;
 if not found or b.is_published is not true or b.details->'businessHours' is distinct from p_hours or b.details->'address' is distinct from p_address or lead is distinct from p_lead then raise exception 'Pickup availability changed'; end if;
 if p_start is null or p_end is distinct from p_start+interval '1 hour' or p_start<now()+make_interval(mins=>lead) or nullif(trim(p_hours->>'timezone'),'') is null or length(trim(p_address_text)) not between 1 and 500 then raise exception 'Pickup availability changed'; end if;
 result:=place_whatsapp_store_request(p_customer,p_store,p_key,p_name,p_phone,p_address_text,p_expected);
 update marketplace_store_orders set fulfillment_method='pickup',pickup_start=p_start,pickup_end=p_end,pickup_timezone=p_hours->>'timezone',pickup_store_address=p_address where id=(result->>'store_order_id')::uuid;
 return result;
end $$;
create or replace function public.confirm_reviewed_store_order(p_order uuid,p_actor uuid,p_is_admin boolean,p_expected_token uuid,p_closing_price numeric)
returns boolean language plpgsql security definer set search_path=public as $$
declare target marketplace_store_orders%rowtype; confirmed boolean;
begin
 select * into target from marketplace_store_orders where id=p_order for update;
 if not found or (p_is_admin is not true and not exists(select 1 from businesses where id=target.business_id and owner_id=p_actor)) then return false; end if;
 if target.status <> 'PENDING' then return false; end if;
 if p_expected_token is null or p_expected_token <> target.edit_token then raise exception 'Order changed'; end if;
 if target.subtotal is null or target.subtotal <= 0 then raise exception 'Product subtotal unavailable'; end if;
 if p_closing_price is null or p_closing_price <= 0 or p_closing_price > target.subtotal or p_closing_price <> round(p_closing_price,2) then raise exception 'Invalid closing price'; end if;
 update marketplace_store_orders set closing_price=p_closing_price where id=target.id;
 confirmed:=manage_store_order(p_order,p_actor,p_is_admin,'accept');
 if confirmed and target.fulfillment_method='pickup' then
  update marketplace_store_orders set status='PROCESSING' where id=target.id;
  insert into marketplace_order_status_history(store_order_id,previous_status,new_status,changed_by) values(target.id,'ACCEPTED','PROCESSING',p_actor);
 end if;
 return confirmed;
end $$;
revoke all on function public.place_pickup_store_request(uuid,uuid,uuid,text,text,jsonb,timestamptz,timestamptz,jsonb,jsonb,text,integer) from public,anon,authenticated;
grant execute on function public.place_pickup_store_request(uuid,uuid,uuid,text,text,jsonb,timestamptz,timestamptz,jsonb,jsonb,text,integer) to service_role;
commit;

-- ============================================================================
-- Source: migrations/042_pickup_handover.sql
-- ============================================================================
begin;
create table public.pickup_handover_codes (
 store_order_id uuid primary key references public.marketplace_store_orders(id) on delete restrict,
 nonce uuid not null, code_hash text not null check(code_hash ~ '^[0-9a-f]{64}$'), expires_at timestamptz not null,
 failed_attempts integer not null default 0, locked_until timestamptz, consumed_at timestamptz, created_at timestamptz not null default now()
);
alter table public.pickup_handover_codes enable row level security;
revoke all on public.pickup_handover_codes from public,anon,authenticated;
grant all on public.pickup_handover_codes to service_role;
create function public.pickup_mark_ready(p_order uuid,p_actor uuid,p_admin boolean,p_nonce uuid,p_hash text)
returns text language plpgsql security definer set search_path=public as $$
declare target marketplace_store_orders%rowtype; current_code pickup_handover_codes%rowtype;
begin
 select * into target from marketplace_store_orders where id=p_order for update;
 if not found or target.fulfillment_method is distinct from 'pickup' or (p_admin is not true and not exists(select 1 from businesses where id=target.business_id and owner_id=p_actor)) then return 'unavailable'; end if;
 if target.status not in ('PROCESSING','READY_FOR_DISPATCH') then return 'invalid_state'; end if;
 if p_nonce is null or p_hash !~ '^[0-9a-f]{64}$' then return 'invalid_code'; end if;
 select * into current_code from pickup_handover_codes where store_order_id=p_order for update;
 if found and current_code.expires_at>now() and current_code.consumed_at is null then return 'already_ready'; end if;
 insert into pickup_handover_codes(store_order_id,nonce,code_hash,expires_at) values(p_order,p_nonce,p_hash,now()+interval '24 hours')
 on conflict(store_order_id) do update set nonce=excluded.nonce,code_hash=excluded.code_hash,expires_at=excluded.expires_at,failed_attempts=0,locked_until=null,consumed_at=null,created_at=now();
 if target.status='PROCESSING' then
  update marketplace_store_orders set status='READY_FOR_DISPATCH' where id=p_order;
  insert into marketplace_order_status_history(store_order_id,previous_status,new_status,changed_by) values(p_order,'PROCESSING','READY_FOR_DISPATCH',p_actor);
 end if;
 perform delivery_notice(null,o.customer_id,false,'Order '||target.store_order_number||' is ready for pickup. View your pickup code in order history.','pickup-ready:'||p_order||':'||p_nonce) from marketplace_orders o where o.id=target.order_id and o.customer_id is not null;
 return 'ready';
end $$;
create function public.pickup_verify_handover(p_order uuid,p_actor uuid,p_admin boolean,p_hash text)
returns text language plpgsql security definer set search_path=public as $$
declare target marketplace_store_orders%rowtype; code pickup_handover_codes%rowtype;
begin
 select * into target from marketplace_store_orders where id=p_order for update;
 if not found or target.fulfillment_method is distinct from 'pickup' or (p_admin is not true and not exists(select 1 from businesses where id=target.business_id and owner_id=p_actor)) then return 'unavailable'; end if;
 if target.status='DELIVERED' then return 'completed'; end if;
 if target.status<>'READY_FOR_DISPATCH' then return 'invalid_state'; end if;
 select * into code from pickup_handover_codes where store_order_id=p_order for update;
 if not found or code.consumed_at is not null or code.expires_at<=now() then return 'expired'; end if;
 if code.locked_until>now() then return 'locked'; end if;
 if code.locked_until is not null then update pickup_handover_codes set failed_attempts=0,locked_until=null where store_order_id=p_order; code.failed_attempts:=0; end if;
 if p_hash is distinct from code.code_hash then
  update pickup_handover_codes set failed_attempts=code.failed_attempts+1,locked_until=case when code.failed_attempts+1>=5 then now()+interval '15 minutes' else null end where store_order_id=p_order;
  return case when code.failed_attempts+1>=5 then 'locked' else 'invalid_code' end;
 end if;
 update pickup_handover_codes set consumed_at=now(),code_hash=repeat('0',64) where store_order_id=p_order;
 update marketplace_store_orders set status='DELIVERED' where id=p_order;
 insert into marketplace_order_status_history(store_order_id,previous_status,new_status,changed_by) values(p_order,'READY_FOR_DISPATCH','DELIVERED',p_actor);
 perform delivery_notice(null,o.customer_id,false,'Order '||target.store_order_number||' pickup completed.','pickup-completed:'||p_order) from marketplace_orders o where o.id=target.order_id and o.customer_id is not null;
 return 'completed';
end $$;
revoke all on function public.pickup_mark_ready(uuid,uuid,boolean,uuid,text),public.pickup_verify_handover(uuid,uuid,boolean,text) from public,anon,authenticated;
grant execute on function public.pickup_mark_ready(uuid,uuid,boolean,uuid,text),public.pickup_verify_handover(uuid,uuid,boolean,text) to service_role;
commit;

-- ============================================================================
-- Source: migrations/043_pickup_rescheduling.sql
-- ============================================================================
begin;
create table public.pickup_reschedule_proposals (
 id uuid primary key default gen_random_uuid(),store_order_id uuid not null references public.marketplace_store_orders(id),
 pickup_start timestamptz not null,pickup_end timestamptz not null,timezone text not null,
 status text not null default 'pending' check(status in ('pending','accepted','declined','superseded')),
 proposed_by uuid references auth.users(id),created_at timestamptz not null default now(),responded_at timestamptz,
 check(pickup_end=pickup_start+interval '1 hour')
);
create unique index pickup_one_pending_proposal on public.pickup_reschedule_proposals(store_order_id) where status='pending';
alter table public.pickup_reschedule_proposals enable row level security;
revoke all on public.pickup_reschedule_proposals from public,anon,authenticated;
grant all on public.pickup_reschedule_proposals to service_role;
create function public.pickup_propose_window(p_order uuid,p_actor uuid,p_admin boolean,p_start timestamptz,p_end timestamptz,p_hours jsonb,p_lead integer)
returns uuid language plpgsql security definer set search_path=public as $$
declare target marketplace_store_orders%rowtype; hours jsonb; lead integer; result uuid;
begin
 select * into target from marketplace_store_orders where id=p_order for update;
 if not found or target.fulfillment_method is distinct from 'pickup' or (p_admin is not true and not exists(select 1 from businesses where id=target.business_id and owner_id=p_actor)) then raise exception 'Order unavailable'; end if;
 if target.status not in ('PROCESSING','READY_FOR_DISPATCH') then raise exception 'Order changed'; end if;
 select details->'businessHours' into hours from businesses where id=target.business_id and is_published for share;
 select lead_minutes into lead from pickup_settings where id=true for share;
 if hours is distinct from p_hours or lead is distinct from p_lead or p_end is distinct from p_start+interval '1 hour' or p_start<now()+make_interval(mins=>lead) then raise exception 'Pickup availability changed'; end if;
 update pickup_reschedule_proposals set status='superseded',responded_at=now() where store_order_id=p_order and status='pending';
 insert into pickup_reschedule_proposals(store_order_id,pickup_start,pickup_end,timezone,proposed_by) values(p_order,p_start,p_end,p_hours->>'timezone',p_actor) returning id into result;
 perform delivery_notice(null,o.customer_id,false,'The seller proposed a new pickup time for order '||target.store_order_number||'. Review it in order history.','pickup-proposal:'||result) from marketplace_orders o where o.id=target.order_id and o.customer_id is not null;
 return result;
end $$;
create function public.pickup_respond_window(p_order uuid,p_proposal uuid,p_customer uuid,p_accept boolean,p_hours jsonb,p_lead integer)
returns text language plpgsql security definer set search_path=public as $$
declare target marketplace_store_orders%rowtype; proposal pickup_reschedule_proposals%rowtype; hours jsonb; lead integer;
begin
 select so.* into target from marketplace_store_orders so join marketplace_orders o on o.id=so.order_id where so.id=p_order and o.customer_id=p_customer for update of so;
 if not found or target.fulfillment_method is distinct from 'pickup' then return 'unavailable'; end if;
 if target.status not in ('PROCESSING','READY_FOR_DISPATCH') then return 'changed'; end if;
 select * into proposal from pickup_reschedule_proposals where id=p_proposal and store_order_id=p_order for update;
 if not found or proposal.status<>'pending' then return 'changed'; end if;
 if not p_accept then
  update pickup_reschedule_proposals set status='declined',responded_at=now() where id=proposal.id;
  perform delivery_notice(null,b.owner_id,false,'The buyer declined the new pickup time for order '||target.store_order_number||'.','pickup-response:'||proposal.id) from businesses b where b.id=target.business_id and b.owner_id is not null;
  return 'declined';
 end if;
 select details->'businessHours' into hours from businesses where id=target.business_id and is_published for share;
 select lead_minutes into lead from pickup_settings where id=true for share;
 if hours is distinct from p_hours or lead is distinct from p_lead or proposal.pickup_start<now()+make_interval(mins=>lead) then return 'changed'; end if;
 update marketplace_store_orders set pickup_start=proposal.pickup_start,pickup_end=proposal.pickup_end,pickup_timezone=proposal.timezone where id=p_order;
 update pickup_reschedule_proposals set status='accepted',responded_at=now() where id=proposal.id;
 perform delivery_notice(null,b.owner_id,false,'The buyer accepted the new pickup time for order '||target.store_order_number||'.','pickup-response:'||proposal.id) from businesses b where b.id=target.business_id and b.owner_id is not null;
 return 'accepted';
end $$;
revoke all on function public.pickup_propose_window(uuid,uuid,boolean,timestamptz,timestamptz,jsonb,integer), public.pickup_respond_window(uuid,uuid,uuid,boolean,jsonb,integer) from public,anon,authenticated;
grant execute on function public.pickup_propose_window(uuid,uuid,boolean,timestamptz,timestamptz,jsonb,integer), public.pickup_respond_window(uuid,uuid,uuid,boolean,jsonb,integer) to service_role;
commit;

-- ============================================================================
-- Source: migrations/044_pickup_logistics_guard.sql
-- ============================================================================
-- Existing logistics APIs remain available for legacy delivery orders, never for self pickup.
begin;
alter function public.delivery_select_order(uuid,uuid,boolean,jsonb) rename to delivery_select_order_legacy;
revoke all on function public.delivery_select_order_legacy(uuid,uuid,boolean,jsonb) from public,anon,authenticated,service_role;
create function public.delivery_select_order(p_store_order uuid,p_actor uuid,p_admin boolean,p_details jsonb)
returns uuid language plpgsql security definer set search_path=public as $$
declare mode text;
begin
 select fulfillment_method into mode from marketplace_store_orders where id=p_store_order;
 if mode='pickup' then raise exception 'Self pickup orders cannot enter delivery allocation'; end if;
 return delivery_select_order_legacy(p_store_order,p_actor,p_admin,p_details);
end $$;
revoke all on function public.delivery_select_order(uuid,uuid,boolean,jsonb) from public,anon,authenticated;
grant execute on function public.delivery_select_order(uuid,uuid,boolean,jsonb) to service_role;
commit;

-- ============================================================================
-- Source: migrations/045_fleet_partner_mapping.sql
-- ============================================================================
-- Explicitly map existing free-text partner vehicle labels to managed fleet types.
begin;
create table public.fleet_partner_vehicle_labels (
 fleet_type_id uuid not null references public.fleet_types(id) on delete restrict,
 vehicle_label text not null check(length(trim(vehicle_label)) between 1 and 80),
 created_by uuid references auth.users(id),created_at timestamptz not null default now(),
 primary key(fleet_type_id,vehicle_label),check(vehicle_label=lower(trim(vehicle_label)))
);
create unique index fleet_partner_vehicle_label_unique on public.fleet_partner_vehicle_labels(vehicle_label);
-- Exact existing labels are safe to map; other free-text labels require administrator review.
insert into public.fleet_partner_vehicle_labels(fleet_type_id,vehicle_label)
 select f.id,lower(f.name) from public.fleet_types f where f.code in ('scooter','bike','small_tempo','truck');
alter table public.fleet_partner_vehicle_labels enable row level security;
revoke all on public.fleet_partner_vehicle_labels from public,anon,authenticated;
grant all on public.fleet_partner_vehicle_labels to service_role;
commit;

-- ============================================================================
-- Source: migrations/046_fleet_only_matching.sql
-- ============================================================================
-- Fleet-only tasks cannot share a partner with another active task because their load is unknown.
begin;
alter table public.delivery_tasks add column fleet_only boolean not null default false;
alter table public.delivery_tasks alter column weight_kg drop not null;
alter table public.delivery_tasks alter column volume_litres drop not null;
alter table public.delivery_tasks add constraint delivery_fleet_measurements_consistent check ((fleet_only and weight_kg is null and volume_litres is null) or (not fleet_only and weight_kg is not null and volume_litres is not null));
create or replace function public.delivery_candidates(p_task uuid,p_type text default null) returns table(partner_id uuid,user_id uuid,full_name text,partner_type text,vehicle_type text,distance_km double precision,active_orders bigint,score double precision) language sql stable security definer set search_path=public as $$
 with eligible as (
 select p.id,p.user_id,p.full_name,p.partner_type,p.vehicle_type,
 delivery_distance_km(a.latitude,a.longitude,t.pickup_lat,t.pickup_lon) as distance_km,
 (select count(*) from delivery_assignments x where x.partner_id=p.id and x.ended_at is null) as workload,
 least(p.max_active_orders,(t.config->>'max_active_orders')::integer) as capacity,t.config,
 coalesce((select avg(delivery_distance_km(q.destination_lat,q.destination_lon,t.pickup_lat,t.pickup_lon))
   from delivery_assignments x join delivery_tasks q on q.id=x.task_id where x.partner_id=p.id and x.ended_at is null),
   delivery_distance_km(a.latitude,a.longitude,t.pickup_lat,t.pickup_lon)) as route_km
 from delivery_tasks t join marketplace_store_orders so on so.id=t.store_order_id join marketplace_orders o on o.id=so.order_id
 cross join delivery_partner_profiles p join delivery_partner_availability a on a.partner_id=p.id
 where t.id=p_task and p.verification_status='approved' and (p_type is null or p.partner_type=p_type)
 and p.user_id is distinct from o.customer_id and a.is_online and a.latitude is not null
 and a.location_recorded_at >= now()-make_interval(secs=>(t.config->>'location_max_age_seconds')::integer)
 and a.accuracy_m <= (t.config->>'max_location_accuracy_m')::numeric
 and lower(trim(p.service_area))=lower(trim(t.service_area)) and lower(trim(p.vehicle_type))=any(t.eligible_vehicles)
 and p.max_active_orders is not null
 and ((t.fleet_only and not exists(select 1 from delivery_assignments x where x.partner_id=p.id and x.ended_at is null))
   or (not t.fleet_only
    and not exists(select 1 from delivery_assignments x join delivery_tasks q on q.id=x.task_id where x.partner_id=p.id and x.ended_at is null and q.fleet_only)
    and p.capacity_kg>=t.weight_kg+coalesce((select sum(q.weight_kg) from delivery_assignments x join delivery_tasks q on q.id=x.task_id where x.partner_id=p.id and x.ended_at is null),0)
    and p.capacity_litres>=t.volume_litres+coalesce((select sum(q.volume_litres) from delivery_assignments x join delivery_tasks q on q.id=x.task_id where x.partner_id=p.id and x.ended_at is null),0)))
 and (p.partner_type='independent' or (p.employment_active and p.shift_start<=now() and p.shift_end>now()))
 ) select id,user_id,full_name,partner_type,vehicle_type,distance_km,workload,
 100*((config->'weights'->>'distance')::double precision/(1+distance_km)+
 (config->'weights'->>'workload')::double precision*(1-workload::double precision/capacity)+
 (config->'weights'->>'route')::double precision/(1+route_km)+
 (config->'weights'->>'availability')::double precision+(config->'weights'->>'vehicle')::double precision)/100
 from eligible where workload<capacity and distance_km <= (select max(value::double precision) from jsonb_array_elements_text(config->'search_radii_km'))
 order by 8 desc,6,1
$$;
revoke all on function public.delivery_candidates(uuid,text) from public,anon,authenticated;
grant execute on function public.delivery_candidates(uuid,text) to service_role;
commit;

-- ============================================================================
-- Source: migrations/047_delivery_checkout_allocation.sql
-- ============================================================================
begin;
alter table public.marketplace_store_orders
 add column delivery_fleet_id uuid references public.fleet_types(id) on delete restrict,
 add column delivery_fee numeric(12,2) check(delivery_fee is null or delivery_fee>=0),
 add column delivery_distance_km numeric(8,1) check(delivery_distance_km is null or delivery_distance_km>=0),
 add column delivery_quote_config jsonb,
 add column delivery_store_address jsonb;
create table public.delivery_order_allocation_jobs (
 store_order_id uuid primary key references public.marketplace_store_orders(id) on delete restrict,
 status text not null default 'queued' check(status in ('queued','created','cancelled')),
 actor_id uuid references auth.users(id), last_error text, created_at timestamptz not null default now(),updated_at timestamptz not null default now()
);
alter table public.delivery_order_allocation_jobs enable row level security;
revoke all on public.delivery_order_allocation_jobs from public,anon,authenticated;
grant all on public.delivery_order_allocation_jobs to service_role;

-- Read existing bilingual profile fields without requiring a duplicate address.
create function public.fulfillment_address_text(value jsonb) returns text language sql immutable set search_path=public as $$
 select nullif(trim(case when jsonb_typeof(value)='string' then value#>>'{}' when jsonb_typeof(value)='object' then coalesce(nullif(value->>'en',''),value->>'mr') else null end),'')
$$;

create function public.place_delivery_store_request(p_customer uuid,p_store uuid,p_key uuid,p_address_id uuid,p_expected jsonb,p_method text,p_fleet uuid,p_distance numeric,p_fee numeric,p_config jsonb,p_origin jsonb,p_destination jsonb)
returns jsonb language plpgsql security definer set search_path=public as $$
declare prior marketplace_store_orders%rowtype; result jsonb; origin jsonb; destination jsonb; cfg jsonb; highest uuid;
begin
 perform pg_advisory_xact_lock(hashtextextended(p_customer::text||':'||p_key::text,0));
 select so.* into prior from marketplace_orders o join marketplace_store_orders so on so.order_id=o.id where o.customer_id=p_customer and o.request_key=p_key;
 if found then
  if prior.business_id is distinct from p_store or prior.fulfillment_method is distinct from p_method or (select delivery_address_snapshot->>'id' from marketplace_orders where id=prior.order_id) is distinct from p_address_id::text then raise exception 'Request key already used'; end if;
  return jsonb_build_object('store_order_id',prior.id,'replayed',true);
 end if;
 if p_method not in ('standard_4_6h','standard_24h','urgent') or p_distance is null or p_distance<0 or p_fee is null or p_fee<0 then raise exception 'Invalid delivery'; end if;
 select details->'address' into origin from businesses where id=p_store and is_published for share;
 select to_jsonb(a) into destination from customer_addresses a where id=p_address_id and user_id=p_customer for share;
 select config into cfg from delivery_pricing_config where id=true for share;
 if origin is distinct from p_origin or destination is distinct from p_destination or cfg is distinct from p_config then raise exception 'Delivery availability changed'; end if;
 result:=place_saved_address_request(p_customer,p_store,p_key,p_address_id,p_expected);
 select f.id into highest from marketplace_order_items i join products p on p.id=i.product_id join fleet_types f on f.id=p.fleet_type_id where i.store_order_id=(result->>'store_order_id')::uuid order by f.sort_rank desc,f.id limit 1;
 if highest is distinct from p_fleet or not exists(select 1 from fleet_types where id=p_fleet and active) then raise exception 'Delivery availability changed'; end if;
 update marketplace_store_orders set fulfillment_method=p_method,delivery_fleet_id=p_fleet,delivery_distance_km=p_distance,delivery_fee=p_fee,delivery_quote_config=p_config,delivery_store_address=p_origin where id=(result->>'store_order_id')::uuid;
 return result;
end $$;

create function public.confirm_fulfillment_order(p_order uuid,p_actor uuid,p_admin boolean,p_token uuid,p_price numeric,p_fleet uuid)
returns boolean language plpgsql security definer set search_path=public as $$
declare target marketplace_store_orders%rowtype; rate numeric; base numeric; confirmed boolean; fee numeric; origin jsonb; address_row customer_addresses%rowtype; distance numeric; customer uuid; phone text;
begin
 perform pg_advisory_xact_lock(74901);
 select * into target from marketplace_store_orders where id=p_order for update;
 if not found or (p_admin is not true and not exists(select 1 from businesses where id=target.business_id and owner_id=p_actor)) then return false; end if;
 if target.status<>'PENDING' then return false; end if;
 if p_token is null or target.edit_token<>p_token then raise exception 'Order changed'; end if;
 if target.subtotal is null or target.subtotal<=0 or p_price is null or p_price<=0 or p_price>target.subtotal or p_price<>round(p_price,2) then raise exception 'Invalid closing price'; end if;
 if target.fulfillment_method in ('standard_4_6h','standard_24h','urgent') then
  if p_fleet is null or not exists(select 1 from fleet_types where id=p_fleet and active) then raise exception 'Fleet unavailable'; end if;
  select (x->>'perKm')::numeric into rate from jsonb_array_elements(target.delivery_quote_config->'fleetRates') x where x->>'fleetId'=p_fleet::text;
  base:=(target.delivery_quote_config->'speeds'->target.fulfillment_method->>'base')::numeric;
  if rate is null or base is null or target.delivery_distance_km is null then raise exception 'Fleet rate unavailable'; end if;
  select b.details->'address' into origin from businesses b where b.id=target.business_id and b.is_published for share;
  select o.customer_id into customer from marketplace_orders o where o.id=target.order_id;
  select a.* into address_row from customer_addresses a where a.id=(select (o.delivery_address_snapshot->>'id')::uuid from marketplace_orders o where o.id=target.order_id) and a.user_id=customer for share;
  if origin is null or address_row.id is null or origin->>'latitude' is null or origin->>'longitude' is null or address_row.latitude is null or address_row.longitude is null or fulfillment_address_text(origin->'street') is null or fulfillment_address_text(origin->'city') is null then raise exception 'Delivery address unavailable'; end if;
  if abs((origin->>'latitude')::numeric)>90 or abs((origin->>'longitude')::numeric)>180 then raise exception 'Delivery address unavailable'; end if;
  phone:=regexp_replace(address_row.phone_number,'[^0-9]','','g');
  if phone ~ '^[6-9][0-9]{9}$' then phone:='91'||phone; end if;
  if phone !~ '^91[6-9][0-9]{9}$' then raise exception 'Delivery address unavailable'; end if;
  if not (target.delivery_quote_config->'postcodes' ? address_row.postal_code) then raise exception 'Delivery address unavailable'; end if;
  distance:=ceil(delivery_distance_km((origin->>'latitude')::double precision,(origin->>'longitude')::double precision,address_row.latitude::double precision,address_row.longitude::double precision)*10)/10;
  if distance>(target.delivery_quote_config->>'maxRadiusKm')::numeric then raise exception 'Delivery address unavailable'; end if;
  fee:=round(base+distance*rate,2);
  update marketplace_orders set customer_name=address_row.full_name,customer_phone=phone,delivery_address=concat_ws(', ',address_row.address_line_1,address_row.address_line_2,nullif(address_row.landmark,''),address_row.city,address_row.state,address_row.postal_code,address_row.country),delivery_address_snapshot=to_jsonb(address_row)-'user_id'-'created_at'-'updated_at'-'is_default' where id=target.order_id;
  update marketplace_store_orders set delivery_fleet_id=p_fleet,delivery_fee=fee,delivery_distance_km=distance,delivery_store_address=origin,closing_price=p_price where id=p_order;
 else update marketplace_store_orders set closing_price=p_price where id=p_order; end if;
 confirmed:=manage_store_order(p_order,p_actor,p_admin,'accept');
 if confirmed and target.fulfillment_method='pickup' then
  update marketplace_store_orders set status='PROCESSING' where id=p_order;
  insert into marketplace_order_status_history(store_order_id,previous_status,new_status,changed_by) values(p_order,'ACCEPTED','PROCESSING',p_actor);
 elsif confirmed and target.fulfillment_method in ('standard_4_6h','standard_24h','urgent') then
  insert into delivery_order_allocation_jobs(store_order_id,actor_id) values(p_order,p_actor) on conflict do nothing;
  perform delivery_notice(null,o.customer_id,false,'Order '||target.store_order_number||' was confirmed. Delivery charge: ₹'||to_char(fee,'FM9999999990.00')||'. Allocation is starting.','delivery-confirmed:'||p_order) from marketplace_orders o where o.id=target.order_id and o.customer_id is not null;
 end if;
 return confirmed;
exception when invalid_text_representation or numeric_value_out_of_range then
 raise exception 'Delivery address unavailable';
end $$;

create function public.process_delivery_order_allocation() returns integer language plpgsql security definer set search_path=public as $$
declare job delivery_order_allocation_jobs%rowtype; so marketplace_store_orders%rowtype; parent marketplace_orders%rowtype; cfg jsonb; labels text[]; origin jsonb; task uuid; n integer:=0; pickup_text text;
begin
 if not pg_try_advisory_xact_lock(74901) then return 0; end if;
 for job in select j.* from delivery_order_allocation_jobs j join marketplace_store_orders s on s.id=j.store_order_id where j.status='queued' order by case when s.fulfillment_method='urgent' then 0 else 1 end,j.updated_at limit 100 for update of j skip locked loop
  begin
   select * into so from marketplace_store_orders where id=job.store_order_id for update;
   if so.status not in ('ACCEPTED','PROCESSING','READY_FOR_DISPATCH') or so.fulfillment_method not in ('standard_4_6h','standard_24h','urgent') then update delivery_order_allocation_jobs set status='cancelled',updated_at=now() where store_order_id=job.store_order_id;continue;end if;
   select config into cfg from delivery_settings where id=true;
   if cfg is null or not coalesce((cfg->>'enabled')::boolean,false) then raise exception 'Allocation settings are not enabled'; end if;
   select array_agg(vehicle_label order by vehicle_label) into labels from fleet_partner_vehicle_labels where fleet_type_id=so.delivery_fleet_id;
   if labels is null then raise exception 'No partner vehicle labels are mapped to this fleet'; end if;
   select * into parent from marketplace_orders where id=so.order_id;
   origin:=so.delivery_store_address;
   pickup_text:=concat_ws(', ',fulfillment_address_text(origin->'street'),fulfillment_address_text(origin->'landmark'),fulfillment_address_text(origin->'city'),fulfillment_address_text(origin->'state'),nullif(origin->>'pincode',''));
   if length(trim(pickup_text))<3 or nullif(parent.delivery_address_snapshot->>'city','') is null then raise exception 'Saved address is incomplete'; end if;
   insert into delivery_tasks(store_order_id,status,pickup_address,pickup_lat,pickup_lon,destination_address,destination_lat,destination_lon,service_area,package_description,weight_kg,volume_litres,eligible_vehicles,urgency,config,independent_deadline,created_by,fleet_only)
   values(so.id,'independent_allocation',pickup_text,(origin->>'latitude')::double precision,(origin->>'longitude')::double precision,parent.delivery_address,(parent.delivery_address_snapshot->>'latitude')::double precision,(parent.delivery_address_snapshot->>'longitude')::double precision,parent.delivery_address_snapshot->>'city','Order '||so.store_order_number,null,null,labels,case when so.fulfillment_method='urgent' then 'urgent' else 'standard' end,cfg,now()+make_interval(secs=>(cfg->>'independent_timeout_seconds')::integer),job.actor_id,true)
   on conflict(store_order_id) do nothing returning id into task;
   if task is null then select id into task from delivery_tasks where store_order_id=so.id; end if;
   perform delivery_log(task,job.actor_id,'delivery_automatically_requested',null,'independent_allocation');
   perform delivery_publish_offers(task);
   update delivery_order_allocation_jobs set status='created',last_error=null,updated_at=now() where store_order_id=so.id;
   n:=n+1;
  exception when others then
   update delivery_order_allocation_jobs set last_error='Allocation setup needs administrator attention',updated_at=now() where store_order_id=job.store_order_id;
   perform delivery_notice(null,null,true,'Delivery allocation needs attention for order '||coalesce(so.store_order_number,job.store_order_id::text),'delivery-setup:'||job.store_order_id);
  end;
 end loop;
 return n;
end $$;

create function public.switch_delivery_to_pickup(p_order uuid,p_customer uuid,p_start timestamptz,p_end timestamptz,p_hours jsonb,p_address jsonb,p_lead integer)
returns text language plpgsql security definer set search_path=public as $$
declare so marketplace_store_orders%rowtype; task delivery_tasks%rowtype; store_details jsonb; lead integer;
begin
 perform pg_advisory_xact_lock(74901);
 select s.* into so from marketplace_store_orders s join marketplace_orders o on o.id=s.order_id where s.id=p_order and o.customer_id=p_customer for update of s;
 if not found or so.fulfillment_method not in ('standard_4_6h','standard_24h','urgent') then return 'unavailable'; end if;
 if so.confirmed_at is null or so.confirmed_at>now()-interval '24 hours' or so.status not in ('ACCEPTED','PROCESSING','READY_FOR_DISPATCH') then return 'unavailable'; end if;
 select * into task from delivery_tasks where store_order_id=p_order for update;
 if found and (task.partner_id is not null or task.status in ('picked_up','on_the_way','awaiting_customer_confirmation','completed','cancelled')) then return 'assigned'; end if;
 select b.details into store_details from businesses b where b.id=so.business_id and b.is_published for share;
 select lead_minutes into lead from pickup_settings where id=true for share;
 if store_details->'businessHours' is distinct from p_hours or store_details->'address' is distinct from p_address or lead is distinct from p_lead or p_end is distinct from p_start+interval '1 hour' or p_start<now()+make_interval(mins=>lead) then return 'changed'; end if;
 if task.id is not null then
  perform delivery_notice(task.id,p.user_id,false,'The customer chose store pickup; this delivery offer is no longer available.','pickup-switch-offer:'||task.id||':'||p.id) from delivery_allocation_attempts a join delivery_partner_profiles p on p.id=a.partner_id where a.task_id=task.id and a.status='offered';
  update delivery_allocation_attempts set status='unavailable',responded_at=now() where task_id=task.id and status='offered';
  update delivery_tasks set status='cancelled',updated_at=now() where id=task.id;
  perform delivery_log(task.id,p_customer,'switched_to_pickup',task.status,'cancelled','Customer chose pickup');
 end if;
 update delivery_order_allocation_jobs set status='cancelled',updated_at=now() where store_order_id=p_order;
 update marketplace_store_orders set fulfillment_method='pickup',delivery_fee=0,pickup_start=p_start,pickup_end=p_end,pickup_timezone=p_hours->>'timezone',pickup_store_address=p_address,status='PROCESSING' where id=p_order;
 if so.status<>'PROCESSING' then insert into marketplace_order_status_history(store_order_id,previous_status,new_status,changed_by) values(p_order,so.status,'PROCESSING',p_customer);end if;
 perform delivery_notice(null,b.owner_id,false,'The buyer chose store pickup for order '||so.store_order_number||'.','delivery-switch-pickup:'||p_order) from businesses b where b.id=so.business_id and b.owner_id is not null;
 return 'switched';
end $$;

create or replace function public.process_delivery_jobs() returns integer language plpgsql security definer set search_path=public as $$
declare t delivery_tasks%rowtype; a delivery_assignments%rowtype; n integer:=0; p delivery_partner_profiles%rowtype;
begin
 -- Across all server instances: one short database transaction owns allocation.
 if not pg_try_advisory_xact_lock(74901) then return 0; end if;
 for t in select * from delivery_tasks where status in ('independent_allocation','salaried_allocation','assigned','accepted','reached_pickup','picked_up','on_the_way','awaiting_customer_confirmation') order by case when urgency='urgent' then 0 else 1 end,updated_at limit 200 for update skip locked loop
  n:=n+1;
  if t.status='independent_allocation' then
   if t.independent_deadline<=now() then
    update delivery_allocation_attempts set status='expired',responded_at=now() where task_id=t.id and status='offered';
    update delivery_tasks set status='salaried_allocation',updated_at=now() where id=t.id;
    perform delivery_log(t.id,null,'independent_window_expired','independent_allocation','salaried_allocation');
    perform delivery_fallback(t.id);
   else perform delivery_publish_offers(t.id); end if;
  elsif t.status='salaried_allocation' then perform delivery_fallback(t.id);
  elsif t.status='assigned' then
   select * into a from delivery_assignments where task_id=t.id and ended_at is null;
   select * into p from delivery_partner_profiles where id=t.partner_id;
   if a.acknowledgement_deadline<=now() or p.verification_status<>'approved' then
    update delivery_assignments set status='expired',ended_at=now() where id=a.id;
    update delivery_allocation_attempts set status='expired',responded_at=now() where task_id=t.id and partner_id=t.partner_id and status='offered';
    update delivery_tasks set status='salaried_allocation',partner_id=null,updated_at=now() where id=t.id;
    perform delivery_log(t.id,null,'acknowledgement_expired','assigned','salaried_allocation');
    perform delivery_fallback(t.id);
   end if;
  elsif t.status='awaiting_customer_confirmation' and t.confirmation_deadline<=now() then
   perform delivery_raise_exception(t.id,'customer_confirmation_overdue','Customer has not confirmed receipt.');
  end if;
  if exists(select 1 from delivery_tasks current_task join delivery_partner_profiles current_profile on current_profile.id=current_task.partner_id where current_task.id=t.id and current_profile.verification_status<>'approved') then
   perform delivery_raise_exception(t.id,'partner_unavailable','Assigned partner is no longer approved; administrator intervention required.');
  end if;
  -- Rotate scanned rows fairly when the queue exceeds the batch size.
  update delivery_tasks set updated_at=now() where id=t.id;
 end loop;
 insert into delivery_worker_health(id,last_success_at,processed) values(true,now(),n) on conflict(id) do update set last_success_at=now(),processed=n;
 return n;
end $$;


-- New fulfillment orders enter allocation automatically; the legacy selector is only for historical orders.
create or replace function public.delivery_select_order(p_store_order uuid,p_actor uuid,p_admin boolean,p_details jsonb)
returns uuid language plpgsql security definer set search_path=public as $$
declare mode text;
begin
 select so.fulfillment_method into mode from marketplace_store_orders so where so.id=p_store_order and (p_admin is true or exists(select 1 from businesses b where b.id=so.business_id and b.owner_id=p_actor));
 if not found then raise exception 'Delivery access denied'; end if;
 if mode='pickup' then raise exception 'Self pickup orders cannot enter delivery allocation'; end if;
 if mode is not null then raise exception 'Delivery allocation starts automatically after confirmation'; end if;
 return delivery_select_order_legacy(p_store_order,p_actor,p_admin,p_details);
end $$;

-- Recalculate the estimate after a buyer changes pending order items.
create function public.refresh_pending_delivery_quote() returns trigger language plpgsql set search_path=public as $$
declare chosen uuid; rate numeric; base numeric;
begin
 if new.fulfillment_method not in ('standard_4_6h','standard_24h','urgent') or new.status<>'PENDING' then return new; end if;
 select f.id into chosen from marketplace_order_items i join products p on p.id=i.product_id join fleet_types f on f.id=p.fleet_type_id where i.store_order_id=new.id and f.active order by f.sort_rank desc,f.id limit 1;
 select (x->>'perKm')::numeric into rate from jsonb_array_elements(new.delivery_quote_config->'fleetRates') x where x->>'fleetId'=chosen::text;
 base:=(new.delivery_quote_config->'speeds'->new.fulfillment_method->>'base')::numeric;
 new.delivery_fleet_id:=chosen;
 new.delivery_fee:=case when rate is not null and base is not null and new.delivery_distance_km is not null then round(base+new.delivery_distance_km*rate,2) else null end;
 return new;
end $$;
create trigger pending_delivery_quote_refresh before update of edit_token on public.marketplace_store_orders for each row execute function public.refresh_pending_delivery_quote();

revoke all on function public.place_delivery_store_request(uuid,uuid,uuid,uuid,jsonb,text,uuid,numeric,numeric,jsonb,jsonb,jsonb),public.confirm_fulfillment_order(uuid,uuid,boolean,uuid,numeric,uuid),public.process_delivery_order_allocation(),public.switch_delivery_to_pickup(uuid,uuid,timestamptz,timestamptz,jsonb,jsonb,integer) from public,anon,authenticated;
grant execute on function public.place_delivery_store_request(uuid,uuid,uuid,uuid,jsonb,text,uuid,numeric,numeric,jsonb,jsonb,jsonb),public.confirm_fulfillment_order(uuid,uuid,boolean,uuid,numeric,uuid),public.process_delivery_order_allocation(),public.switch_delivery_to_pickup(uuid,uuid,timestamptz,timestamptz,jsonb,jsonb,integer) to service_role;
commit;
