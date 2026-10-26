// Run against the disposable database created by global-categories-database.sql.
const {test}=require('node:test');
const assert=require('node:assert/strict');
const {spawn}=require('node:child_process');
const connection=process.env.CATEGORY_TEST_DATABASE_URL;
function psql(sql){
 const child=spawn('psql',[connection,'-X','-v','ON_ERROR_STOP=1','-At'],{stdio:['pipe','pipe','pipe']});
 let output='',errors='',ready;
 const locked=new Promise(resolve=>ready=resolve);
 child.stdout.on('data',data=>{output+=data;if(output.includes('LOCKED'))ready();});child.stderr.on('data',data=>errors+=data);
 const done=new Promise((resolve,reject)=>{child.on('error',reject);child.on('close',code=>resolve({code,output,errors}));});
 child.stdin.end(sql);return {done,locked};
}
test('concurrent assignment, deletion, stale edits and hierarchy changes preserve integrity',{skip:!connection},async t=>{
 const url=new URL(connection);assert.equal(url.searchParams.get('host'),'/tmp');assert.equal(url.port,'55438');assert.match(url.pathname,/shopverse_categories_test/);
 const create=async(name)=>{
  const result=await psql(`select write_global_category(null,null,jsonb_build_object('name','${name}'),false)->>'id';`).done;
  assert.equal(result.code,0,result.errors);return result.output.trim().split('\n').at(-1);
 };
 await t.test('a committed assignment blocks a concurrent deletion',async()=>{
  const category=await create('Concurrent assignment');
  const a=psql(`begin;insert into products(business_id,name,folder_category_id) values('11111111-1111-4111-8111-111111111111','Concurrent item', '${category}');\n\\echo LOCKED\nselect pg_sleep(0.5);commit;`);
  await a.locked;const b=psql(`select write_global_category('${category}',1,'{}',true);`);
  assert.equal((await a.done).code,0);const denied=await b.done;assert.notEqual(denied.code,0);assert.match(denied.errors,/foreign key constraint/);
 });
 await t.test('a committed deletion blocks a concurrent new assignment',async()=>{
  const category=await create('Concurrent deletion');
  const a=psql(`begin;select write_global_category('${category}',1,'{}',true);\n\\echo LOCKED\nselect pg_sleep(0.5);commit;`);
  await a.locked;const b=psql(`insert into products(business_id,name,folder_category_id) values('11111111-1111-4111-8111-111111111111','Orphan attempt','${category}');`);
  assert.equal((await a.done).code,0);const denied=await b.done;assert.notEqual(denied.code,0);assert.match(denied.errors,/unavailable|foreign key/);
 });
 await t.test('concurrent edits using one version cannot silently overwrite',async()=>{
  const category=await create('Concurrent version');
  const a=psql(`begin;select write_global_category('${category}',1,'{"name":"First"}',false);\n\\echo LOCKED\nselect pg_sleep(0.5);commit;`);
  await a.locked;const b=psql(`select write_global_category('${category}',1,'{"name":"Second"}',false);`);
  assert.equal((await a.done).code,0);const denied=await b.done;assert.notEqual(denied.code,0);assert.match(denied.errors,/changed/);
 });
 await t.test('concurrent reparenting cannot create a cycle',async()=>{
  const left=await create('Cycle left'),right=await create('Cycle right');
  const a=psql(`begin;select write_global_category('${left}',1,'{"parent_id":"${right}"}',false);\n\\echo LOCKED\nselect pg_sleep(0.5);commit;`);
  await a.locked;const b=psql(`select write_global_category('${right}',1,'{"parent_id":"${left}"}',false);`);
  assert.equal((await a.done).code,0);const denied=await b.done;assert.notEqual(denied.code,0);assert.match(denied.errors,/ancestor/);
 });
 await t.test('ancestor disabling serializes with a new child selection',async()=>{
  const parent=await create('Disable parent');const result=await psql(`select write_global_category(null,null,'{"name":"Disable child","parent_id":"${parent}"}',false)->>'id';`).done;
  assert.equal(result.code,0,result.errors);const child=result.output.trim();
  const a=psql(`begin;select write_global_category('${parent}',1,'{"status":"disabled"}',false);\n\\echo LOCKED\nselect pg_sleep(0.5);commit;`);
  await a.locked;const b=psql(`insert into products(business_id,name,folder_category_id) values('11111111-1111-4111-8111-111111111111','Disabled attempt','${child}');`);
  assert.equal((await a.done).code,0);const denied=await b.done;assert.notEqual(denied.code,0);assert.match(denied.errors,/unavailable/);
 });
});
