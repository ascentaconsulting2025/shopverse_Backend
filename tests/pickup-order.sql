\set ON_ERROR_STOP on
\i 'shopverse_Backend/tests/closing-price.sql'
\i 'shopverse_Backend/migrations/040_pickup_settings.sql'
\i 'shopverse_Backend/migrations/041_pickup_orders.sql'
update businesses set details='{"businessHours":{"days":{"en":"Mon - Sun"},"timings":{"en":"9:00 AM - 8:00 PM"},"timezone":"Asia/Kolkata"},"address":{"street":{"en":"Shop 1"},"city":{"en":"Pune"}}}' where id='10000000-0000-0000-0000-000000000001';
insert into customer_cart_items(customer_id,product_id,quantity) values('00000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001',2);
do $$ declare b record; result jsonb; replay jsonb; oid uuid; token uuid; start_at timestamptz:=now()+interval '2 hours'; begin
 select details into b from businesses where id='10000000-0000-0000-0000-000000000001';
 result:=place_pickup_store_request('00000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000004','Customer','919876543210','[{"id":"20000000-0000-0000-0000-000000000001","quantity":2,"price":10.50}]',start_at,start_at+interval '1 hour',b.details->'businessHours',b.details->'address','Shop 1, Pune',30);
 oid:=(result->>'store_order_id')::uuid;
 replay:=place_pickup_store_request('00000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000004','Customer','919876543210','[]',start_at,start_at+interval '1 hour',b.details->'businessHours',b.details->'address','Shop 1, Pune',30);
 if not (replay->>'replayed')::boolean or (replay->>'store_order_id')::uuid<>oid then raise exception 'pickup replay failed'; end if;
 if not exists(select 1 from marketplace_store_orders where id=oid and fulfillment_method='pickup' and pickup_start=start_at and pickup_end=start_at+interval '1 hour') then raise exception 'pickup slot missing'; end if;
 select edit_token into token from marketplace_store_orders where id=oid;
 if not confirm_reviewed_store_order(oid,'00000000-0000-0000-0000-000000000002',false,token,20) then raise exception 'pickup confirmation failed'; end if;
 if (select status from marketplace_store_orders where id=oid)<>'PROCESSING' then raise exception 'pickup did not enter preparation'; end if;
 if has_function_privilege('authenticated','public.place_pickup_store_request(uuid,uuid,uuid,text,text,jsonb,timestamptz,timestamptz,jsonb,jsonb,text,integer)','execute') then raise exception 'unsafe RPC privileges'; end if;
end $$;
