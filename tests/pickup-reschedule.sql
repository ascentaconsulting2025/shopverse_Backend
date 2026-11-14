\set ON_ERROR_STOP on
\i 'shopverse_Backend/tests/pickup-order.sql'
create function public.delivery_notice(uuid,uuid,boolean,text,text) returns void language sql as $$ select $$;
\i 'shopverse_Backend/migrations/043_pickup_rescheduling.sql'
do $$ declare oid uuid; proposal uuid; hours jsonb; old_start timestamptz; new_start timestamptz:=now()+interval '4 hours'; begin
 select so.id,so.pickup_start into oid,old_start from marketplace_orders o join marketplace_store_orders so on so.order_id=o.id where o.request_key='30000000-0000-0000-0000-000000000004';
 select details->'businessHours' into hours from businesses where id='10000000-0000-0000-0000-000000000001';
 begin
  perform pickup_propose_window(oid,'00000000-0000-0000-0000-000000000003',false,new_start,new_start+interval '1 hour',hours,30);
  raise exception 'unauthorized proposal succeeded';
 exception when raise_exception then if sqlerrm<>'Order unavailable' then raise; end if; end;
 proposal:=pickup_propose_window(oid,'00000000-0000-0000-0000-000000000002',false,new_start,new_start+interval '1 hour',hours,30);
 if (select pickup_start from marketplace_store_orders where id=oid)<>old_start then raise exception 'proposal changed original window'; end if;
 if pickup_respond_window(oid,proposal,'00000000-0000-0000-0000-000000000003',true,hours,30)<>'unavailable' then raise exception 'unauthorized acceptance'; end if;
 if pickup_respond_window(oid,proposal,'00000000-0000-0000-0000-000000000001',true,'{}',30)<>'changed' then raise exception 'changed hours accepted'; end if;
 if pickup_respond_window(oid,proposal,'00000000-0000-0000-0000-000000000001',true,hours,30)<>'accepted' then raise exception 'acceptance failed'; end if;
 if (select pickup_start from marketplace_store_orders where id=oid)<>new_start then raise exception 'accepted window missing'; end if;
 if pickup_respond_window(oid,proposal,'00000000-0000-0000-0000-000000000001',true,hours,30)<>'changed' then raise exception 'proposal accepted twice'; end if;
 if has_function_privilege('authenticated','public.pickup_propose_window(uuid,uuid,boolean,timestamptz,timestamptz,jsonb,integer)','execute') then raise exception 'unsafe RPC privilege'; end if;
end $$;
