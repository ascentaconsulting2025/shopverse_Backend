-- Super-admin mediated partner suspension/reactivation; no delivery tasks are changed.
begin;
create function public.manage_delivery_partner_status(p_partner uuid,p_actor uuid,p_action text,p_reason text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare profile public.delivery_partner_profiles%rowtype; old_status text; next_status text;
begin
 if p_actor is null or p_action not in ('suspend','reactivate') or length(trim(coalesce(p_reason,''))) not between 1 and 1000 then raise exception 'Invalid action'; end if;
 select * into profile from public.delivery_partner_profiles where id=p_partner for update;
 if not found then raise exception 'Partner not found'; end if;
 old_status := profile.verification_status;
 if (p_action='suspend' and old_status <> 'approved') or (p_action='reactivate' and old_status <> 'suspended') then raise exception 'Partner status changed'; end if;
 next_status := case when p_action='suspend' then 'suspended' else 'approved' end;
 update public.delivery_partner_profiles set verification_status=next_status,updated_at=now() where id=profile.id returning * into profile;
 if p_action='suspend' then update public.delivery_partner_availability set is_online=false,updated_at=now() where partner_id=profile.id; end if;
 insert into public.delivery_partner_verifications(partner_id,actor_id,previous_status,new_status,reason) values(profile.id,p_actor,old_status,next_status,trim(p_reason));
 return jsonb_build_object('id',profile.id,'verification_status',profile.verification_status);
end $$;
revoke all on function public.manage_delivery_partner_status(uuid,uuid,text,text) from public,anon,authenticated;
grant execute on function public.manage_delivery_partner_status(uuid,uuid,text,text) to service_role;
commit;
