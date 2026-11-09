-- Operational state is private and separate from application data.
begin;
create table public.delivery_partner_availability (
 partner_id uuid primary key references public.delivery_partner_profiles(id) on delete restrict,
 is_online boolean not null default false,
 latitude double precision check (latitude between -90 and 90),
 longitude double precision check (longitude between -180 and 180),
 accuracy_m double precision check (accuracy_m >= 0),
 location_recorded_at timestamptz,
 updated_at timestamptz not null default now(),
 check ((latitude is null) = (longitude is null)),
 check ((latitude is null) = (location_recorded_at is null))
);
alter table public.delivery_partner_availability enable row level security;
revoke all on public.delivery_partner_availability from public, anon, authenticated;
grant all on public.delivery_partner_availability to service_role;

create function public.set_delivery_partner_operational_state(p_user uuid, p_online boolean, p_lat double precision, p_lon double precision, p_accuracy double precision)
returns jsonb language plpgsql security definer set search_path = public as $$
declare profile public.delivery_partner_profiles%rowtype; state public.delivery_partner_availability%rowtype;
begin
 select * into profile from public.delivery_partner_profiles where user_id=p_user for update;
 if not found or profile.verification_status <> 'approved' then raise exception 'Approved profile required'; end if;
 -- Salaried shift rules are not yet configured; do not permit self-managed availability.
 if p_online is not null and profile.partner_type <> 'independent' then raise exception 'Availability managed by admin'; end if;
 if (p_lat is null) <> (p_lon is null) or (p_lat is not null and (p_lat not between -90 and 90 or p_lon not between -180 and 180 or p_accuracy is null or p_accuracy < 0)) then raise exception 'Invalid location'; end if;
 insert into public.delivery_partner_availability(partner_id) values(profile.id) on conflict do nothing;
 update public.delivery_partner_availability set
  is_online=coalesce(p_online,is_online), latitude=case when p_lat is null then latitude else p_lat end,
  longitude=case when p_lon is null then longitude else p_lon end,
  accuracy_m=case when p_lat is null then accuracy_m else p_accuracy end,
  location_recorded_at=case when p_lat is null then location_recorded_at else now() end,
  updated_at=now() where partner_id=profile.id returning * into state;
 return to_jsonb(state);
end $$;
revoke all on function public.set_delivery_partner_operational_state(uuid,boolean,double precision,double precision,double precision) from public, anon, authenticated;
grant execute on function public.set_delivery_partner_operational_state(uuid,boolean,double precision,double precision,double precision) to service_role;
commit;
