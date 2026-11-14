const {test}=require('node:test');
const assert=require('node:assert/strict');
const path=require('node:path');
const build=process.env.BUSINESS_ACCESS_BUILD_DIR||path.resolve(__dirname,'../dist');
const config=path.join(build,'config/env.js');
require.cache[config]={id:config,filename:config,loaded:true,exports:{env:{SUPABASE_URL:'https://example.supabase.co',SUPABASE_ANON_KEY:'anonymous-test-key',SUPABASE_SERVICE_ROLE_KEY:'private-test-key'}}};
const calls=[];
const accessPath=path.join(build,'modules/business-access/access.service.js');
const actual=require(accessPath);
test('invitation tokens have independent 256-bit randomness and only hashes persist',()=>{
 const a=actual.newInvitationToken(),b=actual.newInvitationToken();
 assert.match(a,/^[A-Za-z0-9_-]{43}$/);assert.notEqual(a,b);
 assert.match(actual.hashInvitation(a),/^[a-f0-9]{64}$/);assert.notEqual(actual.hashInvitation(a),a);
 assert.equal(actual.hashInvitation(a),actual.hashInvitation(a));
});
test('email delivery fails closed without configuration',()=>{
 delete process.env.BUSINESS_INVITATION_DELIVERY_URL;
 assert.throws(()=>actual.invitationDeliveryConfig(),/not configured/);
});
test('API validates authentication, confirmation and administrative boundaries',async()=>{
 process.env.BUSINESS_ACCESS_ENABLED='true';
 const guard=path.join(build,'middlewares/authGuard.js');
 require.cache[guard]={id:guard,filename:guard,loaded:true,exports:{authGuard:(req,res,next)=>{
  const role=req.headers.authorization;
  if(!role)return res.status(401).json({success:false});
  req.user={id:'00000000-0000-4000-8000-000000000001'};req.isAdmin=role==='admin';req.testRole=role;next();
 }}};
 const client=require(path.join(build,'config/supabaseClient.js'));
 const originalFrom=client.supabaseAdmin.from;
 client.supabaseAdmin.from=()=>({update:()=>({eq:async()=>({error:null})})});
 require.cache[accessPath].exports={...actual,requireBusinessAccess:async()=>'owner',
 invitationDeliveryConfig:()=>({endpoint:'https://example.test',secret:'test',app:'https://example.test'}),
 deliverInvitation:async()=>{throw new Error('delivery unavailable')},businessDb:req=>({rpc:async(name,args)=>{
  calls.push({role:req.testRole,name,args});
  if(req.testRole==='manager'&&name==='business_access_details')return {error:{code:'42501',message:'Access denied'}};
  return {data:name==='business_access_details'?{owner:null,managers:[],invitations:[],history:[]}:true};
 }})};
 const express=require('express');const app=express();app.use(express.json());app.use(require(path.join(build,'modules/business-access/access.routes.js')).default);
 app.use(require(path.join(build,'middlewares/errorHandler.js')).errorHandler);
 const server=app.listen(0,'127.0.0.1');await new Promise(resolve=>server.once('listening',resolve));
 const url=`http://127.0.0.1:${server.address().port}`;const bid='10000000-0000-4000-8000-000000000001';
 const send=(route,role,body)=>fetch(url+route,{method:body?'POST':'GET',headers:{...(role?{Authorization:role}:{}),'Content-Type':'application/json'},...(body?{body:JSON.stringify(body)}:{})});
 try {
 assert.equal((await send(`/businesses/${bid}/access`)).status,401);
 assert.equal((await send('/business-access/users/search','owner',{email:'test@example.test'})).status,403);
 assert.equal((await send(`/businesses/${bid}/access`,'manager')).status,403);
 const input={action:'add_manager',targetUserId:'00000000-0000-4000-8000-000000000002',expectedOwnerId:null,previousOwner:'remove',pendingInvitations:'revoke',confirmed:true};
 assert.equal((await send(`/businesses/${bid}/access/change`,'owner',input)).status,403);
 assert.equal((await send(`/businesses/${bid}/access/change`,'admin',{...input,confirmed:false})).status,400);
 assert.equal((await send(`/businesses/${bid}/access/change`,'admin',{...input,actor:'forged'})).status,400);
 assert.equal((await send(`/businesses/${bid}/access/change`,'admin',input)).status,200);
 const mutation=calls.find(c=>c.name==='business_change_access');assert.ok(mutation);assert.equal(mutation.args.p_target,input.targetUserId);assert.ok(!('actor' in mutation.args));
 assert.equal((await send('/business-invitations/accept','owner',{token:'invalid'})).status,400);
 const failedDelivery=await send(`/businesses/${bid}/access/invitations`,'owner',{email:'invitee@example.test'});
 assert.equal(failedDelivery.status,502);
 const failedBody=await failedDelivery.json();
 assert.equal(failedBody.error.code,'BUSINESS_INVITATION_DELIVERY_FAILED');
 assert.match(failedBody.error.message,/Revoke it before retrying/);
 process.env.BUSINESS_ACCESS_ENABLED='false';
 assert.equal((await send(`/businesses/${bid}/access`,'admin')).status,503);
 }finally{client.supabaseAdmin.from=originalFrom;await new Promise(resolve=>server.close(resolve));}
});
