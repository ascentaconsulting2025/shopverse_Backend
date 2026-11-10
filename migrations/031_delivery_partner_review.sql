-- Application review transitions. Approval requires a recorded identity document;
-- document ingestion and policy-specific requirements must be configured separately.
begin;
create table public.delivery_partner_documents (
 id uuid primary key default gen_random_uuid(),
 partner_id uuid not null references public.delivery_partner_profiles(id) on delete restrict,
 document_type text not null check(document_type in ('identity','driving_licence','vehicle_registration','vehicle_photo','profile_photo')),
 storage_path text not null unique,
 created_at timestamptz not null default now()
);
create table public.delivery_partner_verifications (
 id uuid primary key default gen_random_uuid(),
 partner_id uuid not null references public.delivery_partner_profiles(id) on delete restrict,
 actor_id uuid not null references auth.users(id) on delete restrict,
 previous_status text not null, new_status text not null, reason text,
 created_at timestamptz not null default now()
);
alter table public.delivery_partner_documents enable row level security;
alter table public.delivery_partner_verifications enable row level security;
revoke all on public.delivery_partner_documents, public.delivery_partner_verifications from public, anon, authenticated;
grant all on public.delivery_partner_documents, public.delivery_partner_verifications to service_role;
create function public.submit_delivery_partner_application(p_user uuid) returns jsonb language plpgsql security definer set search_path=public as $$
declare profile public.delivery_partner_profiles%rowtype;
begin
 select * into profile from public.delivery_partner_profiles where user_id=p_user for update;
 if not found or profile.partner_type <> 'independent' or profile.verification_status not in ('draft','additional_information_required','rejected') then raise exception 'Application cannot be submitted'; end if;
 if coalesce(trim(profile.full_name),'')='' or coalesce(trim(profile.phone),'')='' or coalesce(trim(profile.current_address),'')='' or coalesce(trim(profile.city),'')='' or coalesce(trim(profile.service_area),'')='' or coalesce(trim(profile.emergency_contact),'')='' or coalesce(trim(profile.vehicle_type),'')='' or coalesce(trim(profile.vehicle_capacity),'')='' then raise exception 'Complete required application details'; end if;
 if not exists(select 1 from public.delivery_partner_documents where partner_id=profile.id and document_type='identity') then raise exception 'Identity document required'; end if;
 update public.delivery_partner_profiles set verification_status='pending_verification',updated_at=now() where id=profile.id returning * into profile;
 return to_jsonb(profile);
end $$;
create function public.review_delivery_partner_application(p_partner uuid,p_actor uuid,p_decision text,p_reason text) returns jsonb language plpgsql security definer set search_path=public as $$
declare profile public.delivery_partner_profiles%rowtype; old_status text;
begin
 if p_actor is null or p_decision not in ('approved','rejected','additional_information_required') then raise exception 'Invalid review'; end if;
 if p_decision <> 'approved' and coalesce(length(trim(p_reason)),0)=0 then raise exception 'Reason required'; end if;
 select * into profile from public.delivery_partner_profiles where id=p_partner for update;
 if not found or profile.verification_status not in ('pending_verification','under_review') then raise exception 'Application is not awaiting review'; end if;
 if p_decision='approved' and not exists(select 1 from public.delivery_partner_documents where partner_id=profile.id and document_type='identity') then raise exception 'Identity document required'; end if;
 old_status := profile.verification_status;
 update public.delivery_partner_profiles set verification_status=p_decision,updated_at=now() where id=profile.id returning * into profile;
 insert into public.delivery_partner_verifications(partner_id,actor_id,previous_status,new_status,reason) values(profile.id,p_actor,old_status,p_decision,nullif(trim(p_reason),''));
 return to_jsonb(profile);
end $$;
revoke all on function public.submit_delivery_partner_application(uuid), public.review_delivery_partner_application(uuid,uuid,text,text) from public,anon,authenticated;
grant execute on function public.submit_delivery_partner_application(uuid), public.review_delivery_partner_application(uuid,uuid,text,text) to service_role;
commit;
