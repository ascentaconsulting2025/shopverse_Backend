\set ON_ERROR_STOP on
\i 'shopverse_Backend/tests/whatsapp-order-database.sql'
\i 'shopverse_Backend/migrations/036_pending_order_editing.sql'
insert into marketplace_orders(id,customer_id,order_number,customer_name,customer_phone,delivery_address) values ('40000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000001','EDIT-TEST','Customer','919876543210','Address');
insert into marketplace_store_orders(id,order_id,business_id,business_name,store_order_number,subtotal) values ('50000000-0000-0000-0000-000000000002','40000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000001','Shop','EDIT-TEST-1',10.50);
insert into marketplace_order_items(store_order_id,product_id,product_name,quantity,unit_price) values ('50000000-0000-0000-0000-000000000002','20000000-0000-0000-0000-000000000001','Tea',1,10.50);
do $$ declare old_token uuid; new_token uuid; oid uuid := '50000000-0000-0000-0000-000000000002'; begin
 select edit_token into old_token from marketplace_store_orders where id=oid;
 begin
  perform edit_pending_store_order(oid,'00000000-0000-0000-0000-000000000003',old_token,'[{"id":"20000000-0000-0000-0000-000000000001","quantity":2}]');
  raise exception 'unauthorized edit succeeded';
 exception when raise_exception then if sqlerrm <> 'Order unavailable' then raise; end if; end;
 perform edit_pending_store_order(oid,'00000000-0000-0000-0000-000000000001',old_token,'[{"id":"20000000-0000-0000-0000-000000000001","quantity":2}]');
 select edit_token into new_token from marketplace_store_orders where id=oid;
 if old_token=new_token or (select subtotal from marketplace_store_orders where id=oid) <> 21 or (select quantity from marketplace_order_items where store_order_id=oid) <> 2 then raise exception 'edit did not update snapshot'; end if;
 if (select store_order_number from marketplace_store_orders where id=oid) <> 'EDIT-TEST-1' then raise exception 'order ID changed'; end if;
 begin
  perform confirm_reviewed_store_order(oid,'00000000-0000-0000-0000-000000000002',false,old_token);
  raise exception 'stale confirmation succeeded';
 exception when raise_exception then if sqlerrm <> 'Order changed' then raise; end if; end;
 begin
  perform edit_pending_store_order(oid,'00000000-0000-0000-0000-000000000001',old_token,'[{"id":"20000000-0000-0000-0000-000000000001","quantity":1}]');
  raise exception 'stale edit succeeded';
 exception when raise_exception then if sqlerrm <> 'Order changed' then raise; end if; end;
 if not confirm_reviewed_store_order(oid,'00000000-0000-0000-0000-000000000002',false,new_token) then raise exception 'reviewed confirmation failed'; end if;
 begin
  perform edit_pending_store_order(oid,'00000000-0000-0000-0000-000000000001',new_token,'[{"id":"20000000-0000-0000-0000-000000000001","quantity":1}]');
  raise exception 'confirmed order was edited';
 exception when raise_exception then if sqlerrm <> 'Order changed' then raise; end if; end;
 if has_function_privilege('authenticated','public.edit_pending_store_order(uuid,uuid,uuid,jsonb)','execute') then raise exception 'unsafe RPC grants'; end if;
end $$;
