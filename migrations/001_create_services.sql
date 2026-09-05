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
