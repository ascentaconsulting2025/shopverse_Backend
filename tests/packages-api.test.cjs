const { test, beforeEach } = require('node:test');
const assert = require('node:assert/strict');
let plan, used, business, mutations, rpcCalls;
const rules={basic:{products:0,services:0,gallery:20,events:5,offers:0,themes:false,verificationViews:null},standard:{products:20,services:20,gallery:20,events:5,offers:0,themes:false,verificationViews:10000},premium:{products:20,services:20,gallery:20,events:5,offers:null,themes:true,verificationViews:0}};
function stub(path,exports){const filename=require.resolve(path);require.cache[filename]={id:filename,filename,loaded:true,exports};}
function from(table){
 let value,mode,filters=[];
 const result=single=>{
  if(mode){mutations.push({table,mode,value}); if(table==='businesses') Object.assign(business,value);}
  const rows=table==='businesses'?[business]:table==='products'?[{id:'product',business_id:'business',is_published:false}]:[];
  const found=rows.filter(row=>filters.every(([k,v])=>row[k]===v));
  return {data:mode&&table!=='businesses'?{id:'new',...value}:single?structuredClone(found[0]||null):structuredClone(found),error:null};
 };
 const q={select:()=>q,eq:(k,v)=>{filters.push([k,v]);return q},is:()=>q,order:()=>q,range:()=>q,
 insert:v=>{value=v;mode='insert';return q},update:v=>{value=v;mode='update';return q},
 single:async()=>result(true),maybeSingle:async()=>result(true),then:(a,b)=>Promise.resolve(result(false)).then(a,b)};
 return q;
}
stub('../dist/config/env.js',{env:{SUPABASE_SERVICE_ROLE_KEY:'test-secret-do-not-use'}});
stub('../dist/config/supabaseClient.js',{supabaseAdmin:{from,rpc:async(name,args)=>{rpcCalls.push({name,args});return {data:name==='get_business_package'?{planId:plan,capabilities:rules[plan],usage:used}:{totalViews:10000,isVerified:true},error:null}}}});
stub('../dist/utils/cloudinaryAsset.js',{cloudinaryPublicIdFromUrl:()=>null,deleteCloudinaryImage:async()=>{}});
const {protectBusinessFields,requirePackageFeature}=require('../dist/modules/packages/packages.service.js');
const controller=require('../dist/modules/business/business.controller.js');
const products=require('../dist/modules/products/products.controller.js');
const {makeContentController}=require('../dist/modules/content/content.controller.js');
const run=(handler,body={},overrides={})=>new Promise((resolve,reject)=>handler({params:{id:'business',businessId:'business',slug:'test'},body,user:{id:'owner'},isAdmin:false,...overrides},{status(){return this},json:resolve},reject));
beforeEach(()=>{plan='basic';used={products:0,services:0,gallery:0,events:0,offers:0};business={id:'business',slug:'test',business_name:'Test',owner_id:'owner',plan_id:plan,is_verified:false,is_published:true,details:{},profile_views:0};mutations=[];rpcCalls=[]});
test('owner cannot assign package or verify through create/update, including theme-free self-upgrades',async()=>{
 for(const body of [{planId:'premium'},{isVerified:true}]) {
  await assert.rejects(run(controller.createBusiness,{businessName:'Test',...body}),e=>e.status===403);
  await assert.rejects(run(controller.updateBusiness,body),e=>e.status===403);
 }
 assert.equal(mutations.length,0);
});
test('nested fields, legacy listing arrays and client counters are discarded',()=>{
 const input=protectBusinessFields({details:{planId:'premium',isVerified:true},plan_id:'premium',is_verified:true,profile_views:10000,profileViews:10000,stats:{totalViews:10000},owner_id:'other',products:[{}]},business,false);
 assert.equal(input.planId,'basic');assert.equal(input.isVerified,false);
 for(const key of ['details','plan_id','is_verified','profile_views','profileViews','stats','owner_id','products'])assert.equal(input[key],undefined);
});
test('direct Basic product and offer creation receive 403 before any write',async()=>{
 await assert.rejects(run(products.createProduct,{name:{en:'Test'}}),e=>e.status===403&&/Standard or Premium/.test(e.message));
 await assert.rejects(run(makeContentController('offers').create,{}),e=>e.status===403&&/Premium/.test(e.message));
 assert.equal(mutations.length,0);
});
test('creation requires ownership, even for an eligible package',async()=>{
 plan='standard';await assert.rejects(run(products.createProduct,{}, {user:{id:'other'}}),e=>e.status===403);assert.equal(mutations.length,0);
});
test('API quota boundary is 20; Premium offers have no new quota',async()=>{
 plan='standard';used.products=19;await requirePackageFeature('business','products',true);
 used.products=20;await assert.rejects(requirePackageFeature('business','products',true),e=>e.status===409&&/20/.test(e.message));
 plan='premium';used.offers=10000;await requirePackageFeature('business','offers',true);
});
test('Basic cannot republish a draft product',async()=>{
 await assert.rejects(run(products.updateProduct,{isPublished:true},{params:{id:'product'}}),e=>e.status===403);assert.equal(mutations.length,0);
});
test('usage is owner-only and returns canonical capabilities and counts',async()=>{
 await assert.rejects(run(controller.getBusinessUsage,{}, {user:{id:'other'}}),e=>e.status===403);
 const result=await run(controller.getBusinessUsage);assert.deepEqual(result.data.capabilities,rules.basic);assert.equal(result.data.usage.products,0);
});
test('admin package assignment and verification use the existing business state',async()=>{
 const result=await run(controller.updateBusiness,{planId:'premium',isVerified:true},{isAdmin:true});
 assert.equal(result.data.planId,'premium');assert.equal(result.data.isVerified,true);
 assert.equal(mutations.find(m=>m.table==='businesses').value.is_verified,true);
});
test('owner profile saves do not overwrite trusted columns, even with a full card',async()=>{
 await run(controller.updateBusiness,{businessName:'Updated',planId:'basic',isVerified:false,stats:{totalViews:99999}});
 const write=mutations.find(m=>m.table==='businesses').value;
 assert.equal(write.plan_id,undefined);assert.equal(write.is_verified,undefined);assert.equal(write.profile_views,undefined);
});
test('public view endpoint hashes server address and ignores supplied counters and IDs',async()=>{
 const req={ip:'127.0.0.1',socket:{},get:()=> 'test-agent'};
 const result=await run(controller.recordProfileView,{totalViews:999999,visitorHash:'attacker'},req);
 assert.equal(result.data.isVerified,true);
 assert.equal(rpcCalls[0].name,'record_business_profile_view');
 assert.match(rpcCalls[0].args.p_visitor_hash,/^[a-f0-9]{64}$/);
 assert.deepEqual(Object.keys(rpcCalls[0].args).sort(),['p_slug','p_visitor_hash']);
});
test('marketplace browsing and published business profiles remain public routes',()=>{
 const routes=require('../dist/modules/business/business.routes.js').default.stack;
 for(const path of ['/marketplace','/:slug']) {
  const route=routes.find(layer=>layer.route?.path===path).route;
  assert.equal(route.stack.length,1); // no authentication or package middleware
 }
});
test('package database errors retain clear HTTP permission/quota statuses',()=>{
 const {errorHandler}=require('../dist/middlewares/errorHandler.js');
 const original=console.error;console.error=()=>{};
 try {
  for(const [message,expected] of [['Products requires Standard or Premium',403],['Products limit reached (maximum 20)',409]]) {
   let status;
   errorHandler(new Error(message),{}, {status(s){status=s;return this},json(){}},()=>{});
   assert.equal(status,expected);
  }
 } finally { console.error=original; }
});

test('management listing isolates owners while preserving administrator access',async()=>{
 const own=await run(controller.listMyBusinesses);
 assert.deepEqual(own.data.map(card=>card.id),['business']);
 const other=await run(controller.listMyBusinesses,{}, {user:{id:'other',role:'admin'}});
 assert.deepEqual(other.data,[]); // Client metadata is not the server isAdmin flag.
 const admin=await run(controller.listMyBusinesses,{}, {user:{id:'other'},isAdmin:true});
 assert.deepEqual(admin.data.map(card=>card.id),['business']);
});
test('owners may edit existing content at quota; foreign owners may not edit',async()=>{
 plan='standard';used.products=20;
 const own=await run(products.updateProduct,{name:{en:'Updated'}},{params:{id:'product'}});
 assert.equal(own.success,true);
 const before=mutations.length;
 await assert.rejects(run(products.updateProduct,{name:{en:'Forbidden'}},{params:{id:'product'},user:{id:'other'}}),error=>error.status===403);
 assert.equal(mutations.length,before);
});
