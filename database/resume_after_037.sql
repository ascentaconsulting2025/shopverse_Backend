-- Shopverse recovery after migrations 036-037 were already committed.
-- Applies the catalog-trigger correction, then resumes with migrations 038-047.
-- Do not use on a fresh database; use database/master_schema.sql instead.

begin;
create or replace function public.validate_business_catalog_reference() returns trigger
language plpgsql security definer set search_path=public as $$
declare business_category uuid; selected uuid; previous uuid;
begin
 perform pg_advisory_xact_lock_shared(184712009);
 if tg_table_name='businesses' then
  selected:=new.global_category_id;
  if tg_op='UPDATE' and selected is not distinct from old.global_category_id then return new;end if;
  if not exists(select 1 from business_categories where id=selected and catalog_kind='business' and status='enabled' and is_published) then
   raise exception 'Select an active business category' using errcode='23514';end if;
 else
  -- Unrelated listing updates (for example fleet metadata backfills) must not
  -- revalidate unchanged legacy catalog assignments.
  if tg_op='UPDATE'
   and new.business_id is not distinct from old.business_id
   and new.folder_category_id is not distinct from old.folder_category_id
   and new.category_id is not distinct from old.category_id then return new;end if;
  select global_category_id into business_category from businesses where id=new.business_id for share;
  if not catalog_category_allowed(business_category,case when tg_table_name='products' then 'product' else 'service' end,new.folder_category_id)
   or new.category_id is distinct from new.folder_category_id then
   raise exception 'Select an active allowed leaf category for this business and listing type' using errcode='23514';end if;
 end if;
 return new;
end $$;
commit;

-- ============================================================================
-- Source: migrations/038_fleet_types.sql
-- ============================================================================
-- Fleet types are retained when referenced; products default to Bike.
begin;
create table public.fleet_types (
 id uuid primary key default gen_random_uuid(), code text not null unique check(code ~ '^[a-z][a-z0-9_]{0,39}$'),
 name text not null check(length(trim(name)) between 1 and 80), sort_rank integer not null check(sort_rank between 1 and 10000),
 active boolean not null default true, created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
insert into public.fleet_types(code,name,sort_rank) values ('scooter','Scooter',10),('bike','Bike',20),('small_tempo','Small Tempo',30),('truck','Truck',40);
alter table public.fleet_types enable row level security;
revoke all on public.fleet_types from public,anon,authenticated;
grant all on public.fleet_types to service_role;
alter table public.products add column fleet_type_id uuid references public.fleet_types(id) on delete restrict;
update public.products set fleet_type_id=(select id from public.fleet_types where code='bike');
alter table public.products alter column fleet_type_id set not null;
create function public.validate_product_fleet() returns trigger language plpgsql set search_path=public as $$
begin
 if new.fleet_type_id is null then select id into new.fleet_type_id from fleet_types where code='bike' and active; end if;
 if (tg_op='INSERT' or new.fleet_type_id is distinct from old.fleet_type_id) and not exists(select 1 from fleet_types where id=new.fleet_type_id and active) then raise exception 'Fleet type unavailable'; end if;
 return new;
end $$;
create trigger product_fleet_valid before insert or update of fleet_type_id on public.products for each row execute function public.validate_product_fleet();
commit;

-- ============================================================================
-- Source: migrations/039_delivery_pricing.sql
-- ============================================================================
-- Pricing is configured explicitly; no charges or delivery areas are invented.
begin;
create table public.delivery_pricing_config (
 id boolean primary key default true check(id), config jsonb not null default '{}'::jsonb,
 updated_by uuid references auth.users(id), updated_at timestamptz not null default now()
);
insert into public.delivery_pricing_config(id) values(true);
create table public.delivery_pricing_config_history (
 id uuid primary key default gen_random_uuid(), actor_id uuid references auth.users(id), old_config jsonb not null, new_config jsonb not null, created_at timestamptz not null default now()
);
alter table public.delivery_pricing_config enable row level security;
alter table public.delivery_pricing_config_history enable row level security;
revoke all on public.delivery_pricing_config,public.delivery_pricing_config_history from public,anon,authenticated;
grant all on public.delivery_pricing_config,public.delivery_pricing_config_history to service_role;
create function public.save_delivery_pricing_config(p_actor uuid,p_config jsonb) returns void language plpgsql security definer set search_path=public as $$
declare old_config jsonb;
begin
 select config into old_config from delivery_pricing_config where id=true for update;
 update delivery_pricing_config set config=p_config,updated_by=p_actor,updated_at=now() where id=true;
 insert into delivery_pricing_config_history(actor_id,old_config,new_config) values(p_actor,old_config,p_config);
end $$;
revoke all on function public.save_delivery_pricing_config(uuid,jsonb) from public,anon,authenticated;
grant execute on function public.save_delivery_pricing_config(uuid,jsonb) to service_role;
commit;

-- ============================================================================
-- Source: migrations/040_pickup_settings.sql
-- ============================================================================
begin;
create table public.pickup_settings (id boolean primary key default true check(id),lead_minutes integer not null default 30 check(lead_minutes between 0 and 10080),updated_by uuid references auth.users(id),updated_at timestamptz not null default now());
insert into public.pickup_settings(id) values(true);
alter table public.pickup_settings enable row level security;
revoke all on public.pickup_settings from public,anon,authenticated;
grant all on public.pickup_settings to service_role;
commit;

-- ============================================================================
-- Source: migrations/041_pickup_orders.sql
-- ============================================================================
begin;
alter table public.marketplace_store_orders
 add column fulfillment_method text check(fulfillment_method in ('pickup','standard_4_6h','standard_24h','urgent')),
 add column pickup_start timestamptz,
 add column pickup_end timestamptz,
 add column pickup_timezone text,
 add column pickup_store_address jsonb,
 add constraint pickup_order_schedule_valid check(fulfillment_method is distinct from 'pickup' or (pickup_start is not null and pickup_end=pickup_start+interval '1 hour' and pickup_timezone is not null and pickup_store_address is not null));
create function public.place_pickup_store_request(p_customer uuid,p_store uuid,p_key uuid,p_name text,p_phone text,p_expected jsonb,p_start timestamptz,p_end timestamptz,p_hours jsonb,p_address jsonb,p_address_text text,p_lead integer)
returns jsonb language plpgsql security definer set search_path=public as $$
declare prior marketplace_store_orders%rowtype; result jsonb; b record; lead integer;
begin
 perform pg_advisory_xact_lock(hashtextextended(p_customer::text || ':' || p_key::text,0));
 select so.* into prior from marketplace_orders o join marketplace_store_orders so on so.order_id=o.id where o.customer_id=p_customer and o.request_key=p_key;
 if found then
  if prior.business_id is distinct from p_store or prior.fulfillment_method is distinct from 'pickup' or prior.pickup_start is distinct from p_start or prior.pickup_end is distinct from p_end then raise exception 'Request key already used'; end if;
  return jsonb_build_object('store_order_id',prior.id,'replayed',true);
 end if;
 select details,is_published into b from businesses where id=p_store for share;
 select lead_minutes into lead from pickup_settings where id=true for share;
 if not found or b.is_published is not true or b.details->'businessHours' is distinct from p_hours or b.details->'address' is distinct from p_address or lead is distinct from p_lead then raise exception 'Pickup availability changed'; end if;
 if p_start is null or p_end is distinct from p_start+interval '1 hour' or p_start<now()+make_interval(mins=>lead) or nullif(trim(p_hours->>'timezone'),'') is null or length(trim(p_address_text)) not between 1 and 500 then raise exception 'Pickup availability changed'; end if;
 result:=place_whatsapp_store_request(p_customer,p_store,p_key,p_name,p_phone,p_address_text,p_expected);
 update marketplace_store_orders set fulfillment_method='pickup',pickup_start=p_start,pickup_end=p_end,pickup_timezone=p_hours->>'timezone',pickup_store_address=p_address where id=(result->>'store_order_id')::uuid;
 return result;
end $$;
create or replace function public.confirm_reviewed_store_order(p_order uuid,p_actor uuid,p_is_admin boolean,p_expected_token uuid,p_closing_price numeric)
returns boolean language plpgsql security definer set search_path=public as $$
declare target marketplace_store_orders%rowtype; confirmed boolean;
begin
 select * into target from marketplace_store_orders where id=p_order for update;
 if not found or (p_is_admin is not true and not exists(select 1 from businesses where id=target.business_id and owner_id=p_actor)) then return false; end if;
 if target.status <> 'PENDING' then return false; end if;
 if p_expected_token is null or p_expected_token <> target.edit_token then raise exception 'Order changed'; end if;
 if target.subtotal is null or target.subtotal <= 0 then raise exception 'Product subtotal unavailable'; end if;
 if p_closing_price is null or p_closing_price <= 0 or p_closing_price > target.subtotal or p_closing_price <> round(p_closing_price,2) then raise exception 'Invalid closing price'; end if;
 update marketplace_store_orders set closing_price=p_closing_price where id=target.id;
 confirmed:=manage_store_order(p_order,p_actor,p_is_admin,'accept');
 if confirmed and target.fulfillment_method='pickup' then
  update marketplace_store_orders set status='PROCESSING' where id=target.id;
  insert into marketplace_order_status_history(store_order_id,previous_status,new_status,changed_by) values(target.id,'ACCEPTED','PROCESSING',p_actor);
 end if;
 return confirmed;
end $$;
revoke all on function public.place_pickup_store_request(uuid,uuid,uuid,text,text,jsonb,timestamptz,timestamptz,jsonb,jsonb,text,integer) from public,anon,authenticated;
grant execute on function public.place_pickup_store_request(uuid,uuid,uuid,text,text,jsonb,timestamptz,timestamptz,jsonb,jsonb,text,integer) to service_role;
commit;

-- ============================================================================
-- Source: migrations/042_pickup_handover.sql
-- ============================================================================
begin;
create table public.pickup_handover_codes (
 store_order_id uuid primary key references public.marketplace_store_orders(id) on delete restrict,
 nonce uuid not null, code_hash text not null check(code_hash ~ '^[0-9a-f]{64}$'), expires_at timestamptz not null,
 failed_attempts integer not null default 0, locked_until timestamptz, consumed_at timestamptz, created_at timestamptz not null default now()
);
alter table public.pickup_handover_codes enable row level security;
revoke all on public.pickup_handover_codes from public,anon,authenticated;
grant all on public.pickup_handover_codes to service_role;
create function public.pickup_mark_ready(p_order uuid,p_actor uuid,p_admin boolean,p_nonce uuid,p_hash text)
returns text language plpgsql security definer set search_path=public as $$
declare target marketplace_store_orders%rowtype; current_code pickup_handover_codes%rowtype;
begin
 select * into target from marketplace_store_orders where id=p_order for update;
 if not found or target.fulfillment_method is distinct from 'pickup' or (p_admin is not true and not exists(select 1 from businesses where id=target.business_id and owner_id=p_actor)) then return 'unavailable'; end if;
 if target.status not in ('PROCESSING','READY_FOR_DISPATCH') then return 'invalid_state'; end if;
 if p_nonce is null or p_hash !~ '^[0-9a-f]{64}$' then return 'invalid_code'; end if;
 select * into current_code from pickup_handover_codes where store_order_id=p_order for update;
 if found and current_code.expires_at>now() and current_code.consumed_at is null then return 'already_ready'; end if;
 insert into pickup_handover_codes(store_order_id,nonce,code_hash,expires_at) values(p_order,p_nonce,p_hash,now()+interval '24 hours')
 on conflict(store_order_id) do update set nonce=excluded.nonce,code_hash=excluded.code_hash,expires_at=excluded.expires_at,failed_attempts=0,locked_until=null,consumed_at=null,created_at=now();
 if target.status='PROCESSING' then
  update marketplace_store_orders set status='READY_FOR_DISPATCH' where id=p_order;
  insert into marketplace_order_status_history(store_order_id,previous_status,new_status,changed_by) values(p_order,'PROCESSING','READY_FOR_DISPATCH',p_actor);
 end if;
 perform delivery_notice(null,o.customer_id,false,'Order '||target.store_order_number||' is ready for pickup. View your pickup code in order history.','pickup-ready:'||p_order||':'||p_nonce) from marketplace_orders o where o.id=target.order_id and o.customer_id is not null;
 return 'ready';
end $$;
create function public.pickup_verify_handover(p_order uuid,p_actor uuid,p_admin boolean,p_hash text)
returns text language plpgsql security definer set search_path=public as $$
declare target marketplace_store_orders%rowtype; code pickup_handover_codes%rowtype;
begin
 select * into target from marketplace_store_orders where id=p_order for update;
 if not found or target.fulfillment_method is distinct from 'pickup' or (p_admin is not true and not exists(select 1 from businesses where id=target.business_id and owner_id=p_actor)) then return 'unavailable'; end if;
 if target.status='DELIVERED' then return 'completed'; end if;
 if target.status<>'READY_FOR_DISPATCH' then return 'invalid_state'; end if;
 select * into code from pickup_handover_codes where store_order_id=p_order for update;
 if not found or code.consumed_at is not null or code.expires_at<=now() then return 'expired'; end if;
 if code.locked_until>now() then return 'locked'; end if;
 if code.locked_until is not null then update pickup_handover_codes set failed_attempts=0,locked_until=null where store_order_id=p_order; code.failed_attempts:=0; end if;
 if p_hash is distinct from code.code_hash then
  update pickup_handover_codes set failed_attempts=code.failed_attempts+1,locked_until=case when code.failed_attempts+1>=5 then now()+interval '15 minutes' else null end where store_order_id=p_order;
  return case when code.failed_attempts+1>=5 then 'locked' else 'invalid_code' end;
 end if;
 update pickup_handover_codes set consumed_at=now(),code_hash=repeat('0',64) where store_order_id=p_order;
 update marketplace_store_orders set status='DELIVERED' where id=p_order;
 insert into marketplace_order_status_history(store_order_id,previous_status,new_status,changed_by) values(p_order,'READY_FOR_DISPATCH','DELIVERED',p_actor);
 perform delivery_notice(null,o.customer_id,false,'Order '||target.store_order_number||' pickup completed.','pickup-completed:'||p_order) from marketplace_orders o where o.id=target.order_id and o.customer_id is not null;
 return 'completed';
end $$;
revoke all on function public.pickup_mark_ready(uuid,uuid,boolean,uuid,text),public.pickup_verify_handover(uuid,uuid,boolean,text) from public,anon,authenticated;
grant execute on function public.pickup_mark_ready(uuid,uuid,boolean,uuid,text),public.pickup_verify_handover(uuid,uuid,boolean,text) to service_role;
commit;

-- ============================================================================
-- Source: migrations/043_pickup_rescheduling.sql
-- ============================================================================
begin;
create table public.pickup_reschedule_proposals (
 id uuid primary key default gen_random_uuid(),store_order_id uuid not null references public.marketplace_store_orders(id),
 pickup_start timestamptz not null,pickup_end timestamptz not null,timezone text not null,
 status text not null default 'pending' check(status in ('pending','accepted','declined','superseded')),
 proposed_by uuid references auth.users(id),created_at timestamptz not null default now(),responded_at timestamptz,
 check(pickup_end=pickup_start+interval '1 hour')
);
create unique index pickup_one_pending_proposal on public.pickup_reschedule_proposals(store_order_id) where status='pending';
alter table public.pickup_reschedule_proposals enable row level security;
revoke all on public.pickup_reschedule_proposals from public,anon,authenticated;
grant all on public.pickup_reschedule_proposals to service_role;
create function public.pickup_propose_window(p_order uuid,p_actor uuid,p_admin boolean,p_start timestamptz,p_end timestamptz,p_hours jsonb,p_lead integer)
returns uuid language plpgsql security definer set search_path=public as $$
declare target marketplace_store_orders%rowtype; hours jsonb; lead integer; result uuid;
begin
 select * into target from marketplace_store_orders where id=p_order for update;
 if not found or target.fulfillment_method is distinct from 'pickup' or (p_admin is not true and not exists(select 1 from businesses where id=target.business_id and owner_id=p_actor)) then raise exception 'Order unavailable'; end if;
 if target.status not in ('PROCESSING','READY_FOR_DISPATCH') then raise exception 'Order changed'; end if;
 select details->'businessHours' into hours from businesses where id=target.business_id and is_published for share;
 select lead_minutes into lead from pickup_settings where id=true for share;
 if hours is distinct from p_hours or lead is distinct from p_lead or p_end is distinct from p_start+interval '1 hour' or p_start<now()+make_interval(mins=>lead) then raise exception 'Pickup availability changed'; end if;
 update pickup_reschedule_proposals set status='superseded',responded_at=now() where store_order_id=p_order and status='pending';
 insert into pickup_reschedule_proposals(store_order_id,pickup_start,pickup_end,timezone,proposed_by) values(p_order,p_start,p_end,p_hours->>'timezone',p_actor) returning id into result;
 perform delivery_notice(null,o.customer_id,false,'The seller proposed a new pickup time for order '||target.store_order_number||'. Review it in order history.','pickup-proposal:'||result) from marketplace_orders o where o.id=target.order_id and o.customer_id is not null;
 return result;
end $$;
create function public.pickup_respond_window(p_order uuid,p_proposal uuid,p_customer uuid,p_accept boolean,p_hours jsonb,p_lead integer)
returns text language plpgsql security definer set search_path=public as $$
declare target marketplace_store_orders%rowtype; proposal pickup_reschedule_proposals%rowtype; hours jsonb; lead integer;
begin
 select so.* into target from marketplace_store_orders so join marketplace_orders o on o.id=so.order_id where so.id=p_order and o.customer_id=p_customer for update of so;
 if not found or target.fulfillment_method is distinct from 'pickup' then return 'unavailable'; end if;
 if target.status not in ('PROCESSING','READY_FOR_DISPATCH') then return 'changed'; end if;
 select * into proposal from pickup_reschedule_proposals where id=p_proposal and store_order_id=p_order for update;
 if not found or proposal.status<>'pending' then return 'changed'; end if;
 if not p_accept then
  update pickup_reschedule_proposals set status='declined',responded_at=now() where id=proposal.id;
  perform delivery_notice(null,b.owner_id,false,'The buyer declined the new pickup time for order '||target.store_order_number||'.','pickup-response:'||proposal.id) from businesses b where b.id=target.business_id and b.owner_id is not null;
  return 'declined';
 end if;
 select details->'businessHours' into hours from businesses where id=target.business_id and is_published for share;
 select lead_minutes into lead from pickup_settings where id=true for share;
 if hours is distinct from p_hours or lead is distinct from p_lead or proposal.pickup_start<now()+make_interval(mins=>lead) then return 'changed'; end if;
 update marketplace_store_orders set pickup_start=proposal.pickup_start,pickup_end=proposal.pickup_end,pickup_timezone=proposal.timezone where id=p_order;
 update pickup_reschedule_proposals set status='accepted',responded_at=now() where id=proposal.id;
 perform delivery_notice(null,b.owner_id,false,'The buyer accepted the new pickup time for order '||target.store_order_number||'.','pickup-response:'||proposal.id) from businesses b where b.id=target.business_id and b.owner_id is not null;
 return 'accepted';
end $$;
revoke all on function public.pickup_propose_window(uuid,uuid,boolean,timestamptz,timestamptz,jsonb,integer), public.pickup_respond_window(uuid,uuid,uuid,boolean,jsonb,integer) from public,anon,authenticated;
grant execute on function public.pickup_propose_window(uuid,uuid,boolean,timestamptz,timestamptz,jsonb,integer), public.pickup_respond_window(uuid,uuid,uuid,boolean,jsonb,integer) to service_role;
commit;

-- ============================================================================
-- Source: migrations/044_pickup_logistics_guard.sql
-- ============================================================================
-- Existing logistics APIs remain available for legacy delivery orders, never for self pickup.
begin;
alter function public.delivery_select_order(uuid,uuid,boolean,jsonb) rename to delivery_select_order_legacy;
revoke all on function public.delivery_select_order_legacy(uuid,uuid,boolean,jsonb) from public,anon,authenticated,service_role;
create function public.delivery_select_order(p_store_order uuid,p_actor uuid,p_admin boolean,p_details jsonb)
returns uuid language plpgsql security definer set search_path=public as $$
declare mode text;
begin
 select fulfillment_method into mode from marketplace_store_orders where id=p_store_order;
 if mode='pickup' then raise exception 'Self pickup orders cannot enter delivery allocation'; end if;
 return delivery_select_order_legacy(p_store_order,p_actor,p_admin,p_details);
end $$;
revoke all on function public.delivery_select_order(uuid,uuid,boolean,jsonb) from public,anon,authenticated;
grant execute on function public.delivery_select_order(uuid,uuid,boolean,jsonb) to service_role;
commit;

-- ============================================================================
-- Source: migrations/045_fleet_partner_mapping.sql
-- ============================================================================
-- Explicitly map existing free-text partner vehicle labels to managed fleet types.
begin;
create table public.fleet_partner_vehicle_labels (
 fleet_type_id uuid not null references public.fleet_types(id) on delete restrict,
 vehicle_label text not null check(length(trim(vehicle_label)) between 1 and 80),
 created_by uuid references auth.users(id),created_at timestamptz not null default now(),
 primary key(fleet_type_id,vehicle_label),check(vehicle_label=lower(trim(vehicle_label)))
);
create unique index fleet_partner_vehicle_label_unique on public.fleet_partner_vehicle_labels(vehicle_label);
-- Exact existing labels are safe to map; other free-text labels require administrator review.
insert into public.fleet_partner_vehicle_labels(fleet_type_id,vehicle_label)
 select f.id,lower(f.name) from public.fleet_types f where f.code in ('scooter','bike','small_tempo','truck');
alter table public.fleet_partner_vehicle_labels enable row level security;
revoke all on public.fleet_partner_vehicle_labels from public,anon,authenticated;
grant all on public.fleet_partner_vehicle_labels to service_role;
commit;

-- ============================================================================
-- Source: migrations/046_fleet_only_matching.sql
-- ============================================================================
-- Fleet-only tasks cannot share a partner with another active task because their load is unknown.
begin;
alter table public.delivery_tasks add column fleet_only boolean not null default false;
alter table public.delivery_tasks alter column weight_kg drop not null;
alter table public.delivery_tasks alter column volume_litres drop not null;
alter table public.delivery_tasks add constraint delivery_fleet_measurements_consistent check ((fleet_only and weight_kg is null and volume_litres is null) or (not fleet_only and weight_kg is not null and volume_litres is not null));
create or replace function public.delivery_candidates(p_task uuid,p_type text default null) returns table(partner_id uuid,user_id uuid,full_name text,partner_type text,vehicle_type text,distance_km double precision,active_orders bigint,score double precision) language sql stable security definer set search_path=public as $$
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
 and p.max_active_orders is not null
 and ((t.fleet_only and not exists(select 1 from delivery_assignments x where x.partner_id=p.id and x.ended_at is null))
   or (not t.fleet_only
    and not exists(select 1 from delivery_assignments x join delivery_tasks q on q.id=x.task_id where x.partner_id=p.id and x.ended_at is null and q.fleet_only)
    and p.capacity_kg>=t.weight_kg+coalesce((select sum(q.weight_kg) from delivery_assignments x join delivery_tasks q on q.id=x.task_id where x.partner_id=p.id and x.ended_at is null),0)
    and p.capacity_litres>=t.volume_litres+coalesce((select sum(q.volume_litres) from delivery_assignments x join delivery_tasks q on q.id=x.task_id where x.partner_id=p.id and x.ended_at is null),0)))
 and (p.partner_type='independent' or (p.employment_active and p.shift_start<=now() and p.shift_end>now()))
 ) select id,user_id,full_name,partner_type,vehicle_type,distance_km,workload,
 100*((config->'weights'->>'distance')::double precision/(1+distance_km)+
 (config->'weights'->>'workload')::double precision*(1-workload::double precision/capacity)+
 (config->'weights'->>'route')::double precision/(1+route_km)+
 (config->'weights'->>'availability')::double precision+(config->'weights'->>'vehicle')::double precision)/100
 from eligible where workload<capacity and distance_km <= (select max(value::double precision) from jsonb_array_elements_text(config->'search_radii_km'))
 order by 8 desc,6,1
$$;
revoke all on function public.delivery_candidates(uuid,text) from public,anon,authenticated;
grant execute on function public.delivery_candidates(uuid,text) to service_role;
commit;

-- ============================================================================
-- Source: migrations/047_delivery_checkout_allocation.sql
-- ============================================================================
begin;
alter table public.marketplace_store_orders
 add column delivery_fleet_id uuid references public.fleet_types(id) on delete restrict,
 add column delivery_fee numeric(12,2) check(delivery_fee is null or delivery_fee>=0),
 add column delivery_distance_km numeric(8,1) check(delivery_distance_km is null or delivery_distance_km>=0),
 add column delivery_quote_config jsonb,
 add column delivery_store_address jsonb;
create table public.delivery_order_allocation_jobs (
 store_order_id uuid primary key references public.marketplace_store_orders(id) on delete restrict,
 status text not null default 'queued' check(status in ('queued','created','cancelled')),
 actor_id uuid references auth.users(id), last_error text, created_at timestamptz not null default now(),updated_at timestamptz not null default now()
);
alter table public.delivery_order_allocation_jobs enable row level security;
revoke all on public.delivery_order_allocation_jobs from public,anon,authenticated;
grant all on public.delivery_order_allocation_jobs to service_role;

-- Read existing bilingual profile fields without requiring a duplicate address.
create function public.fulfillment_address_text(value jsonb) returns text language sql immutable set search_path=public as $$
 select nullif(trim(case when jsonb_typeof(value)='string' then value#>>'{}' when jsonb_typeof(value)='object' then coalesce(nullif(value->>'en',''),value->>'mr') else null end),'')
$$;

create function public.place_delivery_store_request(p_customer uuid,p_store uuid,p_key uuid,p_address_id uuid,p_expected jsonb,p_method text,p_fleet uuid,p_distance numeric,p_fee numeric,p_config jsonb,p_origin jsonb,p_destination jsonb)
returns jsonb language plpgsql security definer set search_path=public as $$
declare prior marketplace_store_orders%rowtype; result jsonb; origin jsonb; destination jsonb; cfg jsonb; highest uuid;
begin
 perform pg_advisory_xact_lock(hashtextextended(p_customer::text||':'||p_key::text,0));
 select so.* into prior from marketplace_orders o join marketplace_store_orders so on so.order_id=o.id where o.customer_id=p_customer and o.request_key=p_key;
 if found then
  if prior.business_id is distinct from p_store or prior.fulfillment_method is distinct from p_method or (select delivery_address_snapshot->>'id' from marketplace_orders where id=prior.order_id) is distinct from p_address_id::text then raise exception 'Request key already used'; end if;
  return jsonb_build_object('store_order_id',prior.id,'replayed',true);
 end if;
 if p_method not in ('standard_4_6h','standard_24h','urgent') or p_distance is null or p_distance<0 or p_fee is null or p_fee<0 then raise exception 'Invalid delivery'; end if;
 select details->'address' into origin from businesses where id=p_store and is_published for share;
 select to_jsonb(a) into destination from customer_addresses a where id=p_address_id and user_id=p_customer for share;
 select config into cfg from delivery_pricing_config where id=true for share;
 if origin is distinct from p_origin or destination is distinct from p_destination or cfg is distinct from p_config then raise exception 'Delivery availability changed'; end if;
 result:=place_saved_address_request(p_customer,p_store,p_key,p_address_id,p_expected);
 select f.id into highest from marketplace_order_items i join products p on p.id=i.product_id join fleet_types f on f.id=p.fleet_type_id where i.store_order_id=(result->>'store_order_id')::uuid order by f.sort_rank desc,f.id limit 1;
 if highest is distinct from p_fleet or not exists(select 1 from fleet_types where id=p_fleet and active) then raise exception 'Delivery availability changed'; end if;
 update marketplace_store_orders set fulfillment_method=p_method,delivery_fleet_id=p_fleet,delivery_distance_km=p_distance,delivery_fee=p_fee,delivery_quote_config=p_config,delivery_store_address=p_origin where id=(result->>'store_order_id')::uuid;
 return result;
end $$;

create function public.confirm_fulfillment_order(p_order uuid,p_actor uuid,p_admin boolean,p_token uuid,p_price numeric,p_fleet uuid)
returns boolean language plpgsql security definer set search_path=public as $$
declare target marketplace_store_orders%rowtype; rate numeric; base numeric; confirmed boolean; fee numeric; origin jsonb; address_row customer_addresses%rowtype; distance numeric; customer uuid; phone text;
begin
 perform pg_advisory_xact_lock(74901);
 select * into target from marketplace_store_orders where id=p_order for update;
 if not found or (p_admin is not true and not exists(select 1 from businesses where id=target.business_id and owner_id=p_actor)) then return false; end if;
 if target.status<>'PENDING' then return false; end if;
 if p_token is null or target.edit_token<>p_token then raise exception 'Order changed'; end if;
 if target.subtotal is null or target.subtotal<=0 or p_price is null or p_price<=0 or p_price>target.subtotal or p_price<>round(p_price,2) then raise exception 'Invalid closing price'; end if;
 if target.fulfillment_method in ('standard_4_6h','standard_24h','urgent') then
  if p_fleet is null or not exists(select 1 from fleet_types where id=p_fleet and active) then raise exception 'Fleet unavailable'; end if;
  select (x->>'perKm')::numeric into rate from jsonb_array_elements(target.delivery_quote_config->'fleetRates') x where x->>'fleetId'=p_fleet::text;
  base:=(target.delivery_quote_config->'speeds'->target.fulfillment_method->>'base')::numeric;
  if rate is null or base is null or target.delivery_distance_km is null then raise exception 'Fleet rate unavailable'; end if;
  select b.details->'address' into origin from businesses b where b.id=target.business_id and b.is_published for share;
  select o.customer_id into customer from marketplace_orders o where o.id=target.order_id;
  select a.* into address_row from customer_addresses a where a.id=(select (o.delivery_address_snapshot->>'id')::uuid from marketplace_orders o where o.id=target.order_id) and a.user_id=customer for share;
  if origin is null or address_row.id is null or origin->>'latitude' is null or origin->>'longitude' is null or address_row.latitude is null or address_row.longitude is null or fulfillment_address_text(origin->'street') is null or fulfillment_address_text(origin->'city') is null then raise exception 'Delivery address unavailable'; end if;
  if abs((origin->>'latitude')::numeric)>90 or abs((origin->>'longitude')::numeric)>180 then raise exception 'Delivery address unavailable'; end if;
  phone:=regexp_replace(address_row.phone_number,'[^0-9]','','g');
  if phone ~ '^[6-9][0-9]{9}$' then phone:='91'||phone; end if;
  if phone !~ '^91[6-9][0-9]{9}$' then raise exception 'Delivery address unavailable'; end if;
  if not (target.delivery_quote_config->'postcodes' ? address_row.postal_code) then raise exception 'Delivery address unavailable'; end if;
  distance:=ceil(delivery_distance_km((origin->>'latitude')::double precision,(origin->>'longitude')::double precision,address_row.latitude::double precision,address_row.longitude::double precision)*10)/10;
  if distance>(target.delivery_quote_config->>'maxRadiusKm')::numeric then raise exception 'Delivery address unavailable'; end if;
  fee:=round(base+distance*rate,2);
  update marketplace_orders set customer_name=address_row.full_name,customer_phone=phone,delivery_address=concat_ws(', ',address_row.address_line_1,address_row.address_line_2,nullif(address_row.landmark,''),address_row.city,address_row.state,address_row.postal_code,address_row.country),delivery_address_snapshot=to_jsonb(address_row)-'user_id'-'created_at'-'updated_at'-'is_default' where id=target.order_id;
  update marketplace_store_orders set delivery_fleet_id=p_fleet,delivery_fee=fee,delivery_distance_km=distance,delivery_store_address=origin,closing_price=p_price where id=p_order;
 else update marketplace_store_orders set closing_price=p_price where id=p_order; end if;
 confirmed:=manage_store_order(p_order,p_actor,p_admin,'accept');
 if confirmed and target.fulfillment_method='pickup' then
  update marketplace_store_orders set status='PROCESSING' where id=p_order;
  insert into marketplace_order_status_history(store_order_id,previous_status,new_status,changed_by) values(p_order,'ACCEPTED','PROCESSING',p_actor);
 elsif confirmed and target.fulfillment_method in ('standard_4_6h','standard_24h','urgent') then
  insert into delivery_order_allocation_jobs(store_order_id,actor_id) values(p_order,p_actor) on conflict do nothing;
  perform delivery_notice(null,o.customer_id,false,'Order '||target.store_order_number||' was confirmed. Delivery charge: ₹'||to_char(fee,'FM9999999990.00')||'. Allocation is starting.','delivery-confirmed:'||p_order) from marketplace_orders o where o.id=target.order_id and o.customer_id is not null;
 end if;
 return confirmed;
exception when invalid_text_representation or numeric_value_out_of_range then
 raise exception 'Delivery address unavailable';
end $$;

create function public.process_delivery_order_allocation() returns integer language plpgsql security definer set search_path=public as $$
declare job delivery_order_allocation_jobs%rowtype; so marketplace_store_orders%rowtype; parent marketplace_orders%rowtype; cfg jsonb; labels text[]; origin jsonb; task uuid; n integer:=0; pickup_text text;
begin
 if not pg_try_advisory_xact_lock(74901) then return 0; end if;
 for job in select j.* from delivery_order_allocation_jobs j join marketplace_store_orders s on s.id=j.store_order_id where j.status='queued' order by case when s.fulfillment_method='urgent' then 0 else 1 end,j.updated_at limit 100 for update of j skip locked loop
  begin
   select * into so from marketplace_store_orders where id=job.store_order_id for update;
   if so.status not in ('ACCEPTED','PROCESSING','READY_FOR_DISPATCH') or so.fulfillment_method not in ('standard_4_6h','standard_24h','urgent') then update delivery_order_allocation_jobs set status='cancelled',updated_at=now() where store_order_id=job.store_order_id;continue;end if;
   select config into cfg from delivery_settings where id=true;
   if cfg is null or not coalesce((cfg->>'enabled')::boolean,false) then raise exception 'Allocation settings are not enabled'; end if;
   select array_agg(vehicle_label order by vehicle_label) into labels from fleet_partner_vehicle_labels where fleet_type_id=so.delivery_fleet_id;
   if labels is null then raise exception 'No partner vehicle labels are mapped to this fleet'; end if;
   select * into parent from marketplace_orders where id=so.order_id;
   origin:=so.delivery_store_address;
   pickup_text:=concat_ws(', ',fulfillment_address_text(origin->'street'),fulfillment_address_text(origin->'landmark'),fulfillment_address_text(origin->'city'),fulfillment_address_text(origin->'state'),nullif(origin->>'pincode',''));
   if length(trim(pickup_text))<3 or nullif(parent.delivery_address_snapshot->>'city','') is null then raise exception 'Saved address is incomplete'; end if;
   insert into delivery_tasks(store_order_id,status,pickup_address,pickup_lat,pickup_lon,destination_address,destination_lat,destination_lon,service_area,package_description,weight_kg,volume_litres,eligible_vehicles,urgency,config,independent_deadline,created_by,fleet_only)
   values(so.id,'independent_allocation',pickup_text,(origin->>'latitude')::double precision,(origin->>'longitude')::double precision,parent.delivery_address,(parent.delivery_address_snapshot->>'latitude')::double precision,(parent.delivery_address_snapshot->>'longitude')::double precision,parent.delivery_address_snapshot->>'city','Order '||so.store_order_number,null,null,labels,case when so.fulfillment_method='urgent' then 'urgent' else 'standard' end,cfg,now()+make_interval(secs=>(cfg->>'independent_timeout_seconds')::integer),job.actor_id,true)
   on conflict(store_order_id) do nothing returning id into task;
   if task is null then select id into task from delivery_tasks where store_order_id=so.id; end if;
   perform delivery_log(task,job.actor_id,'delivery_automatically_requested',null,'independent_allocation');
   perform delivery_publish_offers(task);
   update delivery_order_allocation_jobs set status='created',last_error=null,updated_at=now() where store_order_id=so.id;
   n:=n+1;
  exception when others then
   update delivery_order_allocation_jobs set last_error='Allocation setup needs administrator attention',updated_at=now() where store_order_id=job.store_order_id;
   perform delivery_notice(null,null,true,'Delivery allocation needs attention for order '||coalesce(so.store_order_number,job.store_order_id::text),'delivery-setup:'||job.store_order_id);
  end;
 end loop;
 return n;
end $$;

create function public.switch_delivery_to_pickup(p_order uuid,p_customer uuid,p_start timestamptz,p_end timestamptz,p_hours jsonb,p_address jsonb,p_lead integer)
returns text language plpgsql security definer set search_path=public as $$
declare so marketplace_store_orders%rowtype; task delivery_tasks%rowtype; store_details jsonb; lead integer;
begin
 perform pg_advisory_xact_lock(74901);
 select s.* into so from marketplace_store_orders s join marketplace_orders o on o.id=s.order_id where s.id=p_order and o.customer_id=p_customer for update of s;
 if not found or so.fulfillment_method not in ('standard_4_6h','standard_24h','urgent') then return 'unavailable'; end if;
 if so.confirmed_at is null or so.confirmed_at>now()-interval '24 hours' or so.status not in ('ACCEPTED','PROCESSING','READY_FOR_DISPATCH') then return 'unavailable'; end if;
 select * into task from delivery_tasks where store_order_id=p_order for update;
 if found and (task.partner_id is not null or task.status in ('picked_up','on_the_way','awaiting_customer_confirmation','completed','cancelled')) then return 'assigned'; end if;
 select b.details into store_details from businesses b where b.id=so.business_id and b.is_published for share;
 select lead_minutes into lead from pickup_settings where id=true for share;
 if store_details->'businessHours' is distinct from p_hours or store_details->'address' is distinct from p_address or lead is distinct from p_lead or p_end is distinct from p_start+interval '1 hour' or p_start<now()+make_interval(mins=>lead) then return 'changed'; end if;
 if task.id is not null then
  perform delivery_notice(task.id,p.user_id,false,'The customer chose store pickup; this delivery offer is no longer available.','pickup-switch-offer:'||task.id||':'||p.id) from delivery_allocation_attempts a join delivery_partner_profiles p on p.id=a.partner_id where a.task_id=task.id and a.status='offered';
  update delivery_allocation_attempts set status='unavailable',responded_at=now() where task_id=task.id and status='offered';
  update delivery_tasks set status='cancelled',updated_at=now() where id=task.id;
  perform delivery_log(task.id,p_customer,'switched_to_pickup',task.status,'cancelled','Customer chose pickup');
 end if;
 update delivery_order_allocation_jobs set status='cancelled',updated_at=now() where store_order_id=p_order;
 update marketplace_store_orders set fulfillment_method='pickup',delivery_fee=0,pickup_start=p_start,pickup_end=p_end,pickup_timezone=p_hours->>'timezone',pickup_store_address=p_address,status='PROCESSING' where id=p_order;
 if so.status<>'PROCESSING' then insert into marketplace_order_status_history(store_order_id,previous_status,new_status,changed_by) values(p_order,so.status,'PROCESSING',p_customer);end if;
 perform delivery_notice(null,b.owner_id,false,'The buyer chose store pickup for order '||so.store_order_number||'.','delivery-switch-pickup:'||p_order) from businesses b where b.id=so.business_id and b.owner_id is not null;
 return 'switched';
end $$;

create or replace function public.process_delivery_jobs() returns integer language plpgsql security definer set search_path=public as $$
declare t delivery_tasks%rowtype; a delivery_assignments%rowtype; n integer:=0; p delivery_partner_profiles%rowtype;
begin
 -- Across all server instances: one short database transaction owns allocation.
 if not pg_try_advisory_xact_lock(74901) then return 0; end if;
 for t in select * from delivery_tasks where status in ('independent_allocation','salaried_allocation','assigned','accepted','reached_pickup','picked_up','on_the_way','awaiting_customer_confirmation') order by case when urgency='urgent' then 0 else 1 end,updated_at limit 200 for update skip locked loop
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


-- New fulfillment orders enter allocation automatically; the legacy selector is only for historical orders.
create or replace function public.delivery_select_order(p_store_order uuid,p_actor uuid,p_admin boolean,p_details jsonb)
returns uuid language plpgsql security definer set search_path=public as $$
declare mode text;
begin
 select so.fulfillment_method into mode from marketplace_store_orders so where so.id=p_store_order and (p_admin is true or exists(select 1 from businesses b where b.id=so.business_id and b.owner_id=p_actor));
 if not found then raise exception 'Delivery access denied'; end if;
 if mode='pickup' then raise exception 'Self pickup orders cannot enter delivery allocation'; end if;
 if mode is not null then raise exception 'Delivery allocation starts automatically after confirmation'; end if;
 return delivery_select_order_legacy(p_store_order,p_actor,p_admin,p_details);
end $$;

-- Recalculate the estimate after a buyer changes pending order items.
create function public.refresh_pending_delivery_quote() returns trigger language plpgsql set search_path=public as $$
declare chosen uuid; rate numeric; base numeric;
begin
 if new.fulfillment_method not in ('standard_4_6h','standard_24h','urgent') or new.status<>'PENDING' then return new; end if;
 select f.id into chosen from marketplace_order_items i join products p on p.id=i.product_id join fleet_types f on f.id=p.fleet_type_id where i.store_order_id=new.id and f.active order by f.sort_rank desc,f.id limit 1;
 select (x->>'perKm')::numeric into rate from jsonb_array_elements(new.delivery_quote_config->'fleetRates') x where x->>'fleetId'=chosen::text;
 base:=(new.delivery_quote_config->'speeds'->new.fulfillment_method->>'base')::numeric;
 new.delivery_fleet_id:=chosen;
 new.delivery_fee:=case when rate is not null and base is not null and new.delivery_distance_km is not null then round(base+new.delivery_distance_km*rate,2) else null end;
 return new;
end $$;
create trigger pending_delivery_quote_refresh before update of edit_token on public.marketplace_store_orders for each row execute function public.refresh_pending_delivery_quote();

revoke all on function public.place_delivery_store_request(uuid,uuid,uuid,uuid,jsonb,text,uuid,numeric,numeric,jsonb,jsonb,jsonb),public.confirm_fulfillment_order(uuid,uuid,boolean,uuid,numeric,uuid),public.process_delivery_order_allocation(),public.switch_delivery_to_pickup(uuid,uuid,timestamptz,timestamptz,jsonb,jsonb,integer) from public,anon,authenticated;
grant execute on function public.place_delivery_store_request(uuid,uuid,uuid,uuid,jsonb,text,uuid,numeric,numeric,jsonb,jsonb,jsonb),public.confirm_fulfillment_order(uuid,uuid,boolean,uuid,numeric,uuid),public.process_delivery_order_allocation(),public.switch_delivery_to_pickup(uuid,uuid,timestamptz,timestamptz,jsonb,jsonb,integer) to service_role;
commit;
