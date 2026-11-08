create extension if not exists pgcrypto;
create schema auth;
do $$ begin if not exists(select 1 from pg_roles where rolname='anon') then create role anon; end if; if not exists(select 1 from pg_roles where rolname='authenticated') then create role authenticated; end if; if not exists(select 1 from pg_roles where rolname='service_role') then create role service_role; end if; end $$;
create table auth.users(id uuid primary key);
create table businesses(id uuid primary key,owner_id uuid,business_name text,is_published boolean,details jsonb default '{}',whatsapp_number text);
create table products(id uuid primary key,business_id uuid references businesses(id),name text,name_en text,price numeric(12,2),is_available boolean,is_published boolean);
create view explore_products as select p.id from products p join businesses b on b.id=p.business_id where p.is_published and b.is_published;
\i 'shopverse_Backend/migrations/022_customer_cart.sql'
\i 'shopverse_Backend/migrations/023_store_orders.sql'
\i 'shopverse_Backend/migrations/024_whatsapp_order_requests.sql'
\i 'shopverse_Backend/migrations/025_remove_order_rejection.sql'
\i 'shopverse_Backend/migrations/026_reject_store_order.sql'
\i 'shopverse_Backend/migrations/027_admin_store_order_actions.sql'
insert into auth.users values ('00000000-0000-0000-0000-000000000001'),('00000000-0000-0000-0000-000000000002'),('00000000-0000-0000-0000-000000000003');
insert into businesses(id,owner_id,business_name,is_published,whatsapp_number) values ('10000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000002','Shop',true,'+919876543210');
insert into products(id,business_id,name,price,is_available,is_published) values ('20000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','Tea',10.50,true,true);
insert into customer_cart_items(customer_id,product_id,quantity) values ('00000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001',2);
select place_whatsapp_store_request('00000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001','Customer','919876543210','Address','[{"id":"20000000-0000-0000-0000-000000000001","quantity":2,"price":10.50}]');
do $$ declare oid uuid; begin
 select id into oid from marketplace_store_orders;
 if (select count(*) from customer_cart_items) <> 0 or (select subtotal from marketplace_store_orders where id=oid) <> 21 then raise exception 'incorrect cart or subtotal'; end if;
 if manage_store_order(oid,'00000000-0000-0000-0000-000000000003',false,'accept') then raise exception 'unauthorized confirm'; end if;
 if manage_store_order(oid,'00000000-0000-0000-0000-000000000003',false,'reject') then raise exception 'unauthorized reject'; end if;
 if not manage_store_order(oid,'00000000-0000-0000-0000-000000000002',false,'reject') then raise exception 'seller reject failed'; end if;
 if (select status from marketplace_store_orders where id=oid) <> 'REJECTED' or (select confirmed_at from marketplace_store_orders where id=oid) is not null then raise exception 'incorrect rejected order'; end if;
 if manage_store_order(oid,'00000000-0000-0000-0000-000000000002',false,'accept') then raise exception 'accepted rejected order'; end if;
 if (select count(*) from marketplace_order_status_history where store_order_id=oid and previous_status='PENDING' and new_status='REJECTED' and changed_by='00000000-0000-0000-0000-000000000002') <> 1 then raise exception 'rejection audit missing'; end if;
end $$;
select place_whatsapp_store_request('00000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001','Customer','919876543210','Address','[{"id":"20000000-0000-0000-0000-000000000001","quantity":2,"price":10.50}]');
do $$ begin if (select count(*) from marketplace_orders) <> 1 then raise exception 'duplicate order'; end if; end $$;
insert into customer_cart_items(customer_id,product_id,quantity) values ('00000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001',1);
do $$ begin
 begin
  perform place_whatsapp_store_request('00000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000002','Customer','919876543210','Address','[{"id":"20000000-0000-0000-0000-000000000001","quantity":1,"price":9.50}]');
  raise exception 'price mismatch was not rejected';
 exception when raise_exception then
  if sqlerrm <> 'Cart or price changed' then raise; end if;
 end;
 if (select count(*) from customer_cart_items) <> 1 or (select count(*) from marketplace_orders) <> 1 then raise exception 'failed request changed data'; end if;
end $$;
select place_whatsapp_store_request('00000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000003','Customer','919876543210','Address','[{"id":"20000000-0000-0000-0000-000000000001","quantity":1,"price":10.50}]');
do $$ declare oid uuid; begin
 select id into oid from marketplace_store_orders where status='PENDING' order by created_at desc limit 1;
 if not manage_store_order(oid,'00000000-0000-0000-0000-000000000003',true,'accept') then raise exception 'admin accept failed'; end if;
 if (select status from marketplace_store_orders where id=oid) <> 'ACCEPTED' or (select confirmed_at from marketplace_store_orders where id=oid) is null then raise exception 'confirmation not recorded'; end if;
 if manage_store_order(oid,'00000000-0000-0000-0000-000000000002',false,'reject') then raise exception 'rejected accepted order'; end if;
 if not exists(select 1 from marketplace_order_status_history where store_order_id=oid and changed_by='00000000-0000-0000-0000-000000000003' and new_status='ACCEPTED') then raise exception 'admin audit missing'; end if;
 if (select count(*) from marketplace_store_orders where confirmed_at is not null) <> 1 then raise exception 'confirmed order list is incorrect'; end if;
 if has_function_privilege('authenticated','public.manage_store_order(uuid,uuid,boolean,text)','execute') then raise exception 'authenticated role can spoof admin'; end if;
end $$;

insert into marketplace_orders(id,customer_id,order_number,customer_name,customer_phone,delivery_address) values ('40000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000001','ADMIN-TEST','Customer','919876543210','Address');
insert into marketplace_store_orders(id,order_id,business_id,business_name,store_order_number) values ('50000000-0000-0000-0000-000000000001','40000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','Shop','ADMIN-TEST-1');
do $$ begin
 if not manage_store_order('50000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000003',true,'reject') then raise exception 'admin reject failed'; end if;
 if not exists(select 1 from marketplace_order_status_history where store_order_id='50000000-0000-0000-0000-000000000001' and changed_by='00000000-0000-0000-0000-000000000003' and new_status='REJECTED') then raise exception 'admin rejection audit missing'; end if;
end $$;
