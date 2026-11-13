-- Disposable database only: contracts from inspected schema.
do $$ begin if not exists(select 1 from pg_roles where rolname='anon') then create role anon; create role authenticated; create role service_role bypassrls; end if; end $$;
create schema auth;
create table auth.users(id uuid primary key,email text,email_confirmed_at timestamptz,banned_until timestamptz);
create function auth.jwt() returns jsonb language sql stable as $$select coalesce(nullif(current_setting('request.jwt.claims',true),''),'{}')::jsonb$$;
create function auth.uid() returns uuid language sql stable as $$select nullif(auth.jwt()->>'sub','')::uuid$$;
grant usage on schema auth to anon,authenticated;
grant execute on all functions in schema auth to anon,authenticated;
create table profiles(id uuid primary key references auth.users(id),full_name text);
create table auth_sessions(id uuid primary key,user_id uuid references auth.users(id),expires_at timestamptz,revoked_at timestamptz);
create table businesses(id uuid primary key default gen_random_uuid(),owner_id uuid not null references profiles(id) on delete cascade,business_name text not null,slug text unique,status text default 'draft',created_at timestamptz default now(),updated_at timestamptz default now(),is_published boolean default false,is_verified boolean default false,plan_id text default 'basic',profile_views bigint default 0,details jsonb not null default '{}'::jsonb);
alter table businesses enable row level security;
create policy legacy_owner on businesses for all using(owner_id=auth.uid()) with check(owner_id=auth.uid());
create policy legacy_public on businesses for select using(is_published);
do $$ declare t text; begin
 foreach t in array array['products','services','events','offers','gallery_photos','business_section_visibility'] loop
 execute format('create table %I(id uuid primary key default gen_random_uuid(),business_id uuid references businesses(id),name text)',t);
 execute format('alter table %I enable row level security',t);
 end loop;
end $$;
create table business_people(id uuid primary key default gen_random_uuid(),business_id uuid references businesses(id),full_name_en text not null,full_name_mr text,designation_en text,designation_mr text,description_en text,description_mr text,profile_image_url text,profile_image_public_id text,display_order integer not null default 0 check(display_order>=0),is_primary boolean not null default false,is_active boolean not null default true);
alter table business_people enable row level security;
create unique index business_people_one_primary on business_people(business_id) where is_primary and is_active;
insert into auth.users(id,email,email_confirmed_at) values
 ('00000000-0000-4000-8000-000000000001','owner@example.test',now()),
 ('00000000-0000-4000-8000-000000000002','manager@example.test',now()),
 ('00000000-0000-4000-8000-000000000003','admin@example.test',now()),
 ('00000000-0000-4000-8000-000000000004','next@example.test',now()),
 ('00000000-0000-4000-8000-000000000005','outsider@example.test',now());
insert into profiles select id,email from auth.users;
insert into auth_sessions select id,id,now()+interval '1 day',null from auth.users;
insert into businesses(id,owner_id,business_name,slug) values('10000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-000000000001','Existing business','existing');
