const {test}=require('node:test'),assert=require('node:assert/strict'),path=require('node:path');
const root=process.env.SHOPVERSE_TEST_DIST;if(!root)throw new Error('Set SHOPVERSE_TEST_DIST');
const dbPath=path.join(root,'config/supabaseClient.js'),quotePath=path.join(root,'modules/fulfillment/delivery-quote.js');
const store='10000000-0000-4000-8000-000000000001',order='20000000-0000-4000-8000-000000000001',address='30000000-0000-4000-8000-000000000001',fleet='40000000-0000-4000-8000-000000000001',key='50000000-0000-4000-8000-000000000001';
let calls=[],row=null;
const chain={select(){return this},eq(){return this},maybeSingle:async()=>({data:row,error:null})};
require.cache[dbPath]={id:dbPath,filename:dbPath,loaded:true,exports:{supabaseAdmin:{from(){return chain},rpc:async(name,args)=>{calls.push({name,args});return {data:true,error:null}}}}};
require.cache[quotePath]={id:quotePath,filename:quotePath,loaded:true,exports:{quoteDeliveryCart:async()=>({fleet:{id:fleet},options:[{speed:'urgent',charge:40}],distanceKm:2,config:{},origin:{},destination:{}})}};
const router=require(path.join(root,'modules/orders/orders.routes.js')).default;
function run(route,method,req){const handler=router.stack.find(x=>x.route?.path===route&&x.route.methods[method]).route.stack.at(-1).handle;return new Promise((resolve,reject)=>handler({user:{id:'buyer'},params:{id:order},body:{},query:{},...req},{json:resolve},reject));}
test('rejects stale delivery quote before creating an order',async()=>{calls=[];row=null;await assert.rejects(run('/place-delivery','post',{body:{storeId:store,requestKey:key,addressId:address,method:'urgent',expectedFleetId:fleet,expectedFee:39,items:[{id:order,quantity:1,price:10}]}}),e=>e.status===409);assert.equal(calls.length,0)});
test('seller confirmation derives actor and sends the selected fleet',async()=>{calls=[];await run('/:id/confirm','post',{user:{id:'seller'},isAdmin:false,body:{expectedToken:key,closingPrice:15,fleetId:fleet}});assert.equal(calls[0].name,'confirm_fulfillment_order');assert.equal(calls[0].args.p_actor,'seller');assert.equal(calls[0].args.p_fleet,fleet)});
test('pickup switch rejects an order owned by another customer',async()=>{calls=[];row={business_id:store,marketplace_orders:{customer_id:'other'}};await assert.rejects(run('/:id/pickup/switch','post',{body:{pickupStart:'2030-01-01T10:00:00.000Z'}}),e=>e.status===404);assert.equal(calls.length,0)});
