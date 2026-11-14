\set ON_ERROR_STOP on
\i 'shopverse_Backend/tests/whatsapp-order-database.sql'
create function auth.uid() returns uuid language sql stable as $$ select null::uuid $$;
\i 'shopverse_Backend/migrations/028_customer_addresses.sql'
\i 'shopverse_Backend/migrations/029_delivery_partner_drafts.sql'
\i 'shopverse_Backend/migrations/030_delivery_partner_availability.sql'
\i 'shopverse_Backend/migrations/031_delivery_partner_review.sql'
\i 'shopverse_Backend/migrations/033_delivery_partner_admin_controls.sql'
\i 'shopverse_Backend/migrations/034_logistics_operations.sql'
\i 'shopverse_Backend/migrations/036_fulfillment_fleet_and_pickup.sql'
\i 'shopverse_Backend/migrations/047_delivery_checkout_allocation.sql'
update businesses set details='{"address":{"street":{"en":"Shop 1"},"city":{"en":"Pune"},"state":{"en":"Maharashtra"},"latitude":18.5,"longitude":73.8},"businessHours":{"days":{"en":"Mon - Sun"},"timings":{"en":"9:00 AM - 8:00 PM"},"timezone":"Asia/Kolkata"}}' where id='10000000-0000-0000-0000-000000000001';
insert into customer_addresses(id,user_id,full_name,phone_number,address_line_1,address_line_2,city,state,postal_code,country,address_type,latitude,longitude,is_default) values('80000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000001','Customer','9876543210','Road','Area','Pune','Maharashtra','411001','India','Home',18.51,73.81,true);
insert into customer_cart_items(customer_id,product_id,quantity) values('00000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001',2);
do $$ declare bike uuid; truck uuid; cfg jsonb; config jsonb; origin jsonb; dest jsonb; result jsonb; oid uuid; token uuid; task uuid; start_at timestamptz:=now()+interval '2 hours'; begin
 select id into bike from fleet_types where code='bike'; select id into truck from fleet_types where code='truck';
 config:=jsonb_build_object('postcodes',jsonb_build_array('411001'),'maxRadiusKm',10,'speeds',jsonb_build_object('urgent',jsonb_build_object('enabled',true,'base',20)),'fleetRates',jsonb_build_array(jsonb_build_object('fleetId',bike,'perKm',5),jsonb_build_object('fleetId',truck,'perKm',10)));
 perform save_delivery_pricing_config('00000000-0000-0000-0000-000000000002',config);
 select details->'address' into origin from businesses where id='10000000-0000-0000-0000-000000000001';
 select to_jsonb(a) into dest from customer_addresses a where id='80000000-0000-0000-0000-000000000001';
 result:=place_delivery_store_request('00000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000009','80000000-0000-0000-0000-000000000001','[{"id":"20000000-0000-0000-0000-000000000001","quantity":2,"price":10.50}]','urgent',bike,2,30,config,origin,dest);
 oid:=(result->>'store_order_id')::uuid;
 if not exists(select 1 from marketplace_store_orders where id=oid and fulfillment_method='urgent' and delivery_fee=30) then raise exception 'delivery placement failed'; end if;
 begin perform delivery_select_order(oid,'00000000-0000-0000-0000-000000000003',false,'{}');raise exception 'unauthorized delivery selection'; exception when raise_exception then if sqlerrm<>'Delivery access denied' then raise; end if;end;
 begin perform delivery_select_order(oid,'00000000-0000-0000-0000-000000000002',false,'{}');raise exception 'manual selection allowed'; exception when raise_exception then if sqlerrm<>'Delivery allocation starts automatically after confirmation' then raise; end if;end;
 select edit_token into token from marketplace_store_orders where id=oid;
 insert into products(id,business_id,name,price,is_available,is_published,fleet_type_id) values('20000000-0000-0000-0000-000000000009','10000000-0000-0000-0000-000000000001','Bulky',5,true,true,truck);
 perform edit_pending_store_order(oid,'00000000-0000-0000-0000-000000000001',token,'[{"id":"20000000-0000-0000-0000-000000000001","quantity":2},{"id":"20000000-0000-0000-0000-000000000009","quantity":1}]');
 if not exists(select 1 from marketplace_store_orders where id=oid and delivery_fleet_id=truck and delivery_fee=40) then raise exception 'edited cart did not refresh fleet quote'; end if;
 select edit_token into token from marketplace_store_orders where id=oid;
 update customer_addresses set latitude=18.52 where id='80000000-0000-0000-0000-000000000001';
 if not confirm_fulfillment_order(oid,'00000000-0000-0000-0000-000000000002',false,token,20,bike) then raise exception 'delivery confirmation failed'; end if;
 if not exists(select 1 from marketplace_store_orders so join marketplace_orders o on o.id=so.order_id where so.id=oid and so.delivery_fleet_id=bike and so.delivery_fee=round((20+ceil(delivery_distance_km(18.5,73.8,18.52,73.81)*10)/10*5)::numeric,2) and (o.delivery_address_snapshot->>'latitude')::numeric=18.52) then raise exception 'confirmation did not snapshot address or recalculate fleet charge'; end if;
 if not exists(select 1 from delivery_order_allocation_jobs where store_order_id=oid and status='queued') then raise exception 'allocation not queued'; end if;
 if process_delivery_order_allocation()<>0 then raise exception 'disabled allocation created task'; end if;
 if not exists(select 1 from delivery_order_allocation_jobs where store_order_id=oid and status='queued' and last_error is not null) then raise exception 'disabled worker did not preserve queued order'; end if;
 cfg:='{"enabled":true,"independent_timeout_seconds":120,"acknowledgement_timeout_seconds":60,"confirmation_timeout_seconds":300,"location_max_age_seconds":300,"max_location_accuracy_m":100,"max_active_orders":2,"search_radii_km":[1,5,10],"weights":{"distance":40,"workload":30,"route":10,"availability":10,"vehicle":10}}';
 perform delivery_save_settings('00000000-0000-0000-0000-000000000002',cfg);
 if process_delivery_order_allocation()<>1 then raise exception 'automatic allocation job failed'; end if;
 select id into task from delivery_tasks where store_order_id=oid and fleet_only and weight_kg is null and volume_litres is null and urgency='urgent';
 if task is null then raise exception 'fleet-only delivery task not created'; end if;
 if process_delivery_order_allocation()<>0 or (select count(*) from delivery_tasks where store_order_id=oid)<>1 then raise exception 'duplicate task created'; end if;
 if switch_delivery_to_pickup(oid,'00000000-0000-0000-0000-000000000001',start_at,start_at+interval '1 hour',(select details->'businessHours' from businesses where id='10000000-0000-0000-0000-000000000001'),origin,30)<>'unavailable' then raise exception 'early pickup switch accepted'; end if;
 update marketplace_store_orders set confirmed_at=now()-interval '25 hours' where id=oid;
 insert into delivery_partner_profiles(id,user_id,partner_type,verification_status) values('60000000-0000-0000-0000-000000000009','00000000-0000-0000-0000-000000000003','independent','approved');
 update delivery_tasks set partner_id='60000000-0000-0000-0000-000000000009',status='accepted' where id=task;
 if switch_delivery_to_pickup(oid,'00000000-0000-0000-0000-000000000001',start_at,start_at+interval '1 hour',(select details->'businessHours' from businesses where id='10000000-0000-0000-0000-000000000001'),origin,30)<>'assigned' then raise exception 'assigned delivery switched to pickup'; end if;
 update delivery_tasks set partner_id=null,status='independent_allocation' where id=task;
 if switch_delivery_to_pickup(oid,'00000000-0000-0000-0000-000000000001',start_at,start_at+interval '1 hour',(select details->'businessHours' from businesses where id='10000000-0000-0000-0000-000000000001'),origin,30)<>'switched' then raise exception 'pickup switch failed'; end if;
 if not exists(select 1 from marketplace_store_orders where id=oid and fulfillment_method='pickup' and delivery_fee=0 and status='PROCESSING') or (select status from delivery_tasks where id=task)<>'cancelled' then raise exception 'pickup conversion inconsistent'; end if;
end $$;
