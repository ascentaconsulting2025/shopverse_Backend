-- Additive logistics core. Apply after 033. No historical order is enrolled automatically.
begin;
alter table public.delivery_partner_profiles
 add column max_active_orders integer check(max_active_orders between 1 and 50),
 add column capacity_kg numeric check(capacity_kg > 0 and capacity_kg <= 10000),
 add column capacity_litres numeric check(capacity_litres > 0 and capacity_litres <= 100000),
 add column employee_id text unique,
 add column employment_active boolean not null default false,
 add column shift_start timestamptz,
 add column shift_end timestamptz,
 add constraint delivery_partner_shift_pair check((shift_start is null and shift_end is null) or (shift_start is not null and shift_end > shift_start));
create table public.delivery_settings (
 id boolean primary key default true check(id), config jsonb, updated_by uuid references auth.users(id), updated_at timestamptz not null default now()
);
insert into public.delivery_settings(id) values(true);
create table public.delivery_settings_history (
 id uuid primary key default gen_random_uuid(), actor_id uuid references auth.users(id), old_config jsonb, new_config jsonb not null, created_at timestamptz not null default now()
);
create table public.delivery_tasks (
 id uuid primary key default gen_random_uuid(), store_order_id uuid not null unique references public.marketplace_store_orders(id) on delete restrict,
 status text not null check(status in ('independent_allocation','salaried_allocation','admin_intervention','assigned','accepted','reached_pickup','picked_up','on_the_way','awaiting_customer_confirmation','completed','cancelled')),
 partner_id uuid references public.delivery_partner_profiles(id), assignment_type text check(assignment_type in ('independent','salaried','manual')),
 pickup_address text not null, pickup_lat double precision not null check(pickup_lat between -90 and 90), pickup_lon double precision not null check(pickup_lon between -180 and 180),
 destination_address text not null, destination_lat double precision not null check(destination_lat between -90 and 90), destination_lon double precision not null check(destination_lon between -180 and 180),
 service_area text not null, package_description text not null, weight_kg numeric not null check(weight_kg>0), volume_litres numeric not null check(volume_litres>0), eligible_vehicles text[] not null check(cardinality(eligible_vehicles)>0), urgency text not null check(urgency in ('standard','urgent')),
 config jsonb not null, independent_deadline timestamptz not null, confirmation_deadline timestamptz,
 created_by uuid not null references auth.users(id), created_at timestamptz not null default now(), updated_at timestamptz not null default now(), completed_at timestamptz
);
create index delivery_tasks_status_due_idx on public.delivery_tasks(status,independent_deadline);
create index delivery_tasks_partner_idx on public.delivery_tasks(partner_id,status);
create table public.delivery_assignments (
 id uuid primary key default gen_random_uuid(), task_id uuid not null references public.delivery_tasks(id), partner_id uuid not null references public.delivery_partner_profiles(id),
 assignment_type text not null check(assignment_type in ('independent','salaried','manual')), status text not null check(status in ('awaiting_ack','accepted','expired','rejected','reassigned','completed','cancelled')),
 score numeric, assigned_at timestamptz not null default now(), acknowledged_at timestamptz, acknowledgement_deadline timestamptz, ended_at timestamptz
);
create unique index delivery_one_live_assignment on public.delivery_assignments(task_id) where ended_at is null;
create index delivery_assignment_workload_idx on public.delivery_assignments(partner_id) where ended_at is null;
create table public.delivery_allocation_attempts (
 id uuid primary key default gen_random_uuid(), task_id uuid not null references public.delivery_tasks(id), partner_id uuid not null references public.delivery_partner_profiles(id),
 kind text not null check(kind in ('independent','salaried')), status text not null check(status in ('offered','accepted','rejected','expired','unavailable')), score numeric, offered_at timestamptz not null default now(), responded_at timestamptz, expires_at timestamptz,
 unique(task_id,partner_id,kind)
);
create table public.delivery_status_history (
 id uuid primary key default gen_random_uuid(), task_id uuid not null references public.delivery_tasks(id), actor_id uuid references auth.users(id), event text not null, old_status text, new_status text, remarks text,
 latitude double precision check(latitude between -90 and 90), longitude double precision check(longitude between -180 and 180), created_at timestamptz not null default now()
);
create table public.delivery_exceptions (
 id uuid primary key default gen_random_uuid(), task_id uuid not null references public.delivery_tasks(id), code text not null, reason text not null, opened_by uuid references auth.users(id), created_at timestamptz not null default now(), resolved_by uuid references auth.users(id), resolved_at timestamptz, resolution text
);
create unique index delivery_open_exception_idx on public.delivery_exceptions(task_id,code) where resolved_at is null;
create table public.delivery_notifications (
 id uuid primary key default gen_random_uuid(), recipient_id uuid references auth.users(id), for_admin boolean not null default false, task_id uuid references public.delivery_tasks(id), message text not null, dedupe_key text not null unique, created_at timestamptz not null default now(), read_at timestamptz,
 check(recipient_id is not null or for_admin)
);
create index delivery_notification_user_idx on public.delivery_notifications(recipient_id,created_at desc);
create table public.delivery_compensation_records (
 id uuid primary key default gen_random_uuid(), task_id uuid not null unique references public.delivery_tasks(id), partner_id uuid not null references public.delivery_partner_profiles(id), partner_type text not null,
 completed_deliveries integer not null default 1 check(completed_deliveries=1), settlement_status text not null default 'deferred' check(settlement_status='deferred'), created_at timestamptz not null default now()
);
create table public.delivery_worker_health (id boolean primary key default true check(id), last_success_at timestamptz, processed integer);
insert into public.delivery_worker_health(id) values(true);
do $$ declare t text; begin foreach t in array array['delivery_settings','delivery_settings_history','delivery_tasks','delivery_assignments','delivery_allocation_attempts','delivery_status_history','delivery_exceptions','delivery_notifications','delivery_compensation_records','delivery_worker_health'] loop
 execute format('alter table public.%I enable row level security',t);
 execute format('revoke all on public.%I from public,anon,authenticated',t);
 execute format('grant all on public.%I to service_role',t);
 end loop; end $$;

create function public.delivery_distance_km(a double precision,b double precision,c double precision,d double precision) returns double precision language sql immutable strict set search_path=public as $$
 select 6371.0*2*asin(sqrt(least(1.0,power(sin(radians(c-a)/2),2)+cos(radians(a))*cos(radians(c))*power(sin(radians(d-b)/2),2))))
$$;
create function public.delivery_notice(p_task uuid,p_user uuid,p_admin boolean,p_message text,p_key text) returns void language sql security definer set search_path=public as $$
 insert into delivery_notifications(task_id,recipient_id,for_admin,message,dedupe_key) values(p_task,p_user,p_admin,p_message,p_key) on conflict(dedupe_key) do nothing
$$;
create function public.delivery_log(p_task uuid,p_actor uuid,p_event text,p_old text,p_new text,p_reason text default null) returns void language sql security definer set search_path=public as $$
 insert into delivery_status_history(task_id,actor_id,event,old_status,new_status,remarks,latitude,longitude)
 select p_task,p_actor,p_event,p_old,p_new,p_reason,a.latitude,a.longitude from (select 1) seed
 left join delivery_partner_profiles p on p.user_id=p_actor and p.id=(select partner_id from delivery_tasks where id=p_task)
 left join delivery_partner_availability a on a.partner_id=p.id and a.is_online and a.location_recorded_at>=now()-interval '5 minutes' 
$$;
create function public.delivery_raise_exception(p_task uuid,p_code text,p_reason text,p_actor uuid default null) returns void language plpgsql security definer set search_path=public as $$
declare x uuid;
begin
 insert into delivery_exceptions(task_id,code,reason,opened_by) values(p_task,p_code,p_reason,p_actor) on conflict(task_id,code) where resolved_at is null do nothing returning id into x;
 if x is not null then perform delivery_notice(p_task,null,true,p_reason,'exception:'||x); end if;
end $$;

-- Eligibility is rechecked under the partner lock when reserving capacity.
create function public.delivery_candidates(p_task uuid,p_type text default null) returns table(partner_id uuid,user_id uuid,full_name text,partner_type text,vehicle_type text,distance_km double precision,active_orders bigint,score double precision) language sql stable security definer set search_path=public as $$
 with eligible as (
 select p.id,p.user_id,p.full_name,p.partner_type,p.vehicle_type,
 delivery_distance_km(a.latitude,a.longitude,t.pickup_lat,t.pickup_lon) as distance_km,
 (select count(*) from delivery_assignments x where x.partner_id=p.id and x.ended_at is null) as workload,
 least(p.max_active_orders,(t.config->>'max_active_orders')::integer) as capacity,t.config,
 coalesce((select avg(delivery_distance_km(q.destination_lat,q.destination_lon,t.pickup_lat,t.pickup_lon))
   from delivery_assignments x join delivery_tasks q on q.id=x.task_id where x.partner_id=p.id and x.ended_at is null),
   delivery_distance_km(a.latitude,a.longitude,t.pickup_lat,t.pickup_lon)) as route_km
 from delivery_tasks t join marketplace_store_orders so on so.id=t.store_order_id join marketplace_orders o on o.id=so.order_id
 cross join delivery_partner_profiles p join delivery_partner_availability a on a.partner_id=p.id
 where t.id=p_task and p.verification_status='approved' and (p_type is null or p.partner_type=p_type)
 and p.user_id is distinct from o.customer_id and a.is_online and a.latitude is not null
 and a.location_recorded_at >= now()-make_interval(secs=>(t.config->>'location_max_age_seconds')::integer)
 and a.accuracy_m <= (t.config->>'max_location_accuracy_m')::numeric
 and lower(trim(p.service_area))=lower(trim(t.service_area)) and lower(trim(p.vehicle_type))=any(t.eligible_vehicles)
 and p.capacity_kg>=t.weight_kg+coalesce((select sum(q.weight_kg) from delivery_assignments x join delivery_tasks q on q.id=x.task_id where x.partner_id=p.id and x.ended_at is null),0)
 and p.capacity_litres>=t.volume_litres+coalesce((select sum(q.volume_litres) from delivery_assignments x join delivery_tasks q on q.id=x.task_id where x.partner_id=p.id and x.ended_at is null),0) and p.max_active_orders is not null
 and (p.partner_type='independent' or (p.employment_active and p.shift_start<=now() and p.shift_end>now()))
 ) select id,user_id,full_name,partner_type,vehicle_type,distance_km,workload,
 100*((config->'weights'->>'distance')::double precision/(1+distance_km)+
 (config->'weights'->>'workload')::double precision*(1-workload::double precision/capacity)+
 (config->'weights'->>'route')::double precision/(1+route_km)+
 (config->'weights'->>'availability')::double precision+(config->'weights'->>'vehicle')::double precision)/100
 from eligible where workload<capacity and distance_km <= (select max(value::double precision) from jsonb_array_elements_text(config->'search_radii_km'))
 order by 8 desc,6,1
$$;
create function public.delivery_publish_offers(p_task uuid) returns void language plpgsql security definer set search_path=public as $$
declare t delivery_tasks%rowtype; c record; offer uuid;
begin
 select * into t from delivery_tasks where id=p_task;
 if t.status<>'independent_allocation' or t.independent_deadline<=now() then return; end if;
 for c in select * from delivery_candidates(p_task,'independent') loop
  offer:=null;
  insert into delivery_allocation_attempts(task_id,partner_id,kind,status,score,expires_at) values(p_task,c.partner_id,'independent','offered',c.score,t.independent_deadline) on conflict do nothing returning id into offer;
  if offer is not null then perform delivery_notice(p_task,c.user_id,false,'A delivery opportunity is available.','offer:'||offer); end if;
 end loop;
end $$;

create function public.delivery_select_order(p_store_order uuid,p_actor uuid,p_admin boolean,p_details jsonb) returns uuid language plpgsql security definer set search_path=public as $$
declare so marketplace_store_orders%rowtype; o marketplace_orders%rowtype; cfg jsonb; result uuid;
begin
 perform pg_advisory_xact_lock(74901);
 select * into so from marketplace_store_orders where id=p_store_order for update;
 if not found or (p_admin is not true and not exists(select 1 from businesses where id=so.business_id and owner_id=p_actor)) then raise exception 'Delivery access denied'; end if;
 select id into result from delivery_tasks where store_order_id=so.id; if result is not null then return result; end if;
 if so.confirmed_at is null or so.status not in ('ACCEPTED','PROCESSING','READY_FOR_DISPATCH') then raise exception 'Confirm this seller order before selecting delivery'; end if;
 select config into cfg from delivery_settings where id;
 if cfg is null or not coalesce((cfg->>'enabled')::boolean,false) then raise exception 'Configure and enable allocation settings first'; end if;
 select * into o from marketplace_orders where id=so.order_id;
 if o.customer_id is null then raise exception 'Customer account required for receipt confirmation'; end if;
 insert into delivery_tasks(store_order_id,status,pickup_address,pickup_lat,pickup_lon,destination_address,destination_lat,destination_lon,service_area,package_description,weight_kg,volume_litres,eligible_vehicles,urgency,config,independent_deadline,created_by)
 values(so.id,'independent_allocation',p_details->>'pickup_address',(p_details->>'pickup_lat')::double precision,(p_details->>'pickup_lon')::double precision,o.delivery_address,(p_details->>'destination_lat')::double precision,(p_details->>'destination_lon')::double precision,p_details->>'service_area',p_details->>'package_description',(p_details->>'weight_kg')::numeric,(p_details->>'volume_litres')::numeric,array(select lower(trim(value)) from jsonb_array_elements_text(p_details->'eligible_vehicles')),p_details->>'urgency',cfg,now()+make_interval(secs=>(cfg->>'independent_timeout_seconds')::integer),p_actor) returning id into result;
 perform delivery_log(result,p_actor,'delivery_selected',null,'independent_allocation');
 perform delivery_publish_offers(result);
 return result;
end $$;

create function public.delivery_reserve(p_task uuid,p_partner uuid,p_type text,p_actor uuid) returns uuid language plpgsql security definer set search_path=public as $$
declare t delivery_tasks%rowtype; p delivery_partner_profiles%rowtype; c record; aid uuid; due timestamptz;
begin
 perform pg_advisory_xact_lock(74901);
 select * into t from delivery_tasks where id=p_task for update;
 select * into p from delivery_partner_profiles where id=p_partner for update;
 select * into c from delivery_candidates(p_task,null) where partner_id=p_partner;
 if not found then raise exception 'Partner is no longer eligible'; end if;
 if exists(select 1 from delivery_assignments where task_id=p_task and ended_at is null) then raise exception 'Delivery no longer available'; end if;
 due:=now()+make_interval(secs=>(t.config->>'acknowledgement_timeout_seconds')::integer);
 insert into delivery_assignments(task_id,partner_id,assignment_type,status,score,acknowledgement_deadline,acknowledged_at)
 values(p_task,p_partner,p_type,case when p_type='independent' then 'accepted' else 'awaiting_ack' end,c.score,case when p_type='independent' then null else due end,case when p_type='independent' then now() else null end) returning id into aid;
 update delivery_tasks set partner_id=p_partner,assignment_type=p_type,status=case when p_type='independent' then 'accepted' else 'assigned' end,updated_at=now() where id=p_task;
 perform delivery_log(p_task,p_actor,'partner_assigned',t.status,case when p_type='independent' then 'accepted' else 'assigned' end,p_type);
 perform delivery_notice(p_task,p.user_id,false,'Delivery assigned. Open your active deliveries.','assignment:'||aid);
 perform delivery_notice(p_task,o.customer_id,false,'A delivery partner has been assigned.','customer-assignment:'||aid) from marketplace_orders o join marketplace_store_orders so on so.order_id=o.id where so.id=t.store_order_id;
 perform delivery_notice(p_task,b.owner_id,false,'A delivery partner has been assigned.','seller-assignment:'||aid) from businesses b join marketplace_store_orders so on so.business_id=b.id where so.id=t.store_order_id and b.owner_id is not null;
 return aid;
end $$;
create function public.delivery_accept(p_task uuid,p_user uuid) returns uuid language plpgsql security definer set search_path=public as $$
declare t delivery_tasks%rowtype; pid uuid; aid uuid;
begin
 perform pg_advisory_xact_lock(74901);
 select * into t from delivery_tasks where id=p_task for update;
 select id into pid from delivery_partner_profiles where user_id=p_user and partner_type='independent';
 if t.partner_id=pid and t.status='accepted' then select id into aid from delivery_assignments where task_id=p_task and ended_at is null; return aid; end if;
 if t.id is null or t.status<>'independent_allocation' or t.independent_deadline<=now() or pid is null then raise exception 'Delivery no longer available'; end if;
 if exists(select 1 from delivery_allocation_attempts where task_id=p_task and partner_id=pid and kind='independent' and status='rejected') then raise exception 'Offer was declined'; end if;
 aid:=delivery_reserve(p_task,pid,'independent',p_user);
 insert into delivery_allocation_attempts(task_id,partner_id,kind,status,responded_at) values(p_task,pid,'independent','accepted',now()) on conflict(task_id,partner_id,kind) do update set status='accepted',responded_at=now();
 update delivery_allocation_attempts set status='unavailable',responded_at=now() where task_id=p_task and partner_id<>pid and status='offered';
 return aid;
end $$;
create function public.delivery_decline(p_task uuid,p_user uuid) returns void language plpgsql security definer set search_path=public as $$
declare pid uuid;
begin
 perform pg_advisory_xact_lock(74901);
 select id into pid from delivery_partner_profiles where user_id=p_user and partner_type='independent';
 if pid is null or not exists(select 1 from delivery_tasks where id=p_task and status='independent_allocation' and independent_deadline>now()) or not exists(select 1 from delivery_candidates(p_task,'independent') where partner_id=pid) then raise exception 'Offer unavailable'; end if;
 insert into delivery_allocation_attempts(task_id,partner_id,kind,status,responded_at) values(p_task,pid,'independent','rejected',now()) on conflict(task_id,partner_id,kind) do update set status='rejected',responded_at=now();
 perform delivery_log(p_task,p_user,'offer_declined',null,null);
end $$;
create function public.delivery_fallback(p_task uuid) returns void language plpgsql security definer set search_path=public as $$
declare t delivery_tasks%rowtype; c record; radius double precision; aid uuid;
begin
 select * into t from delivery_tasks where id=p_task for update;
 if t.status<>'salaried_allocation' or t.independent_deadline>now() then return; end if;
 for radius in select value::double precision from jsonb_array_elements_text(t.config->'search_radii_km') order by 1 loop
  for c in select * from delivery_candidates(p_task,'salaried') x where distance_km<=radius and not exists(select 1 from delivery_allocation_attempts a where a.task_id=p_task and a.partner_id=x.partner_id and a.kind='salaried') loop
   begin
    aid:=delivery_reserve(p_task,c.partner_id,'salaried',null);
    insert into delivery_allocation_attempts(task_id,partner_id,kind,status,score,expires_at) select p_task,c.partner_id,'salaried','offered',c.score,acknowledgement_deadline from delivery_assignments where id=aid;
    return;
   exception when raise_exception then
    if sqlerrm <> 'Partner is no longer eligible' then raise; end if;
   end;
  end loop;
 end loop;
 update delivery_tasks set status='admin_intervention',partner_id=null,updated_at=now() where id=p_task;
 perform delivery_log(p_task,null,'allocation_exhausted',t.status,'admin_intervention');
 perform delivery_raise_exception(p_task,'unassigned','No eligible salaried partner is available.');
end $$;
create function public.process_delivery_jobs() returns integer language plpgsql security definer set search_path=public as $$
declare t delivery_tasks%rowtype; a delivery_assignments%rowtype; n integer:=0; p delivery_partner_profiles%rowtype;
begin
 -- Across all server instances: one short database transaction owns allocation.
 if not pg_try_advisory_xact_lock(74901) then return 0; end if;
 for t in select * from delivery_tasks where status in ('independent_allocation','salaried_allocation','assigned','accepted','reached_pickup','picked_up','on_the_way','awaiting_customer_confirmation') order by updated_at limit 200 for update skip locked loop
  n:=n+1;
  if t.status='independent_allocation' then
   if t.independent_deadline<=now() then
    update delivery_allocation_attempts set status='expired',responded_at=now() where task_id=t.id and status='offered';
    update delivery_tasks set status='salaried_allocation',updated_at=now() where id=t.id;
    perform delivery_log(t.id,null,'independent_window_expired','independent_allocation','salaried_allocation');
    perform delivery_fallback(t.id);
   else perform delivery_publish_offers(t.id); end if;
  elsif t.status='salaried_allocation' then perform delivery_fallback(t.id);
  elsif t.status='assigned' then
   select * into a from delivery_assignments where task_id=t.id and ended_at is null;
   select * into p from delivery_partner_profiles where id=t.partner_id;
   if a.acknowledgement_deadline<=now() or p.verification_status<>'approved' then
    update delivery_assignments set status='expired',ended_at=now() where id=a.id;
    update delivery_allocation_attempts set status='expired',responded_at=now() where task_id=t.id and partner_id=t.partner_id and status='offered';
    update delivery_tasks set status='salaried_allocation',partner_id=null,updated_at=now() where id=t.id;
    perform delivery_log(t.id,null,'acknowledgement_expired','assigned','salaried_allocation');
    perform delivery_fallback(t.id);
   end if;
  elsif t.status='awaiting_customer_confirmation' and t.confirmation_deadline<=now() then
   perform delivery_raise_exception(t.id,'customer_confirmation_overdue','Customer has not confirmed receipt.');
  end if;
  if exists(select 1 from delivery_tasks current_task join delivery_partner_profiles current_profile on current_profile.id=current_task.partner_id where current_task.id=t.id and current_profile.verification_status<>'approved') then
   perform delivery_raise_exception(t.id,'partner_unavailable','Assigned partner is no longer approved; administrator intervention required.');
  end if;
  -- Rotate scanned rows fairly when the queue exceeds the batch size.
  update delivery_tasks set updated_at=now() where id=t.id;
 end loop;
 insert into delivery_worker_health(id,last_success_at,processed) values(true,now(),n) on conflict(id) do update set last_success_at=now(),processed=n;
 return n;
end $$;

create function public.delivery_partner_transition(p_task uuid,p_user uuid,p_action text,p_reason text default null) returns void language plpgsql security definer set search_path=public as $$
declare t delivery_tasks%rowtype; p delivery_partner_profiles%rowtype; a delivery_assignments%rowtype; next_status text;
begin
 perform pg_advisory_xact_lock(74901);
 select * into t from delivery_tasks where id=p_task for update;
 select * into p from delivery_partner_profiles where user_id=p_user;
 if t.id is null or p.id is null or t.partner_id is distinct from p.id or p.verification_status<>'approved' then raise exception 'Delivery access denied'; end if;
 select * into a from delivery_assignments where task_id=t.id and ended_at is null for update;
 if a.id is null then raise exception 'No active assignment'; end if;
 if p_action='reject' then
  if t.status not in ('assigned','accepted','reached_pickup') or length(trim(coalesce(p_reason,'')))=0 then raise exception 'Report an exception after pickup; a reason is required'; end if;
  update delivery_assignments set status='rejected',ended_at=now() where id=a.id;
  update delivery_allocation_attempts set status='rejected',responded_at=now() where task_id=t.id and partner_id=p.id;
  update delivery_tasks set status='admin_intervention',partner_id=null,updated_at=now() where id=t.id;
  perform delivery_log(t.id,p_user,'partner_cancelled',t.status,'admin_intervention',p_reason);
  perform delivery_raise_exception(t.id,'partner_cancelled',p_reason,p_user);
  if a.assignment_type='salaried' then
   update delivery_tasks set status='salaried_allocation' where id=t.id;
   perform delivery_fallback(t.id);
  end if;
  return;
 end if;
 next_status:=case
 when p_action='acknowledge' and t.status='assigned' and a.acknowledgement_deadline>now() then 'accepted'
 when p_action='reached_pickup' and t.status='accepted' then 'reached_pickup'
 when p_action='picked_up' and t.status='reached_pickup' then 'picked_up'
 when p_action='on_the_way' and t.status='picked_up' then 'on_the_way'
 when p_action='reached_customer' and t.status='on_the_way' then 'awaiting_customer_confirmation' else null end;
 if next_status is null then raise exception 'Invalid or expired delivery transition'; end if;
 if p_action='acknowledge' then
  update delivery_assignments set status='accepted',acknowledged_at=now() where id=a.id;
  update delivery_allocation_attempts set status='accepted',responded_at=now() where task_id=t.id and partner_id=p.id and status='offered';
 end if;
 update delivery_tasks set status=next_status,updated_at=now(),confirmation_deadline=case when next_status='awaiting_customer_confirmation' then now()+make_interval(secs=>(config->>'confirmation_timeout_seconds')::integer) else confirmation_deadline end where id=t.id;
 perform delivery_log(t.id,p_user,p_action,t.status,next_status,p_reason);
 if next_status='on_the_way' then
  insert into marketplace_order_status_history(store_order_id,previous_status,new_status,changed_by) select id,status,'OUT_FOR_DELIVERY',p_user from marketplace_store_orders where id=t.store_order_id;
  update marketplace_store_orders set status='OUT_FOR_DELIVERY' where id=t.store_order_id;
 end if;
 if next_status in ('picked_up','on_the_way','awaiting_customer_confirmation') then
  perform delivery_notice(t.id,o.customer_id,false,case when next_status='awaiting_customer_confirmation' then 'Your partner has arrived. Confirm receipt after receiving your order.' else 'Delivery update: '||replace(next_status,'_',' ') end,'customer-status:'||t.id||':'||next_status) from marketplace_orders o join marketplace_store_orders so on so.order_id=o.id where so.id=t.store_order_id;
 end if;
end $$;
create function public.delivery_customer_confirm(p_task uuid,p_user uuid) returns void language plpgsql security definer set search_path=public as $$
declare t delivery_tasks%rowtype; so marketplace_store_orders%rowtype; p delivery_partner_profiles%rowtype;
begin
 perform pg_advisory_xact_lock(74901);
 select * into t from delivery_tasks where id=p_task for update;
 select * into so from marketplace_store_orders where id=t.store_order_id;
 if t.id is null or not exists(select 1 from marketplace_orders where id=so.order_id and customer_id=p_user) then raise exception 'Delivery access denied'; end if;
 if t.status='completed' then return; end if;
 if t.status<>'awaiting_customer_confirmation' then raise exception 'Delivery is not awaiting your confirmation'; end if;
 select * into p from delivery_partner_profiles where id=t.partner_id;
 if p.user_id=p_user then raise exception 'Partner cannot confirm customer receipt'; end if;
 update delivery_tasks set status='completed',completed_at=now(),updated_at=now() where id=t.id;
 update delivery_assignments set status='completed',ended_at=now() where task_id=t.id and ended_at is null;
 update marketplace_store_orders set status='DELIVERED' where id=so.id;
 insert into marketplace_order_status_history(store_order_id,previous_status,new_status,changed_by) values(so.id,so.status,'DELIVERED',p_user);
 perform delivery_log(t.id,p_user,'customer_confirmed',t.status,'delivered');
 perform delivery_log(t.id,p_user,'delivery_completed','delivered','completed');
 insert into delivery_compensation_records(task_id,partner_id,partner_type) values(t.id,p.id,p.partner_type) on conflict(task_id) do nothing;
 update delivery_exceptions set resolved_at=now(),resolved_by=p_user,resolution='Customer confirmed receipt' where task_id=t.id and code='customer_confirmation_overdue' and resolved_at is null;
 perform delivery_notice(t.id,p.user_id,false,'Customer confirmed receipt. Delivery completed.','completed-partner:'||t.id);
 perform delivery_notice(t.id,p_user,false,'Delivery completed. Thank you for confirming receipt.','completed-customer:'||t.id);
 perform delivery_notice(t.id,b.owner_id,false,'Delivery completed.','completed-seller:'||t.id) from businesses b where b.id=so.business_id and b.owner_id is not null;
end $$;
create function public.delivery_manual_assign(p_task uuid,p_partner uuid,p_actor uuid,p_reason text) returns uuid language plpgsql security definer set search_path=public as $$
declare t delivery_tasks%rowtype; aid uuid;
begin
 perform pg_advisory_xact_lock(74901);
 select * into t from delivery_tasks where id=p_task for update;
 if t.id is null or t.status not in ('admin_intervention','salaried_allocation','assigned','accepted','reached_pickup') or t.independent_deadline>now() then raise exception 'Independent priority window must finish; reassignment is allowed only before pickup'; end if;
 if length(trim(coalesce(p_reason,'')))=0 then raise exception 'Reason required'; end if;
 if t.partner_id=p_partner then raise exception 'Partner is already assigned'; end if;
 perform delivery_notice(t.id,p.user_id,false,'This delivery has been reassigned by an administrator.','reassigned:'||a.id) from delivery_assignments a join delivery_partner_profiles p on p.id=a.partner_id where a.task_id=t.id and a.ended_at is null;
 update delivery_allocation_attempts set status='unavailable',responded_at=now() where task_id=t.id and status='offered';
 update delivery_assignments set status='reassigned',ended_at=now() where task_id=t.id and ended_at is null;
 aid:=delivery_reserve(t.id,p_partner,'manual',p_actor);
 perform delivery_log(t.id,p_actor,'manual_assignment',t.status,'assigned',p_reason);
 update delivery_exceptions set resolved_at=now(),resolved_by=p_actor,resolution=p_reason where task_id=t.id and code in ('unassigned','partner_cancelled') and resolved_at is null;
 return aid;
end $$;
create function public.delivery_admin_cancel(p_task uuid,p_actor uuid,p_reason text) returns void language plpgsql security definer set search_path=public as $$
declare t delivery_tasks%rowtype;
begin
 perform pg_advisory_xact_lock(74901);
 select * into t from delivery_tasks where id=p_task for update;
 if t.id is null or t.status in ('picked_up','on_the_way','awaiting_customer_confirmation','completed','cancelled') then raise exception 'Cancellation is only allowed before pickup'; end if;
 if length(trim(coalesce(p_reason,'')))=0 then raise exception 'Reason required'; end if;
 perform delivery_notice(t.id,p.user_id,false,'This delivery has been cancelled by an administrator.','cancelled-partner:'||t.id) from delivery_partner_profiles p where p.id=t.partner_id;
 update delivery_assignments set status='cancelled',ended_at=now() where task_id=t.id and ended_at is null;
 update delivery_allocation_attempts set status='unavailable',responded_at=now() where task_id=t.id and status='offered';
 update delivery_tasks set status='cancelled',updated_at=now() where id=t.id;
 perform delivery_log(t.id,p_actor,'delivery_cancelled',t.status,'cancelled',p_reason);
 perform delivery_notice(t.id,o.customer_id,false,'Delivery allocation cancelled. Please contact the seller.','cancelled-customer:'||t.id) from marketplace_orders o join marketplace_store_orders so on so.order_id=o.id where so.id=t.store_order_id;
end $$;

create function public.delivery_save_settings(p_actor uuid,p_config jsonb) returns void language plpgsql security definer set search_path=public as $$
declare old jsonb;
begin
 perform pg_advisory_xact_lock(74901);
 select config into old from delivery_settings where id for update;
 update delivery_settings set config=p_config,updated_by=p_actor,updated_at=now() where id;
 insert into delivery_settings_history(actor_id,old_config,new_config) values(p_actor,old,p_config);
end $$;
create function public.delivery_configure_partner(p_partner uuid,p_actor uuid,p_data jsonb) returns void language plpgsql security definer set search_path=public as $$
declare p delivery_partner_profiles%rowtype;
begin
 perform pg_advisory_xact_lock(74901);
 select * into p from delivery_partner_profiles where id=p_partner for update;
 if not found or p.verification_status<>'approved' then raise exception 'Approved profile required'; end if;
 if exists(select 1 from delivery_assignments where partner_id=p.id and ended_at is null) then raise exception 'Finish active deliveries before changing partner configuration'; end if;
 update delivery_partner_profiles set partner_type=p_data->>'partner_type',max_active_orders=(p_data->>'max_active_orders')::integer,
 capacity_kg=(p_data->>'capacity_kg')::numeric,capacity_litres=(p_data->>'capacity_litres')::numeric,
 employee_id=nullif(p_data->>'employee_id',''),employment_active=(p_data->>'employment_active')::boolean,
 shift_start=(p_data->>'shift_start')::timestamptz,shift_end=(p_data->>'shift_end')::timestamptz,updated_at=now() where id=p.id;
 insert into delivery_partner_availability(partner_id,is_online) values(p.id,false) on conflict(partner_id) do update set is_online=false;
 insert into delivery_partner_verifications(partner_id,actor_id,previous_status,new_status,reason) values(p.id,p_actor,p.verification_status,p.verification_status,'Operations configuration: '||p_data::text);
end $$;
create or replace function public.set_delivery_partner_operational_state(p_user uuid,p_online boolean,p_lat double precision,p_lon double precision,p_accuracy double precision) returns jsonb language plpgsql security definer set search_path=public as $$
declare p delivery_partner_profiles%rowtype; a delivery_partner_availability%rowtype;
begin
 select * into p from delivery_partner_profiles where user_id=p_user for update;
 if not found or p.verification_status<>'approved' then raise exception 'Approved profile required'; end if;
 if p_online is true and p.partner_type='salaried' and not coalesce(p.employment_active and p.shift_start<=now() and p.shift_end>now(),false) then raise exception 'An active shift is required to go online'; end if;
 if (p_lat is null)<>(p_lon is null) or (p_lat is not null and (p_lat not between -90 and 90 or p_lon not between -180 and 180 or p_accuracy is null or p_accuracy<0)) then raise exception 'Invalid location'; end if;
 insert into delivery_partner_availability(partner_id) values(p.id) on conflict do nothing;
 select * into a from delivery_partner_availability where partner_id=p.id for update;
 if p_lat is not null and not a.is_online then raise exception 'Go online before sharing location'; end if;
 update delivery_partner_availability set is_online=coalesce(p_online,is_online),
 latitude=case when p_online is false then null when p_lat is not null then p_lat else latitude end,
 longitude=case when p_online is false then null when p_lon is not null then p_lon else longitude end,
 accuracy_m=case when p_online is false then null when p_lat is not null then p_accuracy else accuracy_m end,
 location_recorded_at=case when p_online is false then null when p_lat is not null then now() else location_recorded_at end,updated_at=now() where partner_id=p.id returning * into a;
 return to_jsonb(a);
end $$;
create function public.delivery_offers(p_user uuid) returns jsonb language sql stable security definer set search_path=public as $$
 select coalesce(jsonb_agg(x),'[]') from (
 select t.id,t.pickup_address,t.service_area,t.package_description,t.weight_kg,t.volume_litres,t.urgency,t.independent_deadline,c.distance_km,
 delivery_distance_km(t.pickup_lat,t.pickup_lon,t.destination_lat,t.destination_lon) as route_km
 from delivery_tasks t cross join lateral delivery_candidates(t.id,'independent') c
 where c.user_id=p_user and t.status='independent_allocation' and t.independent_deadline>now()
 and not exists(select 1 from delivery_allocation_attempts a where a.task_id=t.id and a.partner_id=c.partner_id and a.status='rejected')
 order by t.independent_deadline limit 50) x
$$;

-- Every function with actor parameters is service-only. The HTTP layer supplies the verified identity and checks admin ownership.
do $$ declare f record; begin for f in select p.oid::regprocedure as signature from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and (p.proname like 'delivery_%' or p.proname='process_delivery_jobs') loop
 execute format('revoke all on function %s from public,anon,authenticated',f.signature);
 execute format('grant execute on function %s to service_role',f.signature);
 end loop; end $$;
commit;
