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
