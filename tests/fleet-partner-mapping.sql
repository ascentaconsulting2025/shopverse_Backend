\set ON_ERROR_STOP on
\i 'shopverse_Backend/tests/fleet-types.sql'
\i 'shopverse_Backend/migrations/045_fleet_partner_mapping.sql'
do $$ declare bike uuid; truck uuid; begin
 select id into bike from fleet_types where code='bike';select id into truck from fleet_types where code='truck';
 if not exists(select 1 from fleet_partner_vehicle_labels where fleet_type_id=bike and vehicle_label='bike') then raise exception 'default mapping missing'; end if;
 begin insert into fleet_partner_vehicle_labels(fleet_type_id,vehicle_label) values(truck,'bike');raise exception 'duplicate mapping accepted';exception when unique_violation then null;end;
 begin insert into fleet_partner_vehicle_labels(fleet_type_id,vehicle_label) values(bike,' Bike ');raise exception 'unnormalized label accepted';exception when check_violation then null;end;
 if has_table_privilege('authenticated','public.fleet_partner_vehicle_labels','insert') then raise exception 'unsafe grants';end if;
end $$;
