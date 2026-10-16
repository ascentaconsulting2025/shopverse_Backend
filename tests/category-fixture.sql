-- ONLY for a fresh, disposable PostgreSQL database; not a production schema.
create role anon;
create role authenticated;
create role service_role;
create schema auth;
create function auth.uid() returns uuid language sql stable as 'select null::uuid';
create table businesses(id uuid primary key,owner_id uuid,is_published boolean);
create table products(id uuid primary key,business_id uuid not null references businesses(id), name text, is_available boolean default true,updated_at timestamptz);
create table services(id uuid primary key,business_id uuid not null references businesses(id),name text,updated_at timestamptz);
alter table products enable row level security;
alter table services enable row level security;
create policy "Existing public products" on products for select using (exists(select 1 from businesses b where b.id=business_id and b.is_published));
create policy "Existing public services" on services for select using (exists(select 1 from businesses b where b.id=business_id and b.is_published));
grant usage on schema public,auth to anon;
grant select on all tables in schema public to anon;
alter default privileges in schema public grant select on tables to anon;
