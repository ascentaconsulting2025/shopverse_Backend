const {test,beforeEach}=require('node:test');
const assert=require('node:assert/strict');
let calls,profileError;
const stub=(path,exports)=>{const id=require.resolve(path);require.cache[id]={id,filename:id,loaded:true,exports}};
stub('../dist/config/supabaseClient.js',{
 createAuthClient:()=>{throw new Error('Admin provisioning must not sign in as the new user')},
 supabaseAdmin:{auth:{admin:{
  createUser:async input=>{calls.push(['create',input]);return {data:{user:{id:'created-user',email:input.email,created_at:'2026-10-22'}},error:null}},
  deleteUser:async id=>{calls.push(['delete',id]);return {error:null}},
 }},from:table=>({upsert:async input=>{calls.push(['profile',table,input]);return {error:profileError}}})},
});
const {createUser}=require('../dist/modules/auth/auth.controller.js');
const valid={full_name:'New Owner',email:'owner@example.com',password:'initial-test-password'};
const run=(body=valid,isAdmin=true)=>new Promise((resolve,reject)=>createUser({body,isAdmin},{status(){return this},json:resolve},reject));
beforeEach(()=>{calls=[];profileError=null});
test('admin credential creation is protected against non-admin requests',async()=>{
 await assert.rejects(run(valid,false),error=>error.status===403);assert.equal(calls.length,0);
});
test('admin can provision credentials without replacing their own session',async()=>{
 const result=await run();
 assert.equal(result.data.user.id,'created-user');
 assert.equal(result.data.session,undefined);
 assert.equal(result.data.user.password,undefined);
 assert.equal(calls[0][1].email_confirm,true);
 assert.deepEqual(calls[1],['profile','profiles',{id:'created-user',full_name:'New Owner'}]);
});
test('invalid credentials are rejected before creating an auth user',async()=>{
 for(const body of [{...valid,password:'short'},{...valid,email:'invalid'},{...valid,full_name:''}]) await assert.rejects(run(body));
 assert.equal(calls.length,0);
});
test('profile failure cleans up the newly provisioned account',async()=>{
 profileError={message:'Profile write failed'};
 await assert.rejects(run(),error=>error.status===500);
 assert.deepEqual(calls.at(-1),['delete','created-user']);
});
