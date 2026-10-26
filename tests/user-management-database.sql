\set ON_ERROR_STOP on
-- Run ONLY in an empty disposable PostgreSQL database; models the relevant Supabase tables.
create role anon; create role authenticated; create role service_role;
create schema auth;
create table auth.users(id uuid primary key,email text,raw_app_meta_data jsonb default '{}',raw_user_meta_data jsonb default '{}',created_at timestamptz default now(),last_sign_in_at timestamptz,email_confirmed_at timestamptz,banned_until timestamptz,encrypted_password text);
create table public.profiles(id uuid primary key references auth.users(id),full_name text);
create table public.auth_sessions(id uuid primary key,user_id uuid,revoked_at timestamptz);
\ir ../migrations/017_user_management.sql
insert into auth.users(id,email) values('11111111-1111-4111-8111-111111111111','admin@example.com');
insert into auth.users(id,email,raw_app_meta_data) values('22222222-2222-4222-8222-222222222222','owner@example.com','{"created_by":"11111111-1111-4111-8111-111111111111"}');
insert into public.auth_sessions(id,user_id) values('33333333-3333-4333-8333-333333333333','22222222-2222-4222-8222-222222222222');
do $$ declare result jsonb; begin
 result:=public.management_users(array['admin@example.com']);
 assert (result->>'total')::int=2;
 assert result->'users'->0 ? 'created_by';
 assert result::text not like '%encrypted_password%';
 assert result::text not like '%raw_app_meta_data%';
 assert (select actor_id='11111111-1111-4111-8111-111111111111'::uuid from public.user_management_audit where target_id='22222222-2222-4222-8222-222222222222');
 assert not has_table_privilege('authenticated','public.user_management_audit','SELECT');
 assert not has_table_privilege('authenticated','public.user_management_audit','INSERT');
 assert not has_function_privilege('authenticated','public.management_users(text[],text,text,text,timestamptz,timestamptz,text,boolean,integer,uuid)','EXECUTE');
 assert not has_function_privilege('anon','public.management_update_profile(uuid,uuid,text)','EXECUTE');
end $$;
select public.management_update_profile('11111111-1111-4111-8111-111111111111','22222222-2222-4222-8222-222222222222','Alice Owner');
update auth.users set encrypted_password='test-hash-only' where id='22222222-2222-4222-8222-222222222222';
do $$ declare result jsonb; begin
 assert (select revoked_at is not null from public.auth_sessions limit 1);
 assert exists(select 1 from public.user_management_audit where action='password_changed');
 result:=public.management_users(array['admin@example.com'],search_text=>'Alice',role_filter=>'user');
 assert (result->>'total')::int=1;
 assert result->'users'->0->>'full_name'='Alice Owner';
 result:=public.management_users(array['admin@example.com'],search_text=>'missing');
 assert result->'users'='[]'::jsonb;
end $$;
update public.auth_sessions set revoked_at=null;
update auth.users set banned_until=now()+interval '1 day' where id='22222222-2222-4222-8222-222222222222';
do $$ declare result jsonb; begin
 assert (select revoked_at is not null from public.auth_sessions limit 1);
 result:=public.management_users(array['admin@example.com'],status_filter=>'inactive');
 assert (result->>'total')::int=1;
 assert (result->'summary'->>'inactive')::int=1;
end $$;
insert into auth.users(id,email) select gen_random_uuid(),'user'||g||'@example.com' from generate_series(1,30) g;
do $$ declare result jsonb; begin
 result:=public.management_users(array['admin@example.com'],page_number=>2);
 assert jsonb_array_length(result->'users')=7;
 result:=public.management_users(array['admin@example.com'],date_from=>now()+interval '1 day');
 assert (result->>'total')::int=0;
 result:=public.management_users(array['admin@example.com'],sort_key=>'name',descending=>true);
 assert result->'users'->0->>'full_name'='Alice Owner';
end $$;
