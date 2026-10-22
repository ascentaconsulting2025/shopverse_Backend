-- ONLY a fresh disposable PostgreSQL database. Never run against an application DB.
\set ON_ERROR_STOP on
do $$ begin
 if not exists(select 1 from pg_roles where rolname='anon') then create role anon; end if;
 if not exists(select 1 from pg_roles where rolname='authenticated') then create role authenticated; end if;
 if not exists(select 1 from pg_roles where rolname='service_role') then create role service_role bypassrls; end if;
end $$;
create schema auth;
create function auth.uid() returns uuid language sql stable as 'select null::uuid';
create table auth.users(id uuid primary key);
grant usage on schema public, auth to anon, authenticated, service_role;
alter default privileges in schema public grant all on tables to anon, authenticated, service_role;
\ir ../schema.sql
-- schema.sql already incorporates 001; supply the historic columns expected by 008.
alter table businesses add column instagram_url text, add column facebook_url text,
 add column linkedin_url text, add column youtube_url text, add column website_url text;
\ir ../migrations/002_create_events_offers_gallery.sql
\ir ../migrations/003_unique_business_slugs.sql
\ir ../migrations/004_create_business_visibility.sql
\ir ../migrations/005_add_business_marathi_fields.sql
\ir ../migrations/006_add_logo_public_id.sql
\ir ../migrations/007_add_image_public_ids.sql
\ir ../migrations/008_add_dynamic_social_links.sql
\ir ../migrations/009_optional_prices_and_business_people.sql
\ir ../migrations/010_category_folders.sql
\ir ../migrations/011_bilingual_category_names.sql
\ir ../migrations/012_explore_catalog.sql
\ir ../migrations/013_explore_services.sql
\ir ../migrations/014_business_packages.sql
