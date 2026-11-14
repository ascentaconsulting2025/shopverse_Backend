\set ON_ERROR_STOP on
\i 'shopverse_Backend/tests/whatsapp-order-database.sql'
\i 'shopverse_Backend/migrations/038_fleet_types.sql'
do $$ declare bike uuid; truck uuid; begin
 select id into bike from fleet_types where code='bike'; select id into truck from fleet_types where code='truck';
 if (select fleet_type_id from products limit 1) <> bike then raise exception 'existing product did not default to Bike'; end if;
 insert into products(id,business_id,name,price,is_available,is_published) values ('20000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000001','New',10,true,true);
 if (select fleet_type_id from products where id='20000000-0000-0000-0000-000000000002') <> bike then raise exception 'new product did not default to Bike'; end if;
 update fleet_types set active=false where id=truck;
 begin
  update products set fleet_type_id=truck where id='20000000-0000-0000-0000-000000000002'; raise exception 'inactive fleet accepted';
 exception when raise_exception then if sqlerrm <> 'Fleet type unavailable' then raise; end if; end;
 begin
  delete from fleet_types where id=bike; raise exception 'referenced fleet deleted';
 exception when foreign_key_violation then null; end;
 if has_table_privilege('authenticated','public.fleet_types','insert') then raise exception 'unsafe grants'; end if;
end $$;
