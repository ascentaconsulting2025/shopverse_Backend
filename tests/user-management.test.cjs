const {test,beforeEach}=require('node:test');
const assert=require('node:assert/strict');
const id='11111111-1111-4111-8111-111111111111', actor='22222222-2222-4222-8222-222222222222';
let calls,target,providerError,invalidToken;
const stub=(path,exports)=>{const id=require.resolve(path);require.cache[id]={id,filename:id,loaded:true,exports}};
stub('../dist/config/supabaseClient.js',{
 supabaseAdmin:{
  rpc:async(name,args)=>{calls.push([name,args]);return {data:{users:[target],summary:{total:1},total:1},error:null}},
  from:()=>({insert:async row=>{calls.push(['audit',row]);return {error:null}}}),
  auth:{admin:{updateUserById:async(id,args)=>{calls.push(['update',id,args]);return {error:providerError}}}}
 },createAuthClient:()=>({auth:{
  resetPasswordForEmail:async(email,options)=>{calls.push(['email',email,options]);return {error:providerError}},
  verifyOtp:async args=>{calls.push(['verify',args]);return {data:invalidToken?{}:{user:{id},session:{}},error:invalidToken?{}:null}},
  updateUser:async args=>{calls.push(['password',args]);return {error:providerError}},
  signOut:async()=>{calls.push(['signout']);return {error:null}}
 }})
});
const m=require('../dist/modules/auth/userManagement.js');
const run=(handler,extra={})=>new Promise((resolve,reject)=>handler({params:{id},query:{},user:{id:actor},isAdmin:true,...extra},{json:resolve},reject));
beforeEach(()=>{calls=[];target={id,email:'owner@example.com',role:'user',status:'active',email_verified:true};providerError=null;invalidToken=false;process.env.PASSWORD_RESET_URL='https://example.com/reset-password'});
test('ordinary users are denied and rejection is audited',async()=>{
 await assert.rejects(run(m.requireSuperAdmin,{isAdmin:false}),e=>e.status===403);assert.equal(calls[0][1].outcome,'rejected');
});
test('search, filters and pagination are validated and forwarded to database',async()=>{
 await run(m.listUsers,{query:{search:'Jane',role:'user',status:'active',sort:'name',direction:'asc',page:'2'}});
 assert.equal(calls[0][1].page_number,2);assert.equal(calls[0][1].search_text,'Jane');assert.equal(calls[0][1].descending,false);
 await assert.rejects(run(m.listUsers,{query:{sort:'encrypted_password'}}));
 await assert.rejects(run(m.listUsers,{query:{page:'-1'}}));
});
test('all Super Admin accounts including the last are protected against every mutation',async()=>{
 target.role='admin';
 for(const action of ['reset','activate','deactivate'])await assert.rejects(run(m.mutateUser,{body:{action,confirmed:true}}),e=>e.status===403);
 await assert.rejects(run(m.mutateUser,{body:{action:'profile',full_name:'Changed'}}),e=>e.status===403);
 assert.ok(!calls.some(c=>['email','update','management_update_profile'].includes(c[0])));
});
test('confirmation, UUID validation and field allowlist prevent unsafe changes',async()=>{
 for(const body of [{action:'reset'},{action:'reset',confirmed:false},{action:'profile',full_name:'Name',role:'admin'}])await assert.rejects(run(m.mutateUser,{body}));
 await assert.rejects(run(m.mutateUser,{params:{id:'invalid'},body:{action:'reset',confirmed:true}}));assert.equal(calls.length,0);
});
test('recovery sends email through isolated provider and audits request/result without credentials',async()=>{
 const result=await run(m.mutateUser,{body:{action:'reset',confirmed:true}});
 assert.match(result.data.message,/accepted for delivery/);assert.equal(calls.find(c=>c[0]==='email')[1],target.email);
 assert.deepEqual(calls.filter(c=>c[0]==='audit').map(c=>c[1].outcome),['requested','success']);
 assert.ok(!JSON.stringify(result).includes('token'));
});
test('provider failures are sanitized and audited',async()=>{
 providerError={message:'secret internal provider metadata'};
 await assert.rejects(run(m.mutateUser,{body:{action:'reset',confirmed:true}}),e=>e.status===502&&!e.message.includes('secret'));
 assert.equal(calls.at(-1)[1].outcome,'failed');
});
test('unconfirmed and inactive accounts cannot receive recovery email',async()=>{
 target.email_verified=false;await assert.rejects(run(m.mutateUser,{body:{action:'reset',confirmed:true}}),e=>e.status===409);
 target.email_verified=true;target.status='inactive';await assert.rejects(run(m.mutateUser,{body:{action:'reset',confirmed:true}}),e=>e.status===409);
 assert.ok(!calls.some(c=>c[0]==='email'));
});
test('profile mutation uses transactional RPC with trusted actor',async()=>{
 await run(m.mutateUser,{body:{action:'profile',full_name:'New Name'}});
 assert.deepEqual(calls.at(-1),['management_update_profile',{actor,target:id,new_name:'New Name'}]);
});
test('expired/reused recovery tokens cannot change passwords',async()=>{
 invalidToken=true;await assert.rejects(run(m.completeRecovery,{body:{token_hash:'a'.repeat(64),password:'new-password'}}),e=>e.status===400);
 assert.ok(!calls.some(c=>c[0]==='password'));
});
test('completion verifies recovery type, enforces policy, signs out and returns no credentials',async()=>{
 const result=await run(m.completeRecovery,{body:{token_hash:'a'.repeat(64),password:'new-password'}});
 assert.equal(calls[0][1].type,'recovery');assert.equal(calls.at(-1)[0],'signout');
 assert.ok(!JSON.stringify(result).includes('new-password'));
 assert.ok(!JSON.stringify(calls.filter(c=>c[0]==='audit')).includes('new-password'));
 await assert.rejects(run(m.completeRecovery,{body:{token_hash:'a'.repeat(64),password:'short'}}));
});
