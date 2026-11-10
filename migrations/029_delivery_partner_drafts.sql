-- Partner application drafts only. No verification or allocation is enabled.
begin;
create table public.delivery_partner_profiles (
 id uuid primary key default gen_random_uuid(),
 user_id uuid not null unique references auth.users(id) on delete restrict,
 partner_type text not null default 'independent' check (partner_type in ('independent','salaried')),
 verification_status text not null default 'draft' check (verification_status in ('draft','pending_verification','under_review','additional_information_required','approved','rejected','suspended','deactivated')),
 full_name text, phone text, email text, current_address text, city text, service_area text,
 emergency_contact text, vehicle_type text, vehicle_registration text, vehicle_capacity text,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
alter table public.delivery_partner_profiles enable row level security;
revoke all on public.delivery_partner_profiles from public, anon, authenticated;
grant all on public.delivery_partner_profiles to service_role;

-- A draft save cannot change partner type or verification status. Locking serializes review.
create function public.save_delivery_partner_draft(p_user uuid, p_data jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare profile public.delivery_partner_profiles%rowtype;
begin
 if p_user is null or jsonb_typeof(p_data) is distinct from 'object' then raise exception 'Invalid draft'; end if;
 insert into public.delivery_partner_profiles(user_id) values(p_user) on conflict(user_id) do nothing;
 select * into profile from public.delivery_partner_profiles where user_id=p_user for update;
 if profile.partner_type <> 'independent' or profile.verification_status not in ('draft','additional_information_required') then
  raise exception 'Application is not editable';
 end if;
 update public.delivery_partner_profiles set
  full_name=p_data->>'full_name', phone=p_data->>'phone', email=p_data->>'email',
  current_address=p_data->>'current_address', city=p_data->>'city', service_area=p_data->>'service_area',
  emergency_contact=p_data->>'emergency_contact', vehicle_type=p_data->>'vehicle_type',
  vehicle_registration=p_data->>'vehicle_registration', vehicle_capacity=p_data->>'vehicle_capacity', updated_at=now()
 where id=profile.id returning * into profile;
 return to_jsonb(profile);
end $$;
revoke all on function public.save_delivery_partner_draft(uuid,jsonb) from public, anon, authenticated;
grant execute on function public.save_delivery_partner_draft(uuid,jsonb) to service_role;
commit;
