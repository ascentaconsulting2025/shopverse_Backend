const {test}=require('node:test');
const assert=require('node:assert/strict');
const calls=[];
const tables={
 businesses:Array.from({length:20},(_,i)=>({id:'b'+i,slug:'shop'+i,business_name:'Shop '+i,is_published:true,feed_name:{en:'Shop '+i},global_category_id:'cat'})),
 business_categories:[{id:'cat',name:'Retail',status:'enabled',is_published:true}],
 products:[{id:'p',business_id:'b0',name:'Visible',description:'Description',price:10},{id:'hidden',business_id:'b0',name:'Hidden',folder_category_id:'missing'}],
 services:[],events:[],business_people:[]
};
const stub=(path,exports)=>{const id=require.resolve(path);require.cache[id]={id,filename:id,loaded:true,exports};};
stub('../dist/config/env.js',{env:{}});
stub('../dist/config/supabaseClient.js',{supabaseAdmin:{from(table){
 const call={table};calls.push(call);let start=0,end=999;
 const q={select(columns){call.columns=columns;return q;},eq(){return q;},or(){return q;},is(){return q;},in(){return q;},order(){return q;},range(a,b){start=a;end=b;return q;},then(resolve,reject){return Promise.resolve({data:structuredClone((tables[table]||[]).slice(start,end+1)),error:null}).then(resolve,reject);}};return q;
}}});
const {listMarketplace}=require('../dist/modules/business/business.controller.js');
const run=query=>new Promise((resolve,reject)=>listMarketplace({query},{json:resolve},reject));
test('marketplace bulk reads and compact payload preserve public listings',async()=>{
 calls.length=0;const {data}=await run({});
 assert.equal(calls.length,6); // Independent of the 20 businesses.
 assert.equal(data.length,21);
 const product=data.find(x=>x.type==='product');
 assert.equal(product.item.name.en,'Visible');
 assert.equal(product.business.category.en,'Retail');
 assert.equal(product.item.description.en,'Description');
 for(const row of data) for(const field of ['products','services','events','people']) assert.equal(row.business[field],undefined);
 assert.ok(!calls.some(c=>['offers','gallery_photos'].includes(c.table)));
});
test('business category skips all child tables',async()=>{
 calls.length=0;const {data}=await run({kind:'business'});
 assert.equal(data.length,20);
 assert.deepEqual(calls.map(c=>c.table),['businesses','business_categories']);
});
test('product category reads only products and searches in both languages',async()=>{
 calls.length=0;const {data}=await run({kind:'product',search:'description'});
 assert.equal(data.length,1);
 assert.deepEqual(calls.map(c=>c.table),['businesses','business_categories','products']);
});
test('initial viewport request loads business and products without below-fold tables',async()=>{
 calls.length=0;const {data}=await run({kind:'business,product'});
 assert.equal(data.length,21);
 assert.ok(data.every(row=>['business','product'].includes(row.type)));
 assert.deepEqual(calls.map(c=>c.table),['businesses','business_categories','products']);
});
test('deferred service request skips unrelated child tables',async()=>{
 calls.length=0;await run({kind:'service'});
 assert.deepEqual(calls.map(c=>c.table),['businesses','business_categories','services']);
});
