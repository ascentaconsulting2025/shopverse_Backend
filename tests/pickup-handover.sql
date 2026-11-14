\set ON_ERROR_STOP on
\i 'shopverse_Backend/tests/pickup-order.sql'
create function public.delivery_notice(uuid,uuid,boolean,text,text) returns void language sql as $$ select $$;
\i 'shopverse_Backend/migrations/042_pickup_handover.sql'
do $$ declare oid uuid; result text; i integer; begin
 select so.id into oid from marketplace_orders o join marketplace_store_orders so on so.order_id=o.id where o.request_key='30000000-0000-0000-0000-000000000004';
 if pickup_mark_ready(oid,'00000000-0000-0000-0000-000000000003',false,gen_random_uuid(),repeat('a',64))<>'unavailable' then raise exception 'unauthorized ready'; end if;
 if pickup_mark_ready(oid,'00000000-0000-0000-0000-000000000002',false,gen_random_uuid(),repeat('a',64))<>'ready' then raise exception 'ready failed'; end if;
 for i in 1..4 loop if pickup_verify_handover(oid,'00000000-0000-0000-0000-000000000002',false,repeat('b',64))<>'invalid_code' then raise exception 'incorrect failure'; end if; end loop;
 if pickup_verify_handover(oid,'00000000-0000-0000-0000-000000000002',false,repeat('b',64))<>'locked' then raise exception 'lockout failed'; end if;
 if pickup_verify_handover(oid,'00000000-0000-0000-0000-000000000002',false,repeat('a',64))<>'locked' then raise exception 'lockout bypassed'; end if;
 update pickup_handover_codes set locked_until=now()-interval '1 second' where store_order_id=oid;
 if pickup_verify_handover(oid,'00000000-0000-0000-0000-000000000003',false,repeat('a',64))<>'unavailable' then raise exception 'unauthorized verification'; end if;
 if pickup_verify_handover(oid,'00000000-0000-0000-0000-000000000002',false,repeat('a',64))<>'completed' then raise exception 'verification failed'; end if;
 if not exists(select 1 from marketplace_store_orders where id=oid and status='DELIVERED') then raise exception 'order not completed'; end if;
 if not exists(select 1 from pickup_handover_codes where store_order_id=oid and consumed_at is not null and code_hash=repeat('0',64)) then raise exception 'code not consumed'; end if;
 if has_table_privilege('authenticated','public.pickup_handover_codes','select') then raise exception 'code storage exposed'; end if;
end $$;
