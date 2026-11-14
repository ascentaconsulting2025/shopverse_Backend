\set ON_ERROR_STOP on
\i 'shopverse_Backend/tests/fleet-types.sql'
\i 'shopverse_Backend/migrations/039_delivery_pricing.sql'
select save_delivery_pricing_config('00000000-0000-0000-0000-000000000002','{"example":true}');
do $$ begin
 if (select config from delivery_pricing_config where id=true) <> '{"example":true}'::jsonb then raise exception 'configuration not saved'; end if;
 if (select count(*) from delivery_pricing_config_history) <> 1 then raise exception 'audit missing'; end if;
 if has_function_privilege('authenticated','public.save_delivery_pricing_config(uuid,jsonb)','execute') then raise exception 'unsafe RPC grants'; end if;
 if has_table_privilege('authenticated','public.delivery_pricing_config','update') then raise exception 'unsafe table grants'; end if;
end $$;
