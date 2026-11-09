-- Isolated database only. Requires 023 and 029-034. All fixtures are rolled back.
\set ON_ERROR_STOP on
begin;
insert into auth.users(id) select ('da000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid from generate_series(1,8)n;
insert into businesses(id,owner_id) values('db000000-0000-4000-8000-000000000001','da000000-0000-4000-8000-000000000001');
insert into marketplace_orders(id,customer_id,order_number,customer_name,customer_phone,delivery_address)
 select ('dc000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,'da000000-0000-4000-8000-000000000002','TEST-'||n,'Test Customer','0000000000','Test destination' from generate_series(1,5)n;
insert into marketplace_store_orders(id,order_id,business_id,business_name,store_order_number,status,confirmed_at)
 select ('dd000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,('dc000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,'db000000-0000-4000-8000-000000000001','Test Store','STORE-'||n,'ACCEPTED',now() from generate_series(1,5)n;
insert into delivery_partner_profiles(id,user_id,partner_type,verification_status,full_name,service_area,vehicle_type,max_active_orders,capacity_kg,capacity_litres,employment_active,shift_start,shift_end)
 select ('de000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,('da000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,case when n=5 then 'salaried' else 'independent' end,'approved','Partner '||n,'North','bicycle',1,10,20,n=5,now()-interval '1 hour',now()+interval '8 hours' from generate_series(3,5)n;
insert into delivery_partner_availability(partner_id,is_online,latitude,longitude,accuracy_m,location_recorded_at)
 select id,true,18.5,73.8,10,now() from delivery_partner_profiles where id::text like 'de000000%';
do $$
declare seller uuid:='da000000-0000-4000-8000-000000000001'; customer uuid:='da000000-0000-4000-8000-000000000002'; p1 uuid:='da000000-0000-4000-8000-000000000003';p2 uuid:='da000000-0000-4000-8000-000000000004';employee uuid:='da000000-0000-4000-8000-000000000005'; t uuid;t2 uuid;t3 uuid;t4 uuid; details jsonb:='{"pickup_address":"Test pickup","pickup_lat":18.5,"pickup_lon":73.8,"destination_lat":18.51,"destination_lon":73.81,"service_area":"North","package_description":"Test package","weight_kg":2,"volume_litres":3,"eligible_vehicles":["bicycle"],"urgency":"standard"}';cfg jsonb:='{"enabled":true,"independent_timeout_seconds":120,"acknowledgement_timeout_seconds":60,"confirmation_timeout_seconds":300,"location_max_age_seconds":300,"max_location_accuracy_m":100,"max_active_orders":2,"search_radii_km":[1,5,10],"weights":{"distance":40,"workload":30,"route":10,"availability":10,"vehicle":10}}'; aid uuid;
begin
 if has_function_privilege('authenticated','public.delivery_manual_assign(uuid,uuid,uuid,text)','execute') then raise exception 'Unsafe function permissions';end if;
 begin perform delivery_select_order('dd000000-0000-4000-8000-000000000001',seller,false,details);raise exception 'Unconfigured allocation accepted';exception when raise_exception then if sqlerrm<>'Configure and enable allocation settings first' then raise;end if;end;
 perform delivery_save_settings(seller,cfg);
 begin perform delivery_select_order('dd000000-0000-4000-8000-000000000001',customer,false,details);raise exception 'Customer selected seller delivery';exception when raise_exception then if sqlerrm<>'Delivery access denied' then raise;end if;end;
 t:=delivery_select_order('dd000000-0000-4000-8000-000000000001',seller,false,details);
 if delivery_select_order('dd000000-0000-4000-8000-000000000001',seller,false,details)<>t then raise exception 'Selection not idempotent';end if;
 if jsonb_array_length(delivery_offers(p1))<>1 then raise exception 'Eligible offer missing';end if;
 if (delivery_offers(p1)->0) ? 'customer_phone' or (delivery_offers(p1)->0) ? 'destination_address' then raise exception 'Offer exposes customer';end if;
 begin perform delivery_manual_assign(t,'de000000-0000-4000-8000-000000000005',seller,'Test manual');raise exception 'Priority bypassed';exception when raise_exception then if sqlerrm not like 'Independent priority window%' then raise;end if;end;
 aid:=delivery_accept(t,p1);
 if delivery_accept(t,p1)<>aid then raise exception 'Accept not idempotent';end if;
 begin perform delivery_accept(t,p2);raise exception 'Duplicate winner';exception when raise_exception then if sqlerrm<>'Delivery no longer available' then raise;end if;end;
 t2:=delivery_select_order('dd000000-0000-4000-8000-000000000002',seller,false,details);
 if exists(select 1 from delivery_candidates(t2) where user_id=p1) then raise exception 'Capacity overrun';end if;
 begin perform delivery_customer_confirm(t,customer);raise exception 'Premature receipt';exception when raise_exception then if sqlerrm<>'Delivery is not awaiting your confirmation' then raise;end if;end;
 begin perform delivery_partner_transition(t,p2,'reached_pickup');raise exception 'Unassigned progress';exception when raise_exception then if sqlerrm<>'Delivery access denied' then raise;end if;end;
 perform delivery_partner_transition(t,p1,'reached_pickup');perform delivery_partner_transition(t,p1,'picked_up');
 begin perform delivery_admin_cancel(t,seller,'Test cancellation');raise exception 'Postpickup cancellation';exception when raise_exception then if sqlerrm<>'Cancellation is only allowed before pickup' then raise;end if;end;
 perform delivery_partner_transition(t,p1,'on_the_way');perform delivery_partner_transition(t,p1,'reached_customer');
 begin perform delivery_customer_confirm(t,p1);raise exception 'Partner confirmed receipt';exception when raise_exception then if sqlerrm<>'Delivery access denied' then raise;end if;end;
 update delivery_tasks set confirmation_deadline=now()-interval '1 second' where id=t;
 perform process_delivery_jobs();
 if not exists(select 1 from delivery_exceptions where task_id=t and code='customer_confirmation_overdue') then raise exception 'Missing confirmation exception';end if;
 perform delivery_customer_confirm(t,customer);perform delivery_customer_confirm(t,customer);
 if (select count(*) from delivery_compensation_records where task_id=t)<>1 then raise exception 'Completion duplicated';end if;
 if exists(select 1 from delivery_assignments where task_id=t and ended_at is null) then raise exception 'Capacity not released';end if;
 if (select status from marketplace_store_orders where id='dd000000-0000-4000-8000-000000000001')<>'DELIVERED' then raise exception 'Order not completed';end if;
 update delivery_tasks set independent_deadline=now()-interval '1 second' where id=t2;
 perform process_delivery_jobs();
 if (select status from delivery_tasks where id=t2)<>'assigned' then raise exception 'Salaried fallback failed';end if;
 update delivery_assignments set acknowledgement_deadline=now()-interval '1 second' where task_id=t2;
 perform process_delivery_jobs();
 if (select status from delivery_tasks where id=t2)<>'admin_intervention' then raise exception 'Exhaustion not escalated';end if;
 perform delivery_manual_assign(t2,'de000000-0000-4000-8000-000000000004',seller,'Test manual intervention');
 perform delivery_partner_transition(t2,p2,'acknowledge');
 perform delivery_admin_cancel(t2,seller,'Customer requested cancellation');
 perform set_delivery_partner_operational_state(p1,false,null,null,null);
 if (select latitude from delivery_partner_availability where partner_id='de000000-0000-4000-8000-000000000003') is not null then raise exception 'Offline GPS retained';end if;
 begin perform set_delivery_partner_operational_state(p1,null,18.5,73.8,10);raise exception 'Offline GPS accepted';exception when raise_exception then if sqlerrm<>'Go online before sharing location' then raise;end if;end;
 -- Aggregate cargo, not just order count, must fit the vehicle.
 update delivery_partner_profiles set max_active_orders=2,capacity_kg=3 where user_id=p2;
 t3:=delivery_select_order('dd000000-0000-4000-8000-000000000003',seller,false,details);
 perform delivery_accept(t3,p2);
 t4:=delivery_select_order('dd000000-0000-4000-8000-000000000004',seller,false,details);
 if exists(select 1 from delivery_candidates(t4) where user_id=p2) then raise exception 'Aggregate package weight exceeded';end if;
 -- A salaried rejection tries the next eligible employee rather than looping forever.
 insert into delivery_partner_profiles(id,user_id,partner_type,verification_status,full_name,service_area,vehicle_type,max_active_orders,capacity_kg,capacity_litres,employment_active,shift_start,shift_end)
 values('de000000-0000-4000-8000-000000000006','da000000-0000-4000-8000-000000000006','salaried','approved','Second employee','North','bicycle',1,10,20,true,now()-interval '1 hour',now()+interval '8 hours');
 insert into delivery_partner_availability(partner_id,is_online,latitude,longitude,accuracy_m,location_recorded_at) values('de000000-0000-4000-8000-000000000006',true,18.501,73.8,10,now());
 update delivery_tasks set independent_deadline=now()-interval '1 second' where id=t4;
 perform process_delivery_jobs();
 perform delivery_partner_transition(t4,employee,'reject','Vehicle breakdown');
 if (select partner_id from delivery_tasks where id=t4)<>'de000000-0000-4000-8000-000000000006' then raise exception 'Salaried rejection did not retry next partner';end if;
 perform delivery_partner_transition(t4,'da000000-0000-4000-8000-000000000006','acknowledge');
 perform delivery_admin_cancel(t4,seller,'End test delivery');
 perform delivery_configure_partner('de000000-0000-4000-8000-000000000003',seller,jsonb_build_object('partner_type','salaried','max_active_orders',1,'capacity_kg',10,'capacity_litres',20,'employee_id','TEST-EMPLOYEE','employment_active',true,'shift_start',now()-interval '2 hours','shift_end',now()-interval '1 hour'));
 begin perform set_delivery_partner_operational_state(p1,true,null,null,null);raise exception 'Offshift employee went online';exception when raise_exception then if sqlerrm<>'An active shift is required to go online' then raise;end if;end;
 raise notice 'PASS lifecycle, ownership, priority, capacity, fallback, timeout, confirmation, idempotency, privacy';
end $$;
rollback;
