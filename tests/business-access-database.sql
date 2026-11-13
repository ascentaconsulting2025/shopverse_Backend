\set ON_ERROR_STOP on
create function test_assert(ok boolean,message text) returns void language plpgsql as $$ begin if ok is not true then raise exception 'ASSERTION: %',message; end if; end $$;
insert into business_access_admins values('admin@example.test');
select test_assert(not has_table_privilege('service_role','public.business_access_logs','INSERT'),'service role cannot forge access history');
select test_assert(not has_table_privilege('service_role','public.business_access_logs','UPDATE'),'service role cannot edit access history');
select test_assert(not has_table_privilege('service_role','public.business_access_logs','DELETE'),'service role cannot delete access history');
select test_assert((select count(*)=1 from business_members where role='owner'),'backfill');
select test_assert((select created_by is null and ownership_review_required from businesses limit 1),'unknown historical creator');
set role authenticated;
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000001","session_id":"00000000-0000-4000-8000-000000000001"}',false);
insert into businesses(id,owner_id,business_name,slug) values('10000000-0000-4000-8000-000000000002',auth.uid(),'Created business','created');
select test_assert((select count(*)=2 from business_members where role='owner'),'multiple businesses');
select test_assert((select created_by=auth.uid() from businesses where slug='created'),'creator');
select test_assert((business_find_user('10000000-0000-4000-8000-000000000001','manager@example.test')->>'id')='00000000-0000-4000-8000-000000000002','exact verified account search');
do $$ begin
 for i in 1..29 loop perform business_find_user('10000000-0000-4000-8000-000000000001','nobody@example.test'); end loop;
 begin
  perform business_find_user('10000000-0000-4000-8000-000000000001','nobody@example.test');
  raise exception 'Expected account-search rate limit';
 exception when sqlstate 'P4290' then null; end;
end $$;

-- INSERT RETURNING must work for unpublished businesses before the owner trigger finishes.
insert into businesses(id,owner_id,business_name,slug) values('10000000-0000-4000-8000-000000000004',auth.uid(),'Draft business','draft') returning id;
select test_assert((business_create_with_people('{"owner_id":"00000000-0000-4000-8000-000000000001","business_name":"Atomic business","slug":"atomic"}', '[{"full_name_en":"Leader","is_primary":true,"is_active":true}]')->>'slug')='atomic','atomic business creation');
select test_assert((select count(*)=1 from business_people p join businesses b on b.id=p.business_id where b.slug='atomic'),'leadership row created');
select business_create_with_people('{"owner_id":"00000000-0000-4000-8000-000000000001","business_name":"Retry business","slug":"retry-original"}', '[]', '30000000-0000-4000-8000-000000000001')->>'id' as retry_id \gset
select test_assert((business_create_with_people('{"owner_id":"00000000-0000-4000-8000-000000000001","business_name":"Retry business","slug":"retry-after-timeout"}', '[]', '30000000-0000-4000-8000-000000000001')->>'id')=:'retry_id','retry returns original business');
select test_assert((select count(*)=1 from businesses where business_name='Retry business'),'retry does not create duplicate business');
do $$ begin
 begin
  perform business_create_with_people('{"owner_id":"00000000-0000-4000-8000-000000000001","business_name":"Different business","slug":"retry-other"}', '[]', '30000000-0000-4000-8000-000000000001');
  raise exception 'Expected conflicting creation request rejection';
 exception when serialization_failure then null; end;
end $$;
do $$ begin
 begin
  perform business_create_with_people('{"owner_id":"00000000-0000-4000-8000-000000000001","business_name":"Must rollback","slug":"atomic-failure"}', '[{"full_name_en":"Leader","is_primary":true,"is_active":true,"display_order":-1}]');
  raise exception 'Expected leadership constraint error';
 exception when check_violation then null; end;
end $$;
select test_assert(not exists(select 1 from businesses where slug='atomic-failure'),'failed leadership rolls back business and membership');
do $$ begin
 begin update businesses set profile_views=999 where slug='created'; raise exception 'Expected protected metrics'; exception when insufficient_privilege then null; end;
 begin update businesses set created_at=now()-interval '10 years' where slug='created'; raise exception 'Expected protected creation time'; exception when insufficient_privilege then null; end;
end $$;

do $$ begin
 begin update businesses set owner_id='00000000-0000-4000-8000-000000000002' where slug='created'; raise exception 'Expected forbidden owner PATCH'; exception when insufficient_privilege then null; end;
 begin perform business_change_access('10000000-0000-4000-8000-000000000001','add_manager','00000000-0000-4000-8000-000000000002',null,'remove','revoke'); raise exception 'Expected owner cannot directly add Manager'; exception when insufficient_privilege then null; end;
end $$;
select business_invite('10000000-0000-4000-8000-000000000001','Manager@Example.test',repeat('a',64),7);
select test_assert(not exists(select 1 from business_members where user_id='00000000-0000-4000-8000-000000000002'),'invitation grants no access');
do $$ begin
 begin perform business_invite('10000000-0000-4000-8000-000000000001','manager@example.test',repeat('b',64),7); raise exception 'Expected duplicate rejection'; exception when unique_violation then null; end;
end $$;
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000005","session_id":"00000000-0000-4000-8000-000000000005"}',false);
do $$ begin
 begin perform business_accept_invitation(repeat('a',64)); raise exception 'Expected invited-email check'; exception when insufficient_privilege then null; end;
end $$;
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000002","session_id":"00000000-0000-4000-8000-000000000002"}',false);
select business_accept_invitation(repeat('a',64));
select test_assert(business_role('10000000-0000-4000-8000-000000000001')='manager','accepted role');
select test_assert((select count(*)=1 from business_members),'Manager privacy');
insert into products(business_id,name) values('10000000-0000-4000-8000-000000000001','Manager product');
update businesses set business_name='Manager edit' where id='10000000-0000-4000-8000-000000000001';
do $$ begin
 begin perform business_access_details('10000000-0000-4000-8000-000000000001'); raise exception 'Expected team privacy'; exception when insufficient_privilege then null; end;
 begin perform business_accept_invitation(repeat('a',64)); raise exception 'Expected single use'; exception when insufficient_privilege then null; end;
 begin insert into products(business_id,name) values('10000000-0000-4000-8000-000000000002','Forbidden'); raise exception 'Expected tenant isolation'; exception when insufficient_privilege then null; end;
end $$;
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000003","session_id":"00000000-0000-4000-8000-000000000003"}',false);
insert into businesses(id,owner_id,business_name,slug) values('10000000-0000-4000-8000-000000000003',null,'Unassigned','unassigned');
select test_assert((select owner_id is null and created_by=auth.uid() from businesses where slug='unassigned'),'admin creator not owner');
select business_change_access('10000000-0000-4000-8000-000000000003','assign_owner','00000000-0000-4000-8000-000000000004',null,'remove','revoke');
select business_change_access('10000000-0000-4000-8000-000000000001','transfer_owner','00000000-0000-4000-8000-000000000004','00000000-0000-4000-8000-000000000001','manager','revoke');
select test_assert((select role='manager' and status='active' from business_members where business_id='10000000-0000-4000-8000-000000000001' and user_id='00000000-0000-4000-8000-000000000001'),'previous owner explicitly retained');
select business_change_access('10000000-0000-4000-8000-000000000001','remove_manager','00000000-0000-4000-8000-000000000002',null,'remove','revoke');
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000002","session_id":"00000000-0000-4000-8000-000000000002"}',false);
select test_assert(not business_can_manage('10000000-0000-4000-8000-000000000001'),'immediate removal');
do $$ begin
 begin insert into products(business_id,name) values('10000000-0000-4000-8000-000000000001','Revoked write'); raise exception 'Expected removal enforcement'; exception when insufficient_privilege then null; end;
end $$;
reset role;
select test_assert((select count(*)>=5 from business_access_logs),'audit');
update auth_sessions set revoked_at=now() where user_id='00000000-0000-4000-8000-000000000004';
set role authenticated;
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000004","session_id":"00000000-0000-4000-8000-000000000004"}',false);
select test_assert(not business_can_manage('10000000-0000-4000-8000-000000000001'),'revoked session');
reset role;
begin;
delete from public.profiles where id='00000000-0000-4000-8000-000000000002';
select test_assert(not exists(select 1 from business_members where user_id='00000000-0000-4000-8000-000000000002'),'deleting a former Manager profile does not block or delete the business');
select test_assert(exists(select 1 from businesses where id='10000000-0000-4000-8000-000000000001'),'business survives former Manager profile deletion');
rollback;
select 'Business access database tests passed' as result;
