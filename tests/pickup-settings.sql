\set ON_ERROR_STOP on
\i 'shopverse_Backend/tests/whatsapp-order-database.sql'
\i 'shopverse_Backend/migrations/040_pickup_settings.sql'
do $$ begin
 if (select lead_minutes from pickup_settings where id=true) <> 30 then raise exception 'incorrect default lead time'; end if;
 begin update pickup_settings set lead_minutes=-1 where id=true; raise exception 'invalid lead accepted'; exception when check_violation then null; end;
 if has_table_privilege('authenticated','public.pickup_settings','update') then raise exception 'unsafe pickup settings grant'; end if;
end $$;
