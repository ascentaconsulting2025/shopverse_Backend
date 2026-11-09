-- Run after applying migration 029 to an isolated test database with Supabase roles.
-- All test changes are rolled back.
begin;
insert into auth.users(id) values ('db000000-0000-0000-0000-000000000001');
do $$
declare result jsonb;
begin
 result := public.save_delivery_partner_draft('db000000-0000-0000-0000-000000000001', '{"full_name":"Test Partner","verification_status":"approved","partner_type":"salaried"}'::jsonb);
 if result->>'verification_status' <> 'draft' or result->>'partner_type' <> 'independent' then
  raise exception 'Draft mutation elevated privileges';
 end if;
 if result->>'full_name' <> 'Test Partner' then raise exception 'Draft did not save'; end if;
 update public.delivery_partner_profiles set verification_status='approved' where user_id='db000000-0000-0000-0000-000000000001';
 begin
  perform public.save_delivery_partner_draft('db000000-0000-0000-0000-000000000001', '{"full_name":"Changed"}'::jsonb);
  raise exception 'Approved profile was editable';
 exception when raise_exception then
  if sqlerrm <> 'Application is not editable' then raise; end if;
 end;
 if has_function_privilege('authenticated','public.save_delivery_partner_draft(uuid,jsonb)','execute') then
  raise exception 'Authenticated role can impersonate an applicant';
 end if;
 if has_table_privilege('authenticated','public.delivery_partner_profiles','select') then
  raise exception 'Authenticated role can directly read partner profiles';
 end if;
end $$;
rollback;
