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