\set ON_ERROR_STOP on
\i 'shopverse_Backend/tests/pickup-order.sql'
create function public.delivery_select_order(uuid,uuid,boolean,jsonb) returns uuid language sql as $$ select 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'::uuid $$;
\i 'shopverse_Backend/migrations/044_pickup_logistics_guard.sql'
do $$ declare oid uuid; begin
 select so.id into oid from marketplace_orders o join marketplace_store_orders so on so.order_id=o.id where o.request_key='30000000-0000-0000-0000-000000000004';
 begin perform delivery_select_order(oid,'00000000-0000-0000-0000-000000000002',false,'{}');raise exception 'pickup entered logistics';
 exception when raise_exception then if sqlerrm<>'Self pickup orders cannot enter delivery allocation' then raise; end if; end;
 if delivery_select_order('50000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000002',false,'{}')<>'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' then raise exception 'legacy routing failed'; end if;
 if has_function_privilege('service_role','public.delivery_select_order_legacy(uuid,uuid,boolean,jsonb)','execute') then raise exception 'legacy bypass exposed'; end if;
end $$;
