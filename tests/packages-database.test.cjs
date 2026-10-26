// Use only a disposable database with schema + migrations 002-014 (or through 018) installed.
// PACKAGE_TEST_DATABASE_URL=postgresql://... node --test tests/packages-database.test.cjs
const { test } = require('node:test');
const assert = require('node:assert/strict');
const { execFileSync, execFile } = require('node:child_process');
const { promisify } = require('node:util');
const db = process.env.PACKAGE_TEST_DATABASE_URL;
const sql = query => execFileSync('psql', [db, '-X', '-qAt', '-v', 'ON_ERROR_STOP=1', '-c', query], { encoding: 'utf8', stdio: ['ignore','pipe','pipe'] }).trim();
const asyncSql = query => promisify(execFile)('psql', [db, '-X', '-qAt', '-v', 'ON_ERROR_STOP=1', '-c', query]);
const owner='00000000-0000-4000-8000-000000000001';
const business = plan => {
 const id=sql(`insert into businesses(owner_id,business_name,slug,plan_id,is_published) values('${owner}','Package test','test-'||gen_random_uuid(),'${plan}',true) returning id`);
 return id;
};
const product = (id, extra='') => `insert into products(business_id,name${extra ? ',is_published' : ''}) values('${id}','Product'${extra ? ','+extra : ''})`;
const event = (id,active=true) => `insert into events(business_id,event_name_en,event_date,start_time,venue_en,enquiry_number,is_active) values('${id}','Event','2026-10-22','10am','Pune','1234567890',${active})`;
const fails = (query, pattern) => assert.throws(() => sql(query), err => pattern.test(err.stderr || err.message));

test('package database permissions, quotas, verification and public reads', {skip: !db}, async t => {
 sql(`insert into auth.users(id) values('${owner}') on conflict do nothing; insert into profiles(id) values('${owner}') on conflict do nothing`);
 await t.test('Basic blocks direct create, bulk create and draft listings',()=>{
  const id=business('basic');
  fails(product(id),/Standard or Premium/);
  fails(product(id,'false'),/Standard or Premium/);
  fails(`insert into services(business_id,name,name_en,name_mr) values('${id}','Service','Service','')`,/Standard or Premium/);
  fails(`insert into offers(business_id,offer_title_en,coupon_code,validity_en,terms_en) values('${id}','Offer','A','Today','Terms')`,/Premium/);
  assert.equal(sql(`select count(*) from products where business_id='${id}'`),'0');
 });
 await t.test('all packages share gallery/event limits, inactive/deleted slots are released',()=>{
  for(const plan of ['basic','standard','premium']) {
   const id=business(plan);
   sql(`insert into gallery_photos(business_id,image_url) select '${id}','image-'||n from generate_series(1,20) n`);
   fails(`insert into gallery_photos(business_id,image_url) values('${id}','overflow')`,/maximum 20/);
   sql(`update gallery_photos set is_active=false where id=(select id from gallery_photos where business_id='${id}' limit 1)`);
   sql(`insert into gallery_photos(business_id,image_url) values('${id}','replacement')`);
   fails(`update gallery_photos set is_active=true where business_id='${id}' and not is_active`,/maximum 20/);
   for(let i=0;i<5;i++) sql(event(id));
   fails(event(id),/maximum 5/);
   sql(event(id,false));
   sql(`update events set deleted_at=now() where id=(select id from events where business_id='${id}' and is_active limit 1)`);
   sql(event(id));
   const pkg=JSON.parse(sql(`select get_business_package('${id}')`));
   assert.equal(pkg.usage.gallery,20); assert.equal(pkg.usage.events,5);
  }
 });
 await t.test('Standard and Premium product/service boundaries include drafts',()=>{
  for(const plan of ['standard','premium']) {
   const id=business(plan);
   sql(`insert into products(business_id,name,is_published) select '${id}','P'||n,false from generate_series(1,20) n`);
   fails(product(id),/maximum 20/);
   sql(`delete from products where id=(select id from products where business_id='${id}' limit 1)`);
   sql(product(id));
   sql(`insert into services(business_id,name,name_en,name_mr) select '${id}','S'||n,'S'||n,'' from generate_series(1,20) n`);
   fails(`insert into services(business_id,name,name_en,name_mr) values('${id}','S','S','')`,/maximum 20/);
  }
 });
 await t.test('two concurrent requests at 19 products admit exactly one',async()=>{
  const id=business('standard');
  sql(`insert into products(business_id,name) select '${id}','P'||n from generate_series(1,19) n`);
  const outcomes=await Promise.allSettled([asyncSql(`begin; ${product(id)}; select pg_sleep(0.2); commit;`),asyncSql(product(id))]);
  assert.equal(outcomes.filter(o=>o.status==='fulfilled').length,1);
  assert.equal(sql(`select count(*) from products where business_id='${id}'`),'20');
  assert.equal(JSON.parse(sql(`select get_business_package('${id}')`)).usage.products,20);
 });
 await t.test('bulk overflow rolls back the whole statement and usage',()=>{
  const id=business('standard');
  fails(`insert into products(business_id,name) select '${id}','P'||n from generate_series(1,21) n`,/maximum 20/);
  assert.equal(sql(`select count(*) from products where business_id='${id}'`),'0');
  assert.equal(JSON.parse(sql(`select get_business_package('${id}')`)).usage.products || 0,0);
 });
 await t.test('Standard verification occurs at exactly 10000 trusted views, deduplicated per day',()=>{
  const id=business('standard');
  sql(`update businesses set profile_views=9999 where id='${id}'`);
  assert.equal(sql(`select is_verified from businesses where id='${id}'`),'f');
  const slug=sql(`select slug from businesses where id='${id}'`);
  const result=JSON.parse(sql(`select record_business_profile_view('${slug}','${'a'.repeat(64)}')`));
  assert.equal(result.totalViews,10000); assert.equal(result.isVerified,true);
  assert.equal(JSON.parse(sql(`select record_business_profile_view('${slug}','${'a'.repeat(64)}')`)).totalViews,10000);
 });
 await t.test('Premium activation immediately grants the same badge; downgrades preserve it and content',()=>{
  const id=business('standard');
  sql(`update businesses set profile_views=100 where id='${id}'`);
  sql(product(id,'false')); sql(product(id));
  sql(`update businesses set plan_id='premium' where id='${id}'`);
  assert.equal(sql(`select is_verified from businesses where id='${id}'`),'t');
  sql(`update businesses set details='{"themeColor":"#123456"}' where id='${id}'`);
  sql(`insert into offers(business_id,offer_title_en,coupon_code,validity_en,terms_en) select '${id}','Offer','CODE-'||n,'Today','Terms' from generate_series(1,30) n`);
  sql(`update businesses set plan_id='basic' where id='${id}'`);
  assert.equal(sql(`select is_verified from businesses where id='${id}'`),'t');
  assert.equal(sql(`select details->>'themeColor' from businesses where id='${id}'`),'#123456');
  assert.equal(sql(`select count(*) from products where business_id='${id}'`),'2');
  fails(`update products set is_published=true where business_id='${id}' and is_published=false`,/Standard or Premium/);
  fails(`update businesses set details='{"themeColor":"#999999"}' where id='${id}'`,/Premium/);
 });
 await t.test('Basic manual verification is preserved; Basic does not auto-verify at 10000',()=>{
  const id=business('basic'); sql(`update businesses set profile_views=10000 where id='${id}'`);
  assert.equal(sql(`select is_verified from businesses where id='${id}'`),'f');
  sql(`update businesses set is_verified=true where id='${id}'`);
  sql(`update businesses set business_name='Updated' where id='${id}'`);
  assert.equal(sql(`select is_verified from businesses where id='${id}'`),'t');
 });
 await t.test('anonymous marketplace remains readable and private write/RPC bypasses are denied',()=>{
  // Production Supabase default grants; migration must revoke privileged writes.
  sql('grant usage on schema public,auth to anon,authenticated; grant select on businesses,products,services,business_categories to anon,authenticated');
  assert.equal(sql('set role anon; select count(*) > 0 from products'),'t');
  for(const role of ['anon','authenticated']) {
   fails(`set role ${role}; update businesses set plan_id='premium'`,/permission denied/);
   fails(`set role ${role}; update businesses set is_verified=true`,/permission denied/);
   fails(`set role ${role}; select record_business_profile_view('x','${'a'.repeat(64)}')`,/permission denied/);
   fails(`set role ${role}; update business_package_usage set used=0`,/permission denied/);
  }
 });
 await t.test('folder, section, profile and folder-move republication cannot bypass Basic',()=>{
  const id=business('standard'); sql(product(id));
  const global=sql("select exists(select 1 from information_schema.columns where table_name='business_categories' and column_name='parent_id')")==='t';
  const category=sql(`insert into business_categories(business_id,type,name,${global?'status':'is_published'}) values('${id}','product','Hidden',${global?"'enabled'":'false'}) returning id`);
  sql(`update products set folder_category_id='${category}' where business_id='${id}'`);
  if(global) sql(`update business_categories set status='disabled' where id='${category}'`);
  sql(`insert into business_section_visibility(business_id,products) values('${id}',false)`);
  sql(`update businesses set is_published=false,plan_id='basic' where id='${id}'`);
  fails(`update business_categories set is_published=true where id='${category}'`,/Standard or Premium/);
  fails(`update products set folder_category_id=null where business_id='${id}'`,/Standard or Premium/);
  fails(`update business_section_visibility set products=true where business_id='${id}'`,/Standard or Premium/);
  fails(`update businesses set is_published=true where id='${id}'`,/Standard or Premium/);
  sql(`update businesses set plan_id='standard',is_published=true where id='${id}'`);
  sql(`update business_categories set is_published=true where id='${category}'`);
 });
 await t.test('initial template customization also requires Premium',()=>{
  const id=business('basic');
  fails(`insert into businesses(owner_id,business_name,slug,plan_id,details) values('${owner}','Custom','custom-'||gen_random_uuid(),'basic','{"templateId":"emerald-luxury"}')`,/Premium/);
  sql(`update businesses set business_name='Still editable' where id='${id}'`);
 });
 await t.test('migration rerun reconciles existing eligible businesses and preserves manual badges',()=>{
  const standard=business('standard'), premium=business('premium'), basic=business('basic');
  sql(`alter table businesses disable trigger apply_package; update businesses set profile_views=10000,is_verified=false where id='${standard}'; update businesses set is_verified=false where id='${premium}'; update businesses set is_verified=true where id='${basic}'; alter table businesses enable trigger apply_package`);
  execFileSync('psql',[db,'-X','-q','-v','ON_ERROR_STOP=1','-f',require('node:path').join(__dirname,'../migrations/014_business_packages.sql')],{stdio:['ignore','pipe','pipe']});
  // Preserve chronological migration ordering when exercising a newer installation.
  if(sql("select exists(select 1 from information_schema.columns where table_name='business_categories' and column_name='parent_id')")==='t') execFileSync('psql',[db,'-X','-q','-v','ON_ERROR_STOP=1','-f',require('node:path').join(__dirname,'../migrations/018_global_category_architecture.sql')],{stdio:['ignore','pipe','pipe']});
  for(const id of [standard,premium,basic])assert.equal(sql(`select is_verified from businesses where id='${id}'`),'t');
 });
 await t.test('parent cascade deletes do not fail quota triggers',()=>{
  const id=business('standard'); sql(product(id)); sql(`delete from businesses where id='${id}'`);
  assert.equal(sql(`select count(*) from business_package_usage where business_id='${id}'`),'0');
 });
});
