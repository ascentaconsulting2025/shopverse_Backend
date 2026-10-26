-- Extend the canonical taxonomy; never infer business types from legacy rows.
begin;
lock table public.business_categories in access exclusive mode;
alter table public.business_categories add column if not exists catalog_kind text not null default 'legacy'
 check(catalog_kind in ('legacy','business','product','service'));
create index if not exists categories_kind_parent on public.business_categories(catalog_kind,parent_id);
create table if not exists public.business_catalog_mappings (
 business_category_id uuid not null references public.business_categories(id) on delete restrict,
 catalog_category_id uuid not null references public.business_categories(id) on delete restrict,
 created_at timestamptz not null default now(),
 primary key(business_category_id,catalog_category_id)
);
create index if not exists catalog_mapping_reverse on public.business_catalog_mappings(catalog_category_id);
alter table public.business_catalog_mappings enable row level security;
revoke all on public.business_catalog_mappings from public,anon,authenticated;
grant all on public.business_catalog_mappings to service_role;

create or replace function public.guard_catalog_kind() returns trigger
language plpgsql set search_path=public as $$
begin
 -- guard_global_category already serializes category writes using this same lock.
 perform pg_advisory_xact_lock(184712009);
 if new.catalog_kind='business' and new.parent_id is not null then
  raise exception 'Business categories must be roots' using errcode='23514'; end if;
 if new.parent_id is not null and new.catalog_kind<>'legacy' and not exists(
  select 1 from business_categories where id=new.parent_id and catalog_kind=new.catalog_kind
 ) then raise exception 'Parent and child must have the same category type' using errcode='23514';end if;
 if tg_op='UPDATE' and new.catalog_kind is distinct from old.catalog_kind then
  if exists(select 1 from business_categories where parent_id=new.id and catalog_kind not in ('legacy',new.catalog_kind))
   or exists(select 1 from business_catalog_mappings where business_category_id=new.id or catalog_category_id=new.id)
   or exists(select 1 from businesses where global_category_id=new.id)
   or exists(select 1 from products where folder_category_id=new.id or category_id=new.id)
   or exists(select 1 from services where folder_category_id=new.id or category_id=new.id)
  then raise exception 'Referenced category type cannot change; create a category or migrate references first' using errcode='23514';end if;
 end if;
 return new;
end $$;
drop trigger if exists guard_catalog_kind on public.business_categories;
create trigger guard_catalog_kind before insert or update on public.business_categories for each row execute function public.guard_catalog_kind();

-- Effective permission: active business type, active same-type ancestors, a mapped
-- ancestor (or self), and a structural leaf. p_roots supports preview without writes.
create or replace function public.catalog_category_allowed(p_business_category uuid,p_type text,p_category uuid,p_roots uuid[] default null)
returns boolean language sql stable security definer set search_path=public as $$
 with recursive ancestors as (
  select id,parent_id,catalog_kind,status,is_published from business_categories where id=p_category
  union all select c.id,c.parent_id,c.catalog_kind,c.status,c.is_published from business_categories c join ancestors a on c.id=a.parent_id
 ) select coalesce(
  p_type in ('product','service')
  and exists(select 1 from business_categories where id=p_business_category and catalog_kind='business' and status='enabled' and is_published)
  and exists(select 1 from ancestors)
  and (select bool_and(catalog_kind=p_type and status='enabled' and is_published) from ancestors)
  and not exists(select 1 from business_categories where parent_id=p_category)
  and exists(select 1 from ancestors a where case when p_roots is null then
   exists(select 1 from business_catalog_mappings m where m.business_category_id=p_business_category and m.catalog_category_id=a.id)
   else a.id=any(p_roots) end), false);
$$;
revoke all on function public.catalog_category_allowed(uuid,text,uuid,uuid[]) from public,anon,authenticated;
grant execute on function public.catalog_category_allowed(uuid,text,uuid,uuid[]) to service_role;

create or replace function public.validate_business_catalog_reference() returns trigger
language plpgsql security definer set search_path=public as $$
declare business_category uuid; selected uuid; previous uuid;
begin
 perform pg_advisory_xact_lock_shared(184712009);
 if tg_table_name='businesses' then
  selected:=new.global_category_id;
  if tg_op='UPDATE' and selected is not distinct from old.global_category_id then return new;end if;
  if not exists(select 1 from business_categories where id=selected and catalog_kind='business' and status='enabled' and is_published) then
   raise exception 'Select an active business category' using errcode='23514';end if;
 else
  select global_category_id into business_category from businesses where id=new.business_id for share;
  if not catalog_category_allowed(business_category,case when tg_table_name='products' then 'product' else 'service' end,new.folder_category_id)
   or new.category_id is distinct from new.folder_category_id then
   raise exception 'Select an active allowed leaf category for this business and listing type' using errcode='23514';end if;
 end if;
 return new;
end $$;
do $$ declare t text;begin
 foreach t in array array['businesses','products','services'] loop
  execute format('drop trigger if exists validate_business_catalog_reference on public.%I',t);
  execute format('create trigger validate_business_catalog_reference before insert or update on public.%I for each row execute function public.validate_business_catalog_reference()',t);
 end loop;
end $$;

-- Conservative impact preview for editing a category or turning a leaf into a group.
create or replace function public.catalog_category_impact(p_id uuid)
returns jsonb language sql stable security invoker set search_path=public as $$
 with recursive subtree as (
  select id from business_categories where id=p_id
  union all select c.id from business_categories c join subtree s on c.parent_id=s.id
 ), items as (
  select business_id,folder_category_id from products union all select business_id,folder_category_id from services
 ), affected as (
  select i.* from items i join businesses b on b.id=i.business_id
   where i.folder_category_id in (select id from subtree) or b.global_category_id in (select id from subtree)
 ) select jsonb_build_object('affectedListings',count(*),'affectedBusinesses',
  (select count(*) from businesses where global_category_id in (select id from subtree) or id in (select business_id from affected))) from affected;
$$;
revoke all on function public.catalog_category_impact(uuid) from public,anon,authenticated;
grant execute on function public.catalog_category_impact(uuid) to service_role;

-- Count affected existing records before mapping/business-assignment changes.
create or replace function public.catalog_assignment_impact(p_business_category uuid,p_business uuid default null,p_type text default null,p_categories uuid[] default null)
returns jsonb language sql stable security invoker set search_path=public as $$
 with items as (
  select business_id,'product'::text as kind,folder_category_id from products
  union all select business_id,'service'::text,folder_category_id from services
 ), affected as (
  select i.* from items i join businesses b on b.id=i.business_id
  where (case when p_business is null then b.global_category_id=p_business_category else b.id=p_business end)
   and (p_type is null or i.kind=p_type)
   and not catalog_category_allowed(p_business_category,i.kind,i.folder_category_id,p_categories)
 ) select jsonb_build_object('affectedListings',count(*),'affectedBusinesses',count(distinct business_id)) from affected;
$$;
revoke all on function public.catalog_assignment_impact(uuid,uuid,text,uuid[]) from public,anon,authenticated;
grant execute on function public.catalog_assignment_impact(uuid,uuid,text,uuid[]) to service_role;

create or replace function public.replace_business_catalog_mappings(p_business_category uuid,p_type text,p_categories uuid[],p_version bigint)
returns jsonb language plpgsql security invoker set search_path=public as $$
declare node business_categories;next_version bigint;
begin
 perform pg_advisory_xact_lock(184712009);
 select * into node from business_categories where id=p_business_category for update;
 if not found then raise exception 'Category not found' using errcode='P0002';end if;
 if node.catalog_kind<>'business' or p_type not in ('product','service') or p_categories is null or cardinality(p_categories)>1000
  or cardinality(p_categories)<>(select count(distinct id) from unnest(p_categories) id)
  or exists(select 1 from unnest(p_categories) roots(category_id) where not exists(select 1 from business_categories c where c.id=roots.category_id and c.catalog_kind=p_type))
 then raise exception 'Invalid business category mappings' using errcode='23514';end if;
 if node.version is distinct from p_version then raise exception 'Category changed; reload before saving' using errcode='40001';end if;
 delete from business_catalog_mappings m using business_categories c
  where m.business_category_id=p_business_category and m.catalog_category_id=c.id and c.catalog_kind=p_type;
 insert into business_catalog_mappings(business_category_id,catalog_category_id)
  select p_business_category,id from unnest(p_categories) id;
 update business_categories set updated_at=now() where id=p_business_category returning version into next_version;
 return jsonb_build_object('version',next_version);
end $$;
revoke all on function public.replace_business_catalog_mappings(uuid,text,uuid[],bigint) from public,anon,authenticated;
grant execute on function public.replace_business_catalog_mappings(uuid,text,uuid[],bigint) to service_role;

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
  insert into business_categories(name,name_mr,parent_id,image_url,icon,status,catalog_kind)
   values(trim(p_fields->>'name'),coalesce(p_fields->>'name_mr',''),(p_fields->>'parent_id')::uuid,
    coalesce(p_fields->>'image_url',''),coalesce(p_fields->>'icon','Tag'),coalesce(p_fields->>'status','enabled'),coalesce(p_fields->>'catalog_kind','legacy')) returning * into node;
 else
  update business_categories set
   catalog_kind=case when p_fields?'catalog_kind' then p_fields->>'catalog_kind' else catalog_kind end,
   name=case when p_fields?'name' then trim(p_fields->>'name') else name end,
   name_mr=case when p_fields?'name_mr' then p_fields->>'name_mr' else name_mr end,
   parent_id=case when p_fields?'parent_id' then (p_fields->>'parent_id')::uuid else parent_id end,
   image_url=case when p_fields?'image_url' then p_fields->>'image_url' else image_url end,
   icon=case when p_fields?'icon' then p_fields->>'icon' else icon end,
   status=case when p_fields?'status' then p_fields->>'status' else status end
  where id=p_id returning * into node;
 end if;
 if p_fields?'map_business_category_id' then
  if p_id is not null or node.catalog_kind not in ('product','service') or not exists(
   select 1 from business_categories where id=(p_fields->>'map_business_category_id')::uuid and catalog_kind='business'
  ) then raise exception 'Invalid contextual category mapping' using errcode='23514';end if;
  insert into business_catalog_mappings(business_category_id,catalog_category_id)
   values((p_fields->>'map_business_category_id')::uuid,node.id);
  update business_categories set updated_at=now() where id=(p_fields->>'map_business_category_id')::uuid;
 end if;
 return to_jsonb(node);
end $$;
revoke all on function public.write_global_category(uuid,bigint,jsonb,boolean) from public,anon,authenticated;
grant execute on function public.write_global_category(uuid,bigint,jsonb,boolean) to service_role;

create or replace function public.import_catalog_categories(p_paths jsonb,p_preview boolean,p_kind text)
returns jsonb language plpgsql security invoker set search_path=public as $$
declare path jsonb; label text; parent uuid; found_id uuid; created integer:=0; reused integer:=0;
 results jsonb:='[]'::jsonb; known jsonb:='{}'::jsonb; key text; depth integer;
begin
 perform pg_advisory_xact_lock(184712009);
 if p_kind not in ('legacy','product','service') then raise exception 'Import product or service trees separately' using errcode='23514';end if;
 if jsonb_typeof(p_paths)<>'array' or jsonb_array_length(p_paths)>1000 then raise exception 'Invalid import' using errcode='23514'; end if;
 for path in select value from jsonb_array_elements(p_paths) order by jsonb_array_length(value) loop
  parent:=null; key:=''; depth:=0;
  for label in select value from jsonb_array_elements_text(path) loop
   label:=trim(label);
   if length(label) not between 1 and 100 or depth>=32 then raise exception 'Invalid category path' using errcode='23514'; end if;
   key:=key||'/'||encode(convert_to(lower(label),'UTF8'),'hex');
   if known ? key then parent:=(known->>key)::uuid; depth:=depth+1; continue; end if;
   select id into found_id from business_categories where catalog_kind=p_kind and parent_id is not distinct from parent and lower(trim(name))=lower(label) order by created_at,id limit 1;
   if found_id is null then
    created:=created+1;
    if p_preview then found_id:=gen_random_uuid();
    else insert into business_categories(name,parent_id,catalog_kind) values(label,parent,p_kind) returning id into found_id; end if;
   else reused:=reused+1; end if;
   results:=results||jsonb_build_array(jsonb_build_object('name',label,'depth',depth,'exists',exists(select 1 from business_categories where id=found_id),'path',path));
   known:=known||jsonb_build_object(key,found_id); parent:=found_id; depth:=depth+1;
  end loop;
 end loop;
 return jsonb_build_object('created',created,'reused',reused,'failed',0,'nodes',results);
end $$;
revoke all on function public.import_catalog_categories(jsonb,boolean,text) from public,anon,authenticated;
grant execute on function public.import_catalog_categories(jsonb,boolean,text) to service_role;


commit;
