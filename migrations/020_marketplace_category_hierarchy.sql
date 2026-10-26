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
