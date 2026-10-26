-- Fresh disposable database ONLY. Includes the existing schema and migrations.
\set ON_ERROR_STOP on
\ir packages-fixture.sql
-- Simulate the deployed shared taxonomy before replacement.
create table public.listing_categories(id uuid primary key,name text,image_url text,display_order integer,is_active boolean);
alter table products add column category_id uuid references listing_categories(id);
alter table services add column category_id uuid references listing_categories(id);
insert into auth.users values('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
insert into profiles(id) values('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
insert into businesses(id,owner_id,business_name,slug,is_published,plan_id) values('11111111-1111-4111-8111-111111111111','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','Shop','shop',true,'premium');
insert into business_categories(id,business_id,type,name,name_mr,image_url,is_published) values
 ('22222222-2222-4222-8222-222222222222','11111111-1111-4111-8111-111111111111','product','Original folder','मूळ','https://example.com/image.jpg',true),
 ('33333333-3333-4333-8333-333333333333','11111111-1111-4111-8111-111111111111','service','Original folder','','',false);
insert into listing_categories values('44444444-4444-4444-8444-444444444444','Old taxonomy','',0,true);
insert into products(id,business_id,name,name_en,name_mr,price,folder_category_id,category_id) values('55555555-5555-4555-8555-555555555555','11111111-1111-4111-8111-111111111111','Product','Product','उत्पादन',100,'22222222-2222-4222-8222-222222222222','44444444-4444-4444-8444-444444444444');
\ir ../migrations/018_global_category_architecture.sql
\ir ../migrations/018_global_category_architecture.sql

do $$ declare result jsonb; root uuid; child uuid; v bigint; begin
 if (select count(*) from business_categories)<>3 then raise exception 'Migration changed category count'; end if;
 if not exists(select 1 from products where price=100 and folder_category_id='22222222-2222-4222-8222-222222222222' and category_id='44444444-4444-4444-8444-444444444444') then raise exception 'Lost existing data'; end if;
 if (select status from business_categories where id='33333333-3333-4333-8333-333333333333')<>'disabled' then raise exception 'Lost visibility'; end if;
 begin delete from business_categories where id='22222222-2222-4222-8222-222222222222'; raise exception 'Referenced folder deleted'; exception when foreign_key_violation then null; end;
 begin delete from business_categories where id='44444444-4444-4444-8444-444444444444'; raise exception 'Referenced taxonomy deleted'; exception when foreign_key_violation then null; end;
 result:=write_global_category(null,null,'{"name":"Root"}',false);root:=(result->>'id')::uuid;
 result:=write_global_category(null,null,jsonb_build_object('name','Child','parent_id',root),false);child:=(result->>'id')::uuid;
 begin perform write_global_category(root,1,jsonb_build_object('parent_id',child),false);raise exception 'Cycle allowed';exception when check_violation then null;end;
 begin perform write_global_category(root,1,'{}',true);raise exception 'Parent deletion allowed';exception when foreign_key_violation then null;end;
 perform write_global_category(child,1,'{"name":"Renamed"}',false);
 begin perform write_global_category(child,1,'{"name":"Stale"}',false);raise exception 'Stale write allowed';exception when serialization_failure then null;end;
 -- Both item types and any business can use the same category.
 perform move_category_items('11111111-1111-4111-8111-111111111111','product',array['55555555-5555-4555-8555-555555555555']::uuid[],child);
 if (select subcategory from explore_products where id='55555555-5555-4555-8555-555555555555')<>'Renamed' then raise exception 'Rename not reflected';end if;
 perform write_global_category(root,1,'{"status":"disabled"}',false);
 if global_category_available(child) then raise exception 'Disabled ancestor available';end if;
 -- Updating unrelated fields or resubmitting the same disabled ID is allowed.
 update products set price=125,folder_category_id=child where id='55555555-5555-4555-8555-555555555555';
 begin update products set folder_category_id='33333333-3333-4333-8333-333333333333' where id='55555555-5555-4555-8555-555555555555';raise exception 'Disabled category accepted';exception when check_violation then null;end;
 begin update products set folder_category_id=gen_random_uuid() where id='55555555-5555-4555-8555-555555555555';raise exception 'Invalid category accepted';exception when check_violation then null;end;
 if exists(select 1 from explore_products where id='55555555-5555-4555-8555-555555555555') then raise exception 'Hidden ancestor leaked product';end if;
 result:=import_global_categories('[["Imported","Nested"],["Imported","Nested","Leaf"]]',true);
 if (result->>'created')::int<>3 or exists(select 1 from business_categories where name='Imported') then raise exception 'Preview mutated categories';end if;
 result:=import_global_categories('[["Imported","Nested"],["Imported","Nested","Leaf"]]',false);
 if (result->>'created')::int<>3 then raise exception 'Import failed';end if;
 result:=import_global_categories('[["imported","Nested"],["Imported","Nested","Leaf"]]',false);
 if (result->>'created')::int<>0 or (result->>'reused')::int<>3 then raise exception 'Path reuse failed';end if;
 -- Manual create preserves the legacy allowance for same-named categories.
 perform write_global_category(null,null,'{"name":"Original folder"}',false);
 result:=write_global_category(null,null,'{"name":"Unused"}',false);
 perform write_global_category((result->>'id')::uuid,1,'{}',true);
 begin perform move_category_items('11111111-1111-4111-8111-111111111111','product',array['55555555-5555-4555-8555-555555555555',gen_random_uuid()],null);raise exception 'Partial move allowed';exception when raise_exception then if sqlerrm='Partial move allowed' then raise;end if;end;
 if (select price from products where id='55555555-5555-4555-8555-555555555555')<>125 then raise exception 'Item data changed';end if;
end $$;
-- Direct database mutation bypass is denied even when the role has an owner JWT.
create or replace function auth.uid() returns uuid language sql stable as $$select 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'::uuid$$;
set role authenticated;
do $$ begin
 if (select count(*) from business_categories)<3 then raise exception 'Authenticated read denied';end if;
 begin insert into business_categories(name) values('Unauthorized');raise exception 'Unauthorized insert allowed';exception when insufficient_privilege then null;end;
 begin update business_categories set name='Unauthorized';raise exception 'Unauthorized update allowed';exception when insufficient_privilege then null;end;
 begin delete from business_categories;raise exception 'Unauthorized delete allowed';exception when insufficient_privilege then null;end;
 begin perform write_global_category(null,null,'{"name":"Unauthorized RPC"}',false);raise exception 'Unauthorized RPC allowed';exception when insufficient_privilege then null;end;
 begin perform import_global_categories('[["Unauthorized import"]]',false);raise exception 'Unauthorized import allowed';exception when insufficient_privilege then null;end;
end $$;
reset role;
set role anon;
do $$ begin
 begin perform count(*) from business_categories;raise exception 'Anonymous taxonomy read allowed';exception when insufficient_privilege then null;end;
end $$;
reset role;

-- Rerunning replacement must not restore a deliberately deleted imported category.
delete from public.business_categories where id='44444444-4444-4444-8444-444444444444';
\ir ../migrations/018_global_category_architecture.sql
do $$ begin
 if exists(select 1 from business_categories where id='44444444-4444-4444-8444-444444444444') then raise exception 'Rerun restored deleted imported category';end if;
 -- Business and gallery references independently block deletion.
 insert into business_categories(id,name) values('99999999-9999-4999-8999-999999999999','Referenced elsewhere');
 update businesses set global_category_id='99999999-9999-4999-8999-999999999999' where id='11111111-1111-4111-8111-111111111111';
 begin delete from business_categories where id='99999999-9999-4999-8999-999999999999';raise exception 'Business reference lost';exception when foreign_key_violation then null;end;
 update businesses set global_category_id=null where id='11111111-1111-4111-8111-111111111111';
 insert into gallery_photos(business_id,image_url,global_category_id,deleted_at) values('11111111-1111-4111-8111-111111111111','https://example.com/gallery.jpg','99999999-9999-4999-8999-999999999999',now());
 begin delete from business_categories where id='99999999-9999-4999-8999-999999999999';raise exception 'Archived gallery reference lost';exception when foreign_key_violation then null;end;
end $$;

-- Global status and hierarchy changes cannot bypass existing package publication rules.
do $$ declare root uuid; child uuid; enabled_parent uuid; begin
 select id into root from business_categories where name='Root';
 select id into child from business_categories where name='Renamed';
 enabled_parent:=(write_global_category(null,null,'{"name":"Enabled branch"}',false)->>'id')::uuid;
 update businesses set plan_id='basic' where id='11111111-1111-4111-8111-111111111111';
 begin update business_categories set status='enabled' where id=root;raise exception 'Global enabling bypassed package';
 exception when raise_exception then if sqlerrm not like '%requires Standard or Premium%' then raise;end if;end;
 begin update products set folder_category_id=null where id='55555555-5555-4555-8555-555555555555';raise exception 'Ancestor move bypassed package';
 exception when raise_exception then if sqlerrm not like '%requires Standard or Premium%' then raise;end if;end;
 begin update business_categories set parent_id=enabled_parent where id=child;raise exception 'Global reparenting bypassed package';
 exception when raise_exception then if sqlerrm not like '%requires Standard or Premium%' then raise;end if;end;
 if global_category_available(child) then raise exception 'Blocked package operation partially saved';end if;
 update businesses set plan_id='premium' where id='11111111-1111-4111-8111-111111111111';
 update business_categories set status='enabled' where id=root;
 if not global_category_available(child) then raise exception 'Eligible package cannot enable category';end if;
end $$;
