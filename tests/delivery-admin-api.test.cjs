const {test}=require('node:test');
const assert=require('node:assert/strict');
const path=require('node:path');
const build=path.resolve(__dirname,'../dist');
const config=path.join(build,'config/supabaseClient.js');
let calls=[];
require.cache[config]={id:config,filename:config,loaded:true,exports:{supabaseAdmin:{rpc:async(name,args)=>{calls.push({name,args});return {data:{verification_status:'suspended'},error:null}}}}};
const router=require(path.join(build,'modules/delivery-partners/delivery-partners.routes.js')).default;
function run(isAdmin,body){const route=router.stack.find(layer=>layer.route?.path==='/admin/partners/:id/status').route;const handler=route.stack[route.stack.length-1].handle;return new Promise((resolve,reject)=>handler({isAdmin,user:{id:'actor-id'},params:{id:'cb000000-0000-4000-8000-000000000001'},body},{json:resolve},reject));}
test('partner status endpoint checks admin and forwards authenticated actor',async()=>{calls=[];await assert.rejects(run(false,{action:'suspend',reason:'review'}),e=>e.status===403);assert.equal(calls.length,0);await assert.rejects(run(true,{action:'suspend',reason:' '}));assert.equal(calls.length,0);const result=await run(true,{action:'suspend',reason:' review '});assert.equal(result.success,true);assert.deepEqual(calls[0],{name:'manage_delivery_partner_status',args:{p_partner:'cb000000-0000-4000-8000-000000000001',p_actor:'actor-id',p_action:'suspend',p_reason:'review'}});});
