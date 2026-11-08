begin;
alter table public.marketplace_orders add column if not exists request_key uuid;
create unique index if not exists marketplace_orders_customer_request_key on public.marketplace_orders(customer_id,request_key) where request_key is not null;

-- A saved request is not a stock reservation or payment confirmation.
create or replace function public.place_whatsapp_store_request(p_customer uuid,p_store uuid,p_key uuid,p_name text,p_phone text,p_address text,p_expected jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare prior uuid; parent_id uuid; store_id uuid; reference text; b record; line record; total numeric(12,2); item_count integer;
begin
  if p_customer is null or p_store is null or p_key is null or length(trim(p_name)) not between 1 and 120 or p_phone !~ '^91[6-9][0-9]{9}$' or length(trim(p_address)) not between 1 and 500 or jsonb_typeof(p_expected) <> 'array' or jsonb_array_length(p_expected) not between 1 and 100 then
    raise exception 'Invalid request';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(p_customer::text || ':' || p_key::text,0));
  select id into prior from marketplace_orders where customer_id=p_customer and request_key=p_key;
  if prior is not null then
    select id into store_id from marketplace_store_orders where order_id=prior and business_id=p_store;
    if store_id is null then raise exception 'Request key already used'; end if;
    return jsonb_build_object('store_order_id',store_id,'replayed',true);
  end if;
  select id,business_name,coalesce(nullif(details->>'whatsapp',''),whatsapp_number) as whatsapp into b from businesses where id=p_store and is_published=true for share;
  if not found or b.whatsapp is null then raise exception 'Store unavailable'; end if;
  perform 1 from customer_cart_items c join products p on p.id=c.product_id where c.customer_id=p_customer and p.business_id=p_store order by p.id for update of c,p;
  select count(*),sum(p.price*c.quantity) into item_count,total from customer_cart_items c join products p on p.id=c.product_id where c.customer_id=p_customer and p.business_id=p_store;
  if item_count=0 or item_count <> jsonb_array_length(p_expected) then raise exception 'Cart changed'; end if;
  for line in select c.product_id,c.quantity,p.price,p.is_available,p.is_published from customer_cart_items c join products p on p.id=c.product_id where c.customer_id=p_customer and p.business_id=p_store loop
    if line.is_available is false or line.is_published is not true or not exists(select 1 from explore_products e where e.id=line.product_id) or not exists (select 1 from jsonb_array_elements(p_expected) x where x->>'id'=line.product_id::text and (x->>'quantity')::int=line.quantity and (x->>'price')::numeric is not distinct from line.price) then raise exception 'Cart or price changed'; end if;
  end loop;
  if (select count(distinct x->>'id') from jsonb_array_elements(p_expected) x) <> item_count then raise exception 'Invalid cart'; end if;
  reference := 'ORD-' || upper(replace(gen_random_uuid()::text,'-',''));
  insert into marketplace_orders(customer_id,order_number,customer_name,customer_phone,delivery_address,request_key) values(p_customer,reference,trim(p_name),p_phone,trim(p_address),p_key) returning id into parent_id;
  insert into marketplace_store_orders(order_id,business_id,business_name,store_order_number,subtotal) values(parent_id,b.id,b.business_name,reference || '-1',case when exists(select 1 from customer_cart_items c join products p on p.id=c.product_id where c.customer_id=p_customer and p.business_id=p_store and p.price is null) then null else total end) returning id into store_id;
  insert into marketplace_order_items(store_order_id,product_id,product_name,quantity,unit_price) select store_id,p.id,coalesce(nullif(p.name_en,''),p.name),c.quantity,p.price from customer_cart_items c join products p on p.id=c.product_id where c.customer_id=p_customer and p.business_id=p_store;
  delete from customer_cart_items c using products p where c.product_id=p.id and c.customer_id=p_customer and p.business_id=p_store;
  return jsonb_build_object('store_order_id',store_id,'replayed',false);
end $$;
revoke all on function public.place_whatsapp_store_request(uuid,uuid,uuid,text,text,text,jsonb) from public,anon,authenticated;
grant execute on function public.place_whatsapp_store_request(uuid,uuid,uuid,text,text,text,jsonb) to service_role;

commit;
