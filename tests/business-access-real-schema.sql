\set ON_ERROR_STOP on
insert into auth.users(id,email,email_confirmed_at) values
 ('00000000-0000-4000-8000-000000000001','owner@example.test',now()),
 ('00000000-0000-4000-8000-000000000002','manager@example.test',now()),
 ('00000000-0000-4000-8000-000000000003','admin@example.test',now());
insert into auth.sessions(id) select id from auth.users;
insert into public.profiles(id,full_name) select id,email from auth.users;
insert into public.auth_sessions(id,user_id,expires_at) select id,id,now()+interval '1 day' from auth.users;
insert into public.business_access_admins(email) values('admin@example.test');
insert into public.business_categories(id,name,catalog_kind,status,is_published) values('20000000-0000-4000-8000-000000000001','Business category','business','enabled',true);
create function public.test_access_assert(ok boolean,message text) returns void language plpgsql as $$ begin if ok is not true then raise exception 'ASSERTION: %',message; end if; end $$;
set role authenticated;
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000001","session_id":"00000000-0000-4000-8000-000000000001"}',false);
select business_create_with_people('{"owner_id":"00000000-0000-4000-8000-000000000001","global_category_id":"20000000-0000-4000-8000-000000000001","business_name":"Draft business","slug":"realistic-draft","status":"draft","is_published":false,"is_verified":false,"plan_id":"basic","details":{}}','[{"full_name_en":"Leader","is_primary":true,"is_active":true}]')->>'id' as business_id \gset
select business_invite(:'business_id','manager@example.test',repeat('a',64),7);
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000002","session_id":"00000000-0000-4000-8000-000000000002"}',false);
select business_accept_invitation(repeat('a',64));
select test_access_assert(business_can_manage(:'business_id'),'Manager access');
select test_access_assert(business_role(:'business_id')='manager','Manager role');
-- Test a manager's actual business edit against the package and media triggers.
update businesses set business_name='Manager edited business' where id=:'business_id' returning business_name;
-- Products are package-controlled; default Basic may prohibit them. Test an existing permission-aware category operation separately.
select test_access_assert((select count(*)=1 from business_people where business_id=:'business_id'),'Manager can read draft leadership');
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000003","session_id":"00000000-0000-4000-8000-000000000003"}',false);
select business_create_with_people('{"owner_id":null,"global_category_id":"20000000-0000-4000-8000-000000000001","business_name":"Unassigned business","slug":"realistic-unassigned","status":"draft","is_published":false,"is_verified":false,"plan_id":"basic","details":{}}','[]')->>'id' as unassigned_id \gset
select business_change_access(:'unassigned_id','assign_owner','00000000-0000-4000-8000-000000000002',null,'remove','revoke');
select test_access_assert((select owner_id='00000000-0000-4000-8000-000000000002'::uuid from businesses where id=:'unassigned_id'),'admin owner assignment');
select 'Full checked-in schema integration passed' as result;
