-- Safe to rerun after a partial or completed installation. Existing data is preserved.
begin;
create table if not exists public.business_categories (
 id uuid primary key default gen_random_uuid(),
 business_id uuid not null references public.businesses(id) on delete cascade,
 type text not null check (type in ('product','service')),
 name text not null check (length(trim(name)) between 1 and 100),
 image_url text not null default '',
 display_order integer not null default 0,
 is_published boolean not null default true,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(id,business_id,type)
);
alter table public.business_categories add column if not exists legacy_category_id uuid;
create unique index if not exists business_categories_legacy_scope_idx
 on public.business_categories(business_id,type,legacy_category_id);
create index if not exists business_categories_business_type_order_idx on public.business_categories(business_id,type,display_order);
alter table public.products
 add column if not exists folder_category_id uuid,
 add column if not exists category_type text generated always as ('product'::text) stored,
 add column if not exists is_published boolean not null default true,
 add column if not exists folder_assignment_migrated boolean not null default false;
alter table public.services
 add column if not exists folder_category_id uuid,
 add column if not exists category_type text generated always as ('service'::text) stored,
 add column if not exists is_published boolean not null default true,
 add column if not exists folder_assignment_migrated boolean not null default false;

-- The deployed schema uses products.category_id/services.category_id for the
-- shared listing_categories taxonomy. Preserve those columns and their FKs.
-- Import only assigned legacy categories, once per business and item type.
do $$
declare item_table text; item_type text;
begin
 if to_regclass('public.listing_categories') is not null then
  foreach item_table in array array['products','services'] loop
   item_type := case when item_table='products' then 'product' else 'service' end;
   if exists(select 1 from information_schema.columns where table_schema='public'
     and table_name=item_table and column_name='category_id') then
    execute format($import$
     insert into public.business_categories
      (business_id,type,name,image_url,display_order,is_published,legacy_category_id)
     select distinct i.business_id,%L,
      left(coalesce(nullif(trim(c.name),''),'Imported category'),100),
      coalesce(c.image_url,''),coalesce(c.display_order,0),coalesce(c.is_active,true),c.id
     from public.%I i join public.listing_categories c on c.id=i.category_id
     where not i.folder_assignment_migrated
     on conflict(business_id,type,legacy_category_id) do nothing
    $import$,item_type,item_table);
    execute format($assign$
     update public.%I i set folder_category_id=c.id, folder_assignment_migrated=true
     from public.business_categories c
     where c.business_id=i.business_id and c.type=%L
      and c.legacy_category_id=i.category_id and i.folder_category_id is null and not i.folder_assignment_migrated
    $assign$,item_table,item_type);
   end if;
  end loop;
 end if;
end $$;
update public.products set folder_assignment_migrated=true where not folder_assignment_migrated;
update public.services set folder_assignment_migrated=true where not folder_assignment_migrated;
alter table public.products alter column folder_assignment_migrated set default true;
alter table public.services alter column folder_assignment_migrated set default true;

-- ADD COLUMN IF NOT EXISTS does not add a missing FK to an existing column.
-- Install the constraints separately, preserving existing rows and assignments.
do $$
declare item_table text; category_column smallint;
begin
 if not exists (
  select 1 from pg_constraint where conrelid='public.business_categories'::regclass
  and contype='u' and conkey=array[
   (select attnum from pg_attribute where attrelid='public.business_categories'::regclass and attname='id'),
   (select attnum from pg_attribute where attrelid='public.business_categories'::regclass and attname='business_id'),
   (select attnum from pg_attribute where attrelid='public.business_categories'::regclass and attname='type')
  ]::smallint[]
 ) then
  alter table public.business_categories add constraint business_categories_scope_unique unique(id,business_id,type);
 end if;
 foreach item_table in array array['products','services'] loop
  select attnum into category_column from pg_attribute
   where attrelid=format('public.%I',item_table)::regclass and attname='folder_category_id';
  if not exists (
   select 1 from pg_constraint where conrelid=format('public.%I',item_table)::regclass
   and contype='f' and confrelid='public.business_categories'::regclass
   and conkey=array[category_column] and confdeltype='n'
  ) then
   execute format('alter table public.%I add constraint %I foreign key(folder_category_id) references public.business_categories(id) on delete set null',item_table,item_table || '_business_folder_fk');
  end if;
  if not exists (
   select 1 from pg_constraint where conrelid=format('public.%I',item_table)::regclass
   and conname=item_table || '_folder_scope'
  ) then
   execute format('alter table public.%I add constraint %I foreign key(folder_category_id,business_id,category_type) references public.business_categories(id,business_id,type)',item_table,item_table || '_folder_scope');
  end if;
 end loop;
end $$;
create index if not exists products_business_folder_category_idx on public.products(business_id,folder_category_id);
create index if not exists services_business_folder_category_idx on public.services(business_id,folder_category_id);
alter table public.business_categories enable row level security;
drop policy if exists "Category owner access" on public.business_categories;
create policy "Category owner access" on public.business_categories for all
 using (exists(select 1 from public.businesses b where b.id=business_id and b.owner_id=auth.uid()))
 with check (exists(select 1 from public.businesses b where b.id=business_id and b.owner_id=auth.uid()));
drop policy if exists "Published categories" on public.business_categories;
create policy "Published categories" on public.business_categories for select using (
 is_published and exists(select 1 from public.businesses b where b.id=business_id and b.is_published)
);
-- Restrictive policies also protect direct Supabase reads alongside existing policies.
drop policy if exists "Product publication boundary" on public.products;
create policy "Product publication boundary" on public.products as restrictive for select using (
 exists(select 1 from public.businesses b where b.id=business_id and b.owner_id=auth.uid())
 or (is_published and (folder_category_id is null or exists(select 1 from public.business_categories c where c.id=folder_category_id and c.is_published)))
);
drop policy if exists "Service publication boundary" on public.services;
create policy "Service publication boundary" on public.services as restrictive for select using (
 exists(select 1 from public.businesses b where b.id=business_id and b.owner_id=auth.uid())
 or (is_published and (folder_category_id is null or exists(select 1 from public.business_categories c where c.id=folder_category_id and c.is_published)))
);
-- Atomic bulk moves validate every requested record before updating any record.
create or replace function public.move_category_items(p_business uuid,p_type text,p_ids uuid[],p_category uuid)
returns void language plpgsql security invoker set search_path=public as $$
declare matched integer;
begin
 if p_type not in ('product','service') or cardinality(p_ids) < 1 then raise exception 'Invalid move'; end if;
 if p_category is not null and not exists(select 1 from business_categories where id=p_category and business_id=p_business and type=p_type) then raise exception 'Invalid category'; end if;
 if p_type='product' then
  perform id from products where business_id=p_business and id=any(p_ids) for update;
  select count(*) into matched from products where business_id=p_business and id=any(p_ids);
 else
  perform id from services where business_id=p_business and id=any(p_ids) for update;
  select count(*) into matched from services where business_id=p_business and id=any(p_ids);
 end if;
 if matched <> cardinality(p_ids) then raise exception 'Invalid items'; end if;
 if p_type='product' then update products set folder_category_id=p_category,updated_at=now() where business_id=p_business and id=any(p_ids);
 else update services set folder_category_id=p_category,updated_at=now() where business_id=p_business and id=any(p_ids); end if;
end $$;
revoke all on function public.move_category_items(uuid,text,uuid[],uuid) from public,anon,authenticated;
grant execute on function public.move_category_items(uuid,text,uuid[],uuid) to service_role;
create or replace function public.reorder_categories(p_business uuid,p_type text,p_ids uuid[])
returns void language plpgsql security invoker set search_path=public as $$
begin
 perform id from business_categories where business_id=p_business and type=p_type for update;
 if (select count(*) from business_categories where business_id=p_business and type=p_type) <> cardinality(p_ids)
 or (select count(distinct id) from unnest(p_ids) id) <> cardinality(p_ids)
 or exists(select 1 from unnest(p_ids) requested(id) where not exists(select 1 from business_categories c where c.id=requested.id and c.business_id=p_business and c.type=p_type)) then raise exception 'Category list changed; refresh and try again'; end if;
 update business_categories c set display_order=o.position-1,updated_at=now()
 from unnest(p_ids) with ordinality o(id,position) where c.id=o.id and c.business_id=p_business and c.type=p_type;
end $$;
revoke all on function public.reorder_categories(uuid,text,uuid[]) from public,anon,authenticated;
grant execute on function public.reorder_categories(uuid,text,uuid[]) to service_role;
commit;
