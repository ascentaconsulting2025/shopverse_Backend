-- Run with psql -v ON_ERROR_STOP=1 -f tests/category-rerun.sql
-- Only on a fresh disposable database (creates roles and a minimal fixture schema).
\ir category-fixture.sql

-- Reproduce ERROR 42701: columns exist, but folder constraints do not.
alter table products add column folder_category_id uuid;
alter table services add column folder_category_id uuid;
\ir ../migrations/010_category_folders.sql

insert into businesses(id,owner_id,is_published) values
 ('11111111-1111-4111-8111-111111111111','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',true);
insert into business_categories(id,business_id,type,name) values
 ('33333333-3333-4333-8333-333333333333','11111111-1111-4111-8111-111111111111','product','Preserved category');
insert into products(id,business_id,name,folder_category_id) values
 ('66666666-6666-4666-8666-666666666666','11111111-1111-4111-8111-111111111111','Preserved product','33333333-3333-4333-8333-333333333333');
create temp table constraint_counts as select conrelid,count(*) total from pg_constraint
 where conrelid in ('products'::regclass,'services'::regclass,'business_categories'::regclass) group by conrelid;

-- Reapply the completed migration, with live assignments and existing policies/RPCs.
\ir ../migrations/010_category_folders.sql
\ir ../migrations/010_category_folders.sql

do $$ begin
 if exists(select 1 from constraint_counts c where c.total <> (select count(*) from pg_constraint p where p.conrelid=c.conrelid)) then raise exception 'Rerun duplicated constraints'; end if;
 if not exists(select 1 from products where name='Preserved product' and folder_category_id='33333333-3333-4333-8333-333333333333') then raise exception 'Rerun changed item data'; end if;
end $$;
delete from business_categories where id='33333333-3333-4333-8333-333333333333';
do $$ begin
 if not exists(select 1 from products where name='Preserved product' and folder_category_id is null) then raise exception 'Existing column did not receive SET NULL foreign key'; end if;
end $$;
delete from products;
delete from businesses;
\ir category-folders.sql
