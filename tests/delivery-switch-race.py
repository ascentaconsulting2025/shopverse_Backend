"""Run only against the disposable local DB produced by delivery-checkout-schema.sql."""
import concurrent.futures, subprocess, sys
name=sys.argv[1]
if not name.startswith('shopverse_delivery_flow_test') or not name.replace('_','').isalnum():
    raise SystemExit('Expected a disposable shopverse_delivery_flow_test* database')
args=['psql','-h','/tmp','-p','55439','-d',name,'-v','ON_ERROR_STOP=1','-At']
def sql(text): return subprocess.run(args,input=text,text=True,capture_output=True)
setup='''
insert into auth.users values('00000000-0000-0000-0000-000000000004');
insert into delivery_partner_profiles(id,user_id,partner_type,verification_status,full_name,service_area,vehicle_type,max_active_orders,capacity_kg,capacity_litres) values('60000000-0000-0000-0000-000000000010','00000000-0000-0000-0000-000000000004','independent','approved','Rider','Pune','bike',3,20,40);
insert into delivery_partner_availability(partner_id,is_online,latitude,longitude,accuracy_m,location_recorded_at) values('60000000-0000-0000-0000-000000000010',true,18.5,73.8,10,now());
insert into marketplace_orders(id,customer_id,order_number,customer_name,customer_phone,delivery_address) values('40000000-0000-0000-0000-000000000010','00000000-0000-0000-0000-000000000001','RACE-DELIVERY','Customer','919876543210','Address');
insert into marketplace_store_orders(id,order_id,business_id,business_name,store_order_number,status,confirmed_at,fulfillment_method) values('50000000-0000-0000-0000-000000000010','40000000-0000-0000-0000-000000000010','10000000-0000-0000-0000-000000000001','Shop','RACE-DELIVERY-1','ACCEPTED',now()-interval '25 hours','urgent');
insert into delivery_tasks(id,store_order_id,status,pickup_address,pickup_lat,pickup_lon,destination_address,destination_lat,destination_lon,service_area,package_description,weight_kg,volume_litres,eligible_vehicles,urgency,config,independent_deadline,created_by,fleet_only)
values('70000000-0000-0000-0000-000000000010','50000000-0000-0000-0000-000000000010','independent_allocation','Shop',18.5,73.8,'Address',18.51,73.81,'Pune','Order',null,null,array['bike'],'urgent','{"location_max_age_seconds":300,"max_location_accuracy_m":100,"max_active_orders":3,"search_radii_km":[10],"weights":{"distance":40,"workload":30,"route":10,"availability":10,"vehicle":10}}',now()+interval '1 hour','00000000-0000-0000-0000-000000000002',true);
select delivery_publish_offers('70000000-0000-0000-0000-000000000010');
'''
r=sql(setup)
assert r.returncode==0,r.stderr
accept="select delivery_accept('70000000-0000-0000-0000-000000000010','00000000-0000-0000-0000-000000000004');"
switch="select switch_delivery_to_pickup('50000000-0000-0000-0000-000000000010','00000000-0000-0000-0000-000000000001',now()+interval '2 hours',now()+interval '3 hours',(select details->'businessHours' from businesses where id='10000000-0000-0000-0000-000000000001'),(select details->'address' from businesses where id='10000000-0000-0000-0000-000000000001'),30);"
with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
    responses=list(pool.map(sql,[accept,switch]))
result=sql("select s.fulfillment_method,t.status,(select count(*) from delivery_assignments a where a.task_id=t.id and a.ended_at is null) from marketplace_store_orders s join delivery_tasks t on t.store_order_id=s.id where s.id='50000000-0000-0000-0000-000000000010'")
assert result.returncode==0,result.stderr
assert result.stdout.strip() in ('pickup|cancelled|0','urgent|accepted|1'),(result.stdout,[x.stderr for x in responses])
print('PASS: concurrent partner acceptance and pickup switch produce exactly one fulfillment path')
