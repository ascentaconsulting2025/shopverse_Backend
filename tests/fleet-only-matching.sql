\set ON_ERROR_STOP on
\i 'shopverse_Backend/tests/whatsapp-order-database.sql'
\i 'shopverse_Backend/migrations/029_delivery_partner_drafts.sql'
\i 'shopverse_Backend/migrations/030_delivery_partner_availability.sql'
\i 'shopverse_Backend/migrations/031_delivery_partner_review.sql'
\i 'shopverse_Backend/migrations/033_delivery_partner_admin_controls.sql'
\i 'shopverse_Backend/migrations/034_logistics_operations.sql'
\i 'shopverse_Backend/migrations/046_fleet_only_matching.sql'
insert into auth.users values('00000000-0000-0000-0000-000000000004');
insert into delivery_partner_profiles(id,user_id,partner_type,verification_status,full_name,service_area,vehicle_type,max_active_orders,capacity_kg,capacity_litres) values('60000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000004','independent','approved','Rider','Pune','bike',3,20,40);
insert into delivery_partner_availability(partner_id,is_online,latitude,longitude,accuracy_m,location_recorded_at) values('60000000-0000-0000-0000-000000000001',true,18.5,73.8,10,now());
insert into marketplace_orders(id,customer_id,order_number,customer_name,customer_phone,delivery_address) values('40000000-0000-0000-0000-000000000010','00000000-0000-0000-0000-000000000001','FLEET-TEST-1','Customer','919876543210','Address'),('40000000-0000-0000-0000-000000000011','00000000-0000-0000-0000-000000000001','FLEET-TEST-2','Customer','919876543210','Address');
insert into marketplace_store_orders(id,order_id,business_id,business_name,store_order_number,status,confirmed_at) values('50000000-0000-0000-0000-000000000010','40000000-0000-0000-0000-000000000010','10000000-0000-0000-0000-000000000001','Shop','FLEET-TEST-1-1','ACCEPTED',now()),('50000000-0000-0000-0000-000000000011','40000000-0000-0000-0000-000000000011','10000000-0000-0000-0000-000000000001','Shop','FLEET-TEST-2-1','ACCEPTED',now());
insert into delivery_tasks(id,store_order_id,status,pickup_address,pickup_lat,pickup_lon,destination_address,destination_lat,destination_lon,service_area,package_description,weight_kg,volume_litres,eligible_vehicles,urgency,config,independent_deadline,created_by,fleet_only)
 select id,oid,'independent_allocation','Store',18.5,73.8,'Customer',18.51,73.81,'Pune','Products',w,v,array['bike'],'standard','{"location_max_age_seconds":300,"max_location_accuracy_m":100,"max_active_orders":3,"search_radii_km":[10],"weights":{"distance":40,"workload":30,"route":10,"availability":10,"vehicle":10}}',now()+interval '1 hour','00000000-0000-0000-0000-000000000002',fleet from (values('70000000-0000-0000-0000-000000000010'::uuid,'50000000-0000-0000-0000-000000000010'::uuid,null::numeric,null::numeric,true),('70000000-0000-0000-0000-000000000011'::uuid,'50000000-0000-0000-0000-000000000011'::uuid,1::numeric,1::numeric,false)) t(id,oid,w,v,fleet);
do $$ begin
 if (select count(*) from delivery_candidates('70000000-0000-0000-0000-000000000010'))<>1 then raise exception 'fleet-only candidate missing';end if;
 insert into delivery_assignments(task_id,partner_id,assignment_type,status) values('70000000-0000-0000-0000-000000000011','60000000-0000-0000-0000-000000000001','independent','accepted');
 if exists(select 1 from delivery_candidates('70000000-0000-0000-0000-000000000010')) then raise exception 'fleet-only task mixed with active task';end if;
 delete from delivery_assignments;
 insert into delivery_assignments(task_id,partner_id,assignment_type,status) values('70000000-0000-0000-0000-000000000010','60000000-0000-0000-0000-000000000001','independent','accepted');
 if exists(select 1 from delivery_candidates('70000000-0000-0000-0000-000000000011')) then raise exception 'legacy task mixed with unknown fleet load';end if;
end $$;
