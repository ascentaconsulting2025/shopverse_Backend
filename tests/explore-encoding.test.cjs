// Exercise the real Supabase/PostgREST request builder without network access.
const {test}=require('node:test');
const assert=require('node:assert/strict');
const {createClient}=require('@supabase/supabase-js');
const requests=[];
const db=createClient('https://catalog.example.test','test-service-key',{
 auth:{persistSession:false,autoRefreshToken:false},
 global:{fetch:async(url,init)=>{
  requests.push(new URL(String(url)));
  return new Response(JSON.stringify([{id:'item',name:'Starter'}]),{
   status:200,headers:{'Content-Type':'application/json','Content-Range':'0-0/1'}
  });
 }}
});
const config=require.resolve('../dist/config/supabaseClient.js');
require.cache[config]={id:config,filename:config,loaded:true,exports:{supabaseAdmin:db}};
const router=require('../dist/modules/explore/explore.routes.js').default;
function run(path,query){
 const handler=router.stack.find(s=>s.route?.path===path).route.stack[0].handle;
 return new Promise((resolve,reject)=>handler({query,params:{}},{json:resolve},reject));
}
test('product/service category ancestry is encoded as a JSON array in the actual HTTP query',async()=>{
 const node='30000000-0000-4000-8000-000000000003';
 for(const path of ['/products','/services']) {
  const response=await run(path,{category:'Food',node});
  const url=requests.at(-1);
  assert.equal(url.searchParams.get('category_path'),'cs.'+JSON.stringify([{id:node}]));
  assert.deepEqual(JSON.parse(url.searchParams.get('category_path').slice(3)),[{id:node}]);
  assert.equal(url.searchParams.get('category'),'eq.Food');
  assert.equal(url.searchParams.get('order'),'sort_order.asc,id.asc');
  assert.equal(response.data.total,1);
  assert.equal(response.data.items[0].id,'item');
 }
});
