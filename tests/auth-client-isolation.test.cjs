const {test}=require('node:test');
const assert=require('node:assert/strict');
// Exercise the actual Supabase SDK and auth controllers without a real account.
const envPath=require.resolve('../dist/config/env.js');
const serviceKey='test-service-role-key';
require.cache[envPath]={id:envPath,filename:envPath,loaded:true,exports:{env:{SUPABASE_URL:'https://test.supabase.co',SUPABASE_SERVICE_ROLE_KEY:serviceKey,SUPABASE_ANON_KEY:'test-anon-key'}}};
const calls=[];
const token=Buffer.from('{}').toString('base64url')+'.'+Buffer.from(JSON.stringify({sub:'owner',role:'authenticated',exp:Math.floor(Date.now()/1000)+3600})).toString('base64url')+'.signature';
global.fetch=async(url,init={})=>{
 const headers=new Headers(init.headers);const body=init.body?JSON.parse(init.body):null;
 calls.push({url:String(url),authorization:headers.get('authorization'),body});
 if(String(url).includes('/auth/v1/token')) return new Response(JSON.stringify({access_token:token,refresh_token:'refresh',token_type:'bearer',expires_in:3600,user:{id:'owner',email:'owner@example.com',aud:'authenticated'}}),{status:200,headers:{'Content-Type':'application/json'}});
 if(String(url).includes('/auth/v1/admin/users')) return new Response(JSON.stringify({id:'owner',email:'owner@example.com'}),{status:200,headers:{'Content-Type':'application/json'}});
 if(String(url).includes('/rest/v1/rpc/')) {
  return headers.get('authorization')==='Bearer '+serviceKey
   ? new Response('null',{status:200,headers:{'Content-Type':'application/json'}})
   : new Response(JSON.stringify({code:'42501',message:'permission denied for function move_category_items'}),{status:403,headers:{'Content-Type':'application/json'}});
 }
 return new Response(null,{status:204});
};
const {supabaseAdmin,createAuthClient}=require('../dist/config/supabaseClient.js');
const {login,register}=require('../dist/modules/auth/auth.controller.js');
const run=(handler,body)=>new Promise((resolve,reject)=>handler({body},{status(){return this},json:resolve},reject));
test('login and registration do not replace the backend service role',async()=>{
 await run(login,{email:'owner@example.com',password:'Password123!'});
 assert.equal((await supabaseAdmin.auth.getSession()).data.session,null);
 let result=await supabaseAdmin.rpc('move_category_items',{p_business:'business',p_type:'product',p_ids:['product'],p_category:null});
 assert.equal(result.error,null);
 assert.equal(calls.at(-1).authorization,'Bearer '+serviceKey);
 assert.equal(calls.at(-1).body.p_category,null);
 await run(register,{email:'owner@example.com',password:'Password123!',full_name:'Owner'});
 assert.equal((await supabaseAdmin.auth.getSession()).data.session,null);
 result=await supabaseAdmin.rpc('reorder_categories',{p_business:'business',p_type:'product',p_ids:[]});
 assert.equal(result.error,null);
 const a=createAuthClient(),b=createAuthClient();
 await a.auth.signInWithPassword({email:'owner@example.com',password:'Password123!'});
 assert.equal((await b.auth.getSession()).data.session,null);
 assert.ok(calls.filter(c=>c.url.includes('/auth/v1/token')).every(c=>c.authorization==='Bearer test-anon-key'));
});
test('the former shared-client login reproduces the reported permission error',async()=>{
 const {createClient}=require('@supabase/supabase-js');
 const shared=createClient('https://test.supabase.co',serviceKey,{auth:{persistSession:false,autoRefreshToken:false,detectSessionInUrl:false}});
 await shared.auth.signInWithPassword({email:'owner@example.com',password:'Password123!'});
 const result=await shared.rpc('move_category_items',{p_business:'business',p_type:'product',p_ids:['product'],p_category:null});
 assert.equal(result.error.code,'42501');
 assert.match(result.error.message,/permission denied/);
});
