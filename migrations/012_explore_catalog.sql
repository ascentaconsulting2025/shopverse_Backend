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
