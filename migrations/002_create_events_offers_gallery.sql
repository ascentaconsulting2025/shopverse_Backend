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