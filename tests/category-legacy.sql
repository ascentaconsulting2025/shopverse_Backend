-- Fresh disposable database only: reproduce the inspected production taxonomy.
\ir category-fixture.sql
create table listing_categories (
 id uuid primary key, name text, image_url text, display_order integer, is_active boolean
);
alter table products add column category_id uuid references listing_categories(id);
alter table services add column category_id uuid references listing_categories(id);
insert into businesses values
 ('11111111-1111-4111-8111-111111111111','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',true),
 ('22222222-2222-4222-8222-222222222222','bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',true);
insert into listing_categories values ('33333333-3333-4333-8333-333333333333','Shared category','https://example.com/photo.png',5,true);
insert into products(id,business_id,name,category_id) values
 ('66666666-6666-4666-8666-666666666666','11111111-1111-4111-8111-111111111111','Original product','33333333-3333-4333-8333-333333333333'),
 ('77777777-7777-4777-8777-777777777777','22222222-2222-4222-8222-222222222222','Other product','33333333-3333-4333-8333-333333333333');
insert into services(id,business_id,name,category_id) values
 ('88888888-8888-4888-8888-888888888888','11111111-1111-4111-8111-111111111111','Original service','33333333-3333-4333-8333-333333333333');
\ir ../migrations/010_category_folders.sql
\ir ../migrations/010_category_folders.sql
do $$ begin
 if (select count(*) from business_categories)<>3 then raise exception 'Expected three independent imported folders'; end if;
 if exists(select 1 from products where category_id<>'33333333-3333-4333-8333-333333333333' or folder_category_id is null) then raise exception 'Legacy product assignment lost'; end if;
 if exists(select 1 from services where category_id<>'33333333-3333-4333-8333-333333333333' or folder_category_id is null) then raise exception 'Legacy service assignment lost'; end if;
 if exists(select 1 from business_categories where name<>'Shared category' or image_url<>'https://example.com/photo.png' or display_order<>5) then raise exception 'Category metadata lost'; end if;
end $$;
-- Intentionally unassign a product and delete a service folder, then rerun.
update products set folder_category_id=null where name='Original product';
delete from business_categories where type='service';
\ir ../migrations/010_category_folders.sql
do $$ begin
 if exists(select 1 from products where name='Original product' and folder_category_id is not null) then raise exception 'Rerun reversed intentional unassignment'; end if;
 if exists(select 1 from business_categories where type='service') then raise exception 'Rerun recreated deleted folder'; end if;
 if (select count(*) from products)<>2 or (select count(*) from services)<>1 or (select count(*) from listing_categories)<>1 then raise exception 'Legacy data was removed'; end if;
end $$;
-- Newly created business folders must work independently of the shared taxonomy.
insert into business_categories(id,business_id,type,name) values
 ('99999999-9999-4999-8999-999999999999','11111111-1111-4111-8111-111111111111','product','New folder');
select move_category_items('11111111-1111-4111-8111-111111111111','product',array['66666666-6666-4666-8666-666666666666']::uuid[],'99999999-9999-4999-8999-999999999999');
do $$ begin
 if not exists(select 1 from products where name='Original product' and category_id='33333333-3333-4333-8333-333333333333' and folder_category_id='99999999-9999-4999-8999-999999999999') then raise exception 'Move changed legacy taxonomy'; end if;
end $$;
