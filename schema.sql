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
  price numeric(12,2) default 0,
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
  starting_price numeric(12,2) not null check (starting_price >= 0),
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
