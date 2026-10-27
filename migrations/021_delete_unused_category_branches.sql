-- Delete unused branches and their catalog mappings atomically.
-- Business, listing, and gallery references still prevent deletion.
begin;
create or replace function public.write_global_category(p_id uuid,p_version bigint,p_fields jsonb,p_delete boolean default false)
returns jsonb language plpgsql security invoker set search_path=public as $$
declare node business_categories; branch uuid[]; removed record; begin
 perform pg_advisory_xact_lock(184712009);
 if p_id is not null then
  select * into node from business_categories where id=p_id for update;
  if not found then raise exception 'Category not found' using errcode='P0002'; end if;
  if p_version is distinct from node.version then raise exception 'Category changed; reload before saving' using errcode='40001'; end if;
 end if;
 if p_delete then
  -- Mappings are configuration; real records remain protected by restrictive FKs.
  with recursive descendants as (
   select id from business_categories where id=p_id
   union all select c.id from business_categories c join descendants d on c.parent_id=d.id
  ) select array_agg(id) into branch from descendants;
  update business_categories set updated_at=now()
   where not (id=any(branch)) and id in (
    select business_category_id from business_catalog_mappings where catalog_category_id=any(branch)
   );
  delete from business_catalog_mappings
   where business_category_id=any(branch) or catalog_category_id=any(branch);
  -- Delete leaves first to satisfy immediate parent constraints.
  for removed in
   with recursive descendants as (
    select id,0 as depth from business_categories where id=p_id
    union all select c.id,d.depth+1 from business_categories c join descendants d on c.parent_id=d.id
   ) select id from descendants order by depth desc,id
  loop
   delete from business_categories where id=removed.id;
  end loop;
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

commit;
