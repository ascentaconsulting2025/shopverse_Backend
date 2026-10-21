-- Run only against a disposable database. Includes a minimal pre-migration schema.
create role anon;
create role authenticated;
create role service_role;
create table businesses(id uuid primary key, business_name text, slug text, category text, details jsonb default '{}', logo_url text,phone text,whatsapp_number text,address text,is_verified boolean default false,is_published boolean default true);
create table business_categories(id uuid primary key,business_id uuid,type text,name text,image_url text,is_published boolean default true);
create table business_section_visibility(business_id uuid,products boolean);
create table products(id uuid primary key,business_id uuid,name text,name_en text,name_mr text,description text,description_en text,description_mr text,price numeric,image_url text,is_available boolean,created_at timestamptz default now(),sort_order integer,category text,category_en text,folder_category_id uuid,is_published boolean default true);
\ir ../migrations/012_explore_catalog.sql
\ir ../migrations/012_explore_catalog.sql
insert into businesses(id,business_name,slug,category) values ('10000000-0000-4000-8000-000000000001','Test seller','test-seller','Jewellery');
insert into business_categories(id,business_id,type,name) values ('30000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000001','product','Gold Jewellery');
insert into products(id,business_id,name,price,is_available,folder_category_id) values ('20000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000001','Gold necklace',245000,false,'30000000-0000-4000-8000-000000000001');
do $$ begin
 if (select count(*) from explore_products) <> 1 then raise exception 'Published product missing'; end if;
 if (select available from explore_products limit 1) then raise exception 'Availability changed'; end if;
 if explore_facets()->0->>'subcategory' <> 'Gold Jewellery' then raise exception 'Folder category missing'; end if;
 if has_table_privilege('anon','explore_products','select') or has_table_privilege('authenticated','explore_products','select') then raise exception 'Direct catalog access granted'; end if;
 if has_function_privilege('anon','explore_facets()','execute') then raise exception 'Direct facets access granted'; end if;
end $$;
update business_categories set is_published=false;
do $$ begin if exists(select 1 from explore_products) then raise exception 'Hidden category exposed'; end if; end $$;
update business_categories set is_published=true;
update products set is_published=false;
do $$ begin if exists(select 1 from explore_products) then raise exception 'Draft product exposed'; end if; end $$;
update products set is_published=true;
update businesses set is_published=false;
do $$ begin if exists(select 1 from explore_products) then raise exception 'Hidden seller exposed'; end if; end $$;
update businesses set is_published=true;
insert into business_section_visibility values ('10000000-0000-4000-8000-000000000001',false);
do $$ begin if exists(select 1 from explore_products) then raise exception 'Hidden section exposed'; end if; end $$;
delete from business_section_visibility;
set role service_role;
select count(*) from explore_products;
select explore_facets();
reset role;

-- Services share business publication rules but never use product folders or stock.
alter table business_section_visibility add column services boolean;
create table services(id uuid primary key,business_id uuid,name text,name_en text,name_mr text,details text,details_en text,details_mr text,starting_price numeric,cover_image text,duration_en text,created_at timestamptz default now(),category_en text,folder_category_id uuid,is_published boolean default true);
\ir ../migrations/013_explore_services.sql
\ir ../migrations/013_explore_services.sql
insert into business_categories(id,business_id,type,name) values ('30000000-0000-4000-8000-000000000002','10000000-0000-4000-8000-000000000001','service','Cleaning');
insert into services(id,business_id,name,starting_price,duration_en,folder_category_id) values ('20000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000001','Deep cleaning',2499,'4 hours','30000000-0000-4000-8000-000000000002');
do $$ begin
 if (select count(*) from explore_services) <> 1 then raise exception 'Service missing'; end if;
 if (select specifications->>'Duration' from explore_services limit 1) <> '4 hours' then raise exception 'Duration missing'; end if;
 if (select available from explore_services limit 1) is not null then raise exception 'Invented service availability'; end if;
 if explore_service_facets()->0->>'subcategory' <> 'Cleaning' then raise exception 'Service folder missing'; end if;
 if has_table_privilege('anon','explore_services','select') or has_function_privilege('anon','explore_service_facets()','execute') then raise exception 'Service grants leaked'; end if;
end $$;
update services set folder_category_id='30000000-0000-4000-8000-000000000001';
do $$ begin if exists(select 1 from explore_services) then raise exception 'Product folder used for service'; end if; end $$;
update services set folder_category_id='30000000-0000-4000-8000-000000000002';
update business_categories set is_published=false where type='service';
do $$ begin if exists(select 1 from explore_services) then raise exception 'Hidden service folder exposed'; end if; end $$;
update business_categories set is_published=true;
update services set is_published=false;
do $$ begin if exists(select 1 from explore_services) then raise exception 'Draft service exposed'; end if; end $$;
update services set is_published=true;
insert into business_section_visibility(business_id,services) values ('10000000-0000-4000-8000-000000000001',false);
do $$ begin if exists(select 1 from explore_services) then raise exception 'Hidden service section exposed'; end if; end $$;
delete from business_section_visibility;
update businesses set is_published=false;
do $$ begin if exists(select 1 from explore_services) then raise exception 'Unpublished provider exposed'; end if; end $$;
update businesses set is_published=true;
set role service_role;
select explore_service_facets();
reset role;
