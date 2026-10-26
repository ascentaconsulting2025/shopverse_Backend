\set ON_ERROR_STOP on
-- Disposable database only. Minimal entity shapes exercise the production trigger.
create role anon;
create role authenticated;
create role service_role;
create table businesses(id text primary key, logo_url text, logo_public_id text, details jsonb default '{}');
create table products(id text primary key, business_id text references businesses on delete cascade, image_url text, image_public_id text, images jsonb default '[]');
create table services(id text primary key, cover_image text, cover_image_public_id text);
create table events(id text primary key, poster_url text, poster_public_id text, deleted_at timestamptz);
create table offers(id text primary key, image_url text, image_public_id text, deleted_at timestamptz);
create table gallery_photos(id text primary key, image_url text, image_public_id text, deleted_at timestamptz);
create table business_people(id text primary key, profile_image_url text, profile_image_public_id text);
create table business_categories(id text primary key, image_url text);
\ir ../migrations/016_cloudinary_lifecycle.sql
create function assert_true(value boolean, message text) returns void language plpgsql as $$ begin if value is distinct from true then raise exception '%',message; end if; end $$;
insert into cloudinary_assets(public_id,secure_url,owner_id) select 'folder/'||n,'https://cloud.test/folder/'||n||'.png','00000000-0000-0000-0000-000000000001' from generate_series(1,8) n;
insert into businesses(id) values('business');
insert into products(id,business_id,image_url,images) values('p','business','https://cloud.test/folder/1.png','["https://cloud.test/folder/2.png","https://cloud.test/folder/3.png"]');
select assert_true((select image_public_id='folder/1' from products where id='p'),'exact upload ID populated');
insert into gallery_photos(id,image_url) values('shared','https://cloud.test/folder/1.png');
update products set image_url='https://cloud.test/folder/4.png',images='["https://cloud.test/folder/2.png","https://cloud.test/folder/4.png"]' where id='p';
select * from claim_cloudinary_cleanup();
select assert_true((select state='ready' from cloudinary_assets where public_id='folder/1'),'shared retained');
select assert_true((select state='ready' from cloudinary_assets where public_id='folder/2'),'unchanged gallery retained');
select assert_true((select state='deleting' from cloudinary_assets where public_id='folder/3'),'removed gallery queued');
select assert_true((select images='["https://cloud.test/folder/2.png","https://cloud.test/folder/4.png"]'::jsonb from products where id='p'),'gallery order retained');
update gallery_photos set deleted_at=now() where id='shared';
select * from claim_cloudinary_cleanup();
select assert_true((select state='deleting' from cloudinary_assets where public_id='folder/1'),'soft deletion queues last reference');
do $$ begin
 begin insert into products(id,image_url) values('race','https://cloud.test/folder/1.png'); raise exception 'Expected reuse rejection';
 exception when raise_exception then if SQLERRM not like 'Image is being deleted%' then raise; end if; end;
end $$;
begin;
update products set image_url='https://cloud.test/folder/5.png' where id='p';
rollback;
select assert_true((select image_public_id='folder/4' from products where id='p'),'failed transaction retains old image');
select assert_true((select cleanup_after>now() from cloudinary_assets where public_id='folder/4'),'rollback also rolls back cleanup');
update cloudinary_assets set cleanup_after=now() where public_id='folder/5';
select * from claim_cloudinary_cleanup();
select assert_true((select state='deleting' from cloudinary_assets where public_id='folder/5'),'failed save orphan is collected after grace period');
insert into products(id,image_url,image_public_id) values('legacy','https://external.test/legacy.png','invented');
select assert_true(not exists(select 1 from cloudinary_assets where public_id='invented'),'unverified identity never registered');
delete from businesses where id='business';
select * from claim_cloudinary_cleanup();
select assert_true((select state='deleting' from cloudinary_assets where public_id='folder/4'),'cascade cleanup');
select assert_true(not has_table_privilege('authenticated','cloudinary_assets','INSERT'),'ledger private');
select assert_true(not has_function_privilege('authenticated','claim_cloudinary_cleanup()','EXECUTE'),'claim private');
select 'Cloudinary database lifecycle checks passed';
