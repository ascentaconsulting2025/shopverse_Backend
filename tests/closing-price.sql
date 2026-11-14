\set ON_ERROR_STOP on
\i 'shopverse_Backend/tests/pending-order-editing.sql'
\i 'shopverse_Backend/migrations/037_closing_price.sql'
insert into marketplace_orders(id,customer_id,order_number,customer_name,customer_phone,delivery_address) values ('40000000-0000-0000-0000-000000000003','00000000-0000-0000-0000-000000000001','PRICE-TEST','Customer','919876543210','Address');
insert into marketplace_store_orders(id,order_id,business_id,business_name,store_order_number,subtotal) values ('50000000-0000-0000-0000-000000000003','40000000-0000-0000-0000-000000000003','10000000-0000-0000-0000-000000000001','Shop','PRICE-TEST-1',21);
do $$ declare t uuid; oid uuid := '50000000-0000-0000-0000-000000000003'; bad numeric; begin
 select edit_token into t from marketplace_store_orders where id=oid;
 foreach bad in array array[0::numeric,-1,21.01,1.001] loop
  begin
   perform confirm_reviewed_store_order(oid,'00000000-0000-0000-0000-000000000002',false,t,bad);
   raise exception 'invalid price accepted';
  exception when raise_exception then if sqlerrm <> 'Invalid closing price' then raise; end if; end;
 end loop;
 if not confirm_reviewed_store_order(oid,'00000000-0000-0000-0000-000000000002',false,t,21) then raise exception 'valid price rejected'; end if;
 if (select closing_price from marketplace_store_orders where id=oid) <> 21 or (select status from marketplace_store_orders where id=oid) <> 'ACCEPTED' then raise exception 'confirmation not recorded'; end if;
 if has_function_privilege('authenticated','public.confirm_reviewed_store_order(uuid,uuid,boolean,uuid,numeric)','execute') then raise exception 'unsafe grants'; end if;
end $$;
