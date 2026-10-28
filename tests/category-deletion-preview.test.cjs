const {test,beforeEach}=require('node:test');
const assert=require('node:assert/strict');
const stub=(path,exports)=>{const filename=require.resolve(path);require.cache[filename]={id:filename,filename,loaded:true,exports};};
let categories, records, failing;
const selected='11111111-1111-4111-8111-111111111111';
stub('../dist/modules/categories/categories.service.js',{
 loadCategoryArchitecture:async()=>categories,
 loadMappings:async()=>['catalog'],
 categoryError:error=>{throw Object.assign(new Error('Database unavailable'),{status:503});},
});
stub('../dist/config/supabaseClient.js',{supabaseAdmin:{from(table){
 let filtered=records[table], countRequested=false;
 const q={select(columns,options){countRequested=options?.count==='exact';return q;},
  eq(column,value){filtered=filtered.filter(row=>row[column]===value);return q;},
  or(){filtered=filtered.filter(row=>row.folder_category_id===selected||row.category_id===selected);return q;},
  in(column,values){filtered=filtered.filter(row=>values.includes(row[column]));return q;},
  order(){return q;},range(start,end){return Promise.resolve(failing===table?{error:{code:'fail'}}:{data:filtered.slice(start,end+1),count:countRequested?filtered.length:null,error:null});},
  then(resolve,reject){return Promise.resolve(failing===table?{error:{code:'fail'}}:{data:filtered,error:null}).then(resolve,reject);},
 };return q;
}}});
const {categoryDeletionPreview}=require('../dist/modules/categories/deletion-preview.js');
beforeEach(()=>{
 categories=[{id:selected,name:'Parent',catalog_kind:'product',business_category_ids:['business'],direct_business_category_ids:['business']},{id:'business',name:'Automobile',catalog_kind:'business',business_category_ids:[],direct_business_category_ids:[]}];
 records={businesses:[{id:'shop',business_name:'Example Shop',global_category_id:'other'}],products:[],services:[],gallery_photos:[]};failing=null;
});
test('reports direct children, both product reference columns, business names, and gallery references',async()=>{
 categories.push({id:'child',name:'Child',parent_id:selected,catalog_kind:'product'});
 records.products.push({id:'p',name:'Bike',business_id:'shop',folder_category_id:selected,category_id:selected});
 records.services.push({id:'s',name:'Repair',business_id:'shop',category_id:selected});
 records.gallery_photos.push({id:'g',caption:'Photo',business_id:'shop',global_category_id:selected});
 const result=await categoryDeletionPreview(selected);
 assert.deepEqual(result.children.map(c=>c.name),['Child']);
 assert.equal(result.references.products.count,1);assert.equal(result.references.products.items[0].businessName,'Example Shop');
 assert.equal(result.references.services.items[0].name,'Repair');assert.equal(result.references.gallery.items[0].name,'Photo');
 assert.equal(result.owners[0].name,'Automobile');assert.equal(result.blocked,true);
});
test('shows shared business categories and blocks deletion',async()=>{
 categories[0].business_category_ids.push('business2');categories.push({id:'business2',name:'Restaurant'});
 const result=await categoryDeletionPreview(selected);
 assert.deepEqual(result.owners.map(owner=>owner.name),['Automobile','Restaurant']);assert.equal(result.blocked,true);
});
test('business category reports assigned businesses and catalog mappings',async()=>{
 categories[0].catalog_kind='business';categories.push({id:'catalog',name:'Gold'});
 records.businesses[0].global_category_id=selected;
 const result=await categoryDeletionPreview(selected);
 assert.equal(result.references.businesses.items[0].name,'Example Shop');assert.equal(result.mappings[0].name,'Gold');assert.equal(result.blocked,true);
});
test('limits displayed records but counts every dependency',async()=>{
 records.products=Array.from({length:65},(_,i)=>({id:String(i),name:`Product ${i}`,folder_category_id:selected,business_id:'shop'}));
 const result=await categoryDeletionPreview(selected);
 assert.equal(result.references.products.count,65);assert.equal(result.references.products.items.length,50);
 const next=await categoryDeletionPreview(selected,50);assert.equal(next.references.products.items.length,15);assert.equal(next.references.products.count,65);assert.equal(next.offset,50);
});
test('allows an unreferenced category, rejects missing categories and fails closed on query errors',async()=>{
 assert.equal((await categoryDeletionPreview(selected)).blocked,false);
 await assert.rejects(categoryDeletionPreview('missing'),error=>error.status===404);
 failing='products';await assert.rejects(categoryDeletionPreview(selected),error=>error.status===503);
});
