const {test,beforeEach}=require('node:test');
const assert=require('node:assert/strict');
const id='11111111-1111-4111-8111-111111111111';
let rows,calls,dbError,sessionError;
const stub=(path,exports)=>{const filename=require.resolve(path);require.cache[filename]={id:filename,filename,loaded:true,exports};};
stub('../dist/modules/auth/session.js',{assertSession:async()=>{if(sessionError)throw sessionError;}});
stub('../dist/config/supabaseClient.js',{supabaseAdmin:{
 auth:{getUser:async token=>({data:{user:token==='invalid'?null:{id:'owner',email:token==='admin'?'admin@example.com':'user@example.com',user_metadata:{role:'admin'}}},error:null})},
 from(table){const filters=[];let start=0,end=Infinity;const q={select:()=>q,order:()=>q,eq(k,v){filters.push([k,v]);return q},range(a,b){start=a;end=b;return q},single:async()=>({data:{owner_id:'owner'}}),then(resolve,reject){return Promise.resolve({data:rows.filter(r=>filters.every(([k,v])=>r[k]===v)).slice(start,end+1),error:dbError}).then(resolve,reject);}};return q;},
 rpc:async(name,args)=>{calls.push({name,args});return {data:{id,...args.p_fields},error:dbError};}
}});
const {globalCategoryRoutes,default:oldRouter}=require('../dist/modules/categories/categories.routes.js');
const {authGuard}=require('../dist/middlewares/authGuard.js');
const {parseCategoryImport}=require('../dist/modules/categories/import.js');
function run(method,path,{token='user',params={},body={},query={},extra={}}={}){
 const route=globalCategoryRoutes.stack.find(s=>s.route?.path===path && s.route.methods[method]).route;
 return invoke([authGuard,...route.stack.map(s=>s.handle)],{headers:token?{authorization:`Bearer ${token}`}:{},params,body,query,...extra});
}
function invoke(handlers,req){return new Promise((resolve,reject)=>{let status=200,index=0;const res={setHeader(){},status(n){status=n;return res},json(data){resolve({status,...data})},send(){resolve({status})}};const next=error=>{if(error)return reject(error);const handler=handlers[index++];if(handler)Promise.resolve(handler(req,res,next)).catch(reject);else resolve({status});};next();});}
beforeEach(()=>{process.env.ADMIN_EMAILS='admin@example.com';rows=[{id,name:'Global',name_mr:'जागतिक',status:'enabled',is_published:true,parent_id:null}];calls=[];dbError=null;sessionError=null;});
test('global list/detail require a valid authenticated, non-revoked session',async()=>{
 assert.equal((await run('get','/',{token:null})).status,401);
 assert.equal((await run('get','/',{token:'invalid'})).status,401);
 sessionError=Object.assign(new Error('Session revoked'),{status:401});await assert.rejects(run('get','/'),e=>e.status===401);
 sessionError=null;assert.equal((await run('get','/')).data.length,1);assert.equal((await run('get','/:id',{params:{id}})).data.name,'Global');
});
test('regular users cannot create, edit, delete, or import even with forged role fields',async()=>{
 for(const [method,path,body] of [['post','/',{name:'New'}],['patch','/:id',{name:'Changed',version:1}],['delete','/:id',{version:1}],['post','/import',{structure:{Root:['Child']},preview:false}]]){
  await assert.rejects(run(method,path,{params:{id},body,extra:{isAdmin:true,user:{role:'admin'}}}),e=>e.status===403);
 }
 assert.equal(calls.length,0);
});
test('Super Admin mutations use bounded allowlisted fields, UUIDs, and expected versions',async()=>{
 const result=await run('post','/',{token:'admin',body:{name:' New ',parent_id:null,status:'enabled',image_url:'https://example.com/image.jpg'}});
 assert.equal(result.status,201);assert.equal(calls[0].args.p_fields.name,'New');
 await run('patch','/:id',{token:'admin',params:{id},body:{name:'Edited',version:7}});assert.equal(calls.at(-1).args.p_version,7);
 await run('delete','/:id',{token:'admin',params:{id},body:{version:8}});assert.equal(calls.at(-1).args.p_delete,true);
 for(const body of [{name:''},{name:'x',business_id:id},{name:'x',isAdmin:true},{name:'x',status:'inactive'},{name:'x',image_url:'javascript:alert(1)'}])await assert.rejects(run('post','/',{token:'admin',body}));
 await assert.rejects(run('patch','/:id',{token:'admin',params:{id},body:{name:'No version'}}));
 await assert.rejects(run('delete','/:id',{token:'admin',params:{id:'invalid'},body:{version:1}}));
});
test('reference conflicts and stale edits return safe actionable errors',async()=>{
 for(const [code,status] of [['23503',409],['40001',409],['23514',400],['XX000',503]]){
  dbError={code,message:'internal secret database query'};
  await assert.rejects(run('delete','/:id',{token:'admin',params:{id},body:{version:1}}),e=>e.status===status&&!e.message.includes('secret'));
 }
});
test('category enabling preserves existing package permissions without leaking provider errors',async()=>{
 dbError={code:'P0001',message:'Products requires Standard or Premium'};
 await assert.rejects(run('patch','/:id',{token:'admin',params:{id},body:{status:'enabled',version:1}}),e=>e.status===403&&/require Standard or Premium/.test(e.message));
});
test('search, availability, and Marathi searches share the same global source',async()=>{
 rows.push({id:'child',name:'Child',status:'enabled',is_published:true,parent_id:id});rows[0].status='disabled';
 assert.equal((await run('get','/',{query:{available:'true'}})).data.length,0);
 assert.equal((await run('get','/',{query:{search:'जागतिक'}})).data[0].id,id);
 await assert.rejects(run('get','/:id',{params:{id:'22222222-2222-4222-8222-222222222222'}}),e=>e.status===404);
});
test('JSON import matches the legacy nested format, deduplicates paths, and enforces limits',async()=>{
 assert.deepEqual(parseCategoryImport({Fashion:{Women:['Clothing','Shoes',' shoes ']}}),[['Fashion'],['Fashion','Women'],['Fashion','Women','Clothing'],['Fashion','Women','Shoes']]);
 assert.throws(()=>parseCategoryImport({Root:123}));assert.throws(()=>parseCategoryImport([]));assert.throws(()=>parseCategoryImport(['x'.repeat(101)]));
 assert.throws(()=>parseCategoryImport(Array.from({length:1001},(_,i)=>`Name ${i}`)));
 await run('post','/import',{token:'admin',body:{structure:{Root:['Child']},preview:true}});
 assert.equal(calls[0].name,'import_global_categories');assert.equal(calls[0].args.p_preview,true);assert.deepEqual(calls[0].args.p_paths,[['Root'],['Root','Child']]);
});
test('legacy owner CRUD and reorder URLs cannot bypass global permissions',async()=>{
 for(const path of ['/:businessId/categories/:type','/:businessId/categories/:type/:id']){
  const route=oldRouter.stack.find(s=>s.route?.path===path && s.route.methods._all).route;
  await assert.rejects(invoke(route.stack.map(s=>s.handle),{isAdmin:false}),e=>e.status===403);
  await assert.rejects(invoke(route.stack.map(s=>s.handle),{isAdmin:true}),e=>e.status===410);
 }
});

test('mapping management and impact previews are restricted to Super Admin',async()=>{
 for(const [method,path,body] of [['get','/:id/mappings',{}],['get','/:id/impact',{}],['post','/:id/mappings/preview',{type:'product',categoryIds:[]}],['put','/:id/mappings',{type:'product',categoryIds:[],version:1}]]) {
  await assert.rejects(run(method,path,{params:{id},body}),e=>e.status===403);
 }
 assert.equal(calls.length,0);
});
test('mapping saves validate unique IDs, types and versions and use an atomic RPC',async()=>{
 await run('put','/:id/mappings',{token:'admin',params:{id},body:{type:'product',categoryIds:[id],version:3}});
 assert.equal(calls.at(-1).name,'replace_business_catalog_mappings');
 assert.deepEqual(calls.at(-1).args,{p_business_category:id,p_type:'product',p_categories:[id],p_version:3});
 for(const body of [{type:'product',categoryIds:[id,id],version:3},{type:'business',categoryIds:[],version:3},{type:'service',categoryIds:[]},{type:'product',categoryIds:['bad'],version:3}])
  await assert.rejects(run('put','/:id/mappings',{token:'admin',params:{id},body}));
 await run('post','/:id/mappings/preview',{token:'admin',params:{id},body:{type:'service',categoryIds:[]}});
 assert.equal(calls.at(-1).name,'catalog_assignment_impact');
});
test('typed JSON import keeps product and service trees explicit',async()=>{
 await run('post','/import',{token:'admin',body:{structure:{Gold:['Rings']},preview:true,kind:'product'}});
 assert.equal(calls.at(-1).name,'import_catalog_categories');assert.equal(calls.at(-1).args.p_kind,'product');
 await assert.rejects(run('post','/import',{token:'admin',body:{structure:{Gold:['Rings']},preview:false,kind:'business'}}));
});

test('architecture is admin-only and deletion refuses child branches before the RPC',async()=>{
 await assert.rejects(run('get','/architecture'),e=>e.status===403);
 rows.push({id:'child',name:'Child',catalog_kind:'product',parent_id:id,status:'enabled',is_published:true});
 await assert.rejects(run('delete','/:id',{token:'admin',params:{id},body:{version:1}}),e=>e.status===409&&/child/.test(e.message));
 assert.equal(calls.length,0);
});
test('normalized duplicates and invalid contextual parents never reach the write RPC',async()=>{
 rows[0].catalog_kind='product';
 await assert.rejects(run('post','/',{token:'admin',body:{name:' GLOBAL ',catalog_kind:'product'}}),e=>e.status===409&&/Already Exists/.test(e.message));
 await assert.rejects(run('post','/',{token:'admin',body:{name:'New',catalog_kind:'product',map_business_category_id:id}}),e=>e.status===404);
 assert.equal(calls.length,0);
});
