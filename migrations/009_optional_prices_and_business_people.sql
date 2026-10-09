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
