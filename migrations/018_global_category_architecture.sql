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
