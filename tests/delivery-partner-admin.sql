-- Run after migrations 029, 030, 031 and 033 against an isolated test database.
begin;
insert into auth.users(id) values ('ca000000-0000-0000-0000-000000000001'),('ca000000-0000-0000-0000-000000000002');
insert into public.delivery_partner_profiles(id,user_id,verification_status) values ('cb000000-0000-0000-0000-000000000001','ca000000-0000-0000-0000-000000000001','approved');
insert into public.delivery_partner_availability(partner_id,is_online) values ('cb000000-0000-0000-0000-000000000001',true);
do $$
begin
 perform public.manage_delivery_partner_status('cb000000-0000-0000-0000-000000000001','ca000000-0000-0000-0000-000000000002','suspend','Verification issue');
 if (select verification_status from public.delivery_partner_profiles where id='cb000000-0000-0000-0000-000000000001') <> 'suspended' then raise exception 'Suspension not saved'; end if;
 if (select is_online from public.delivery_partner_availability where partner_id='cb000000-0000-0000-0000-000000000001') then raise exception 'Suspended partner still online'; end if;
 if (select count(*) from public.delivery_partner_verifications where partner_id='cb000000-0000-0000-0000-000000000001' and reason='Verification issue') <> 1 then raise exception 'Missing audit'; end if;
 begin
  perform public.manage_delivery_partner_status('cb000000-0000-0000-0000-000000000001','ca000000-0000-0000-0000-000000000002','suspend','again');
  raise exception 'Duplicate suspension accepted';
 exception when raise_exception then if sqlerrm <> 'Partner status changed' then raise; end if; end;
 perform public.manage_delivery_partner_status('cb000000-0000-0000-0000-000000000001','ca000000-0000-0000-0000-000000000002','reactivate','Verified');
 if (select verification_status from public.delivery_partner_profiles where id='cb000000-0000-0000-0000-000000000001') <> 'approved' or (select is_online from public.delivery_partner_availability where partner_id='cb000000-0000-0000-0000-000000000001') then raise exception 'Reactivation state incorrect'; end if;
 if has_function_privilege('authenticated','public.manage_delivery_partner_status(uuid,uuid,text,text)','execute') then raise exception 'Authenticated role can spoof an admin'; end if;
end $$;
rollback;
