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
  slug text not null,
  category text,
  description text,
  logo_url text,
  whatsapp_number text,
  address text,
  social_links jsonb,
  qr_code_url text,
  is_published boolean default false,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

-- Unique slug
create unique index if not exists idx_businesses_slug on public.businesses(slug);

-- Products
create table if not exists public.products (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  name text not null,
  description text,
  price numeric(12,2) default 0,
  image_url text,
  category text,
  is_available boolean default true,
  sort_order int default 0,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

-- Composite index for product list queries
create index if not exists idx_products_business_available on public.products(business_id, is_available);

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
