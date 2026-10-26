const {test}=require('node:test');
const assert=require('node:assert/strict');
let tables,failWrite;
function query(table){
 const filters=[];let mutation,start=0,end=Infinity;
 const q={select(){return q},eq(k,v){filters.push([k,v]);return q},order(){return q},range(a,b){start=a;end=b;return q},update(v){mutation=v;return q},insert(v){mutation=v;return q},async single(){return execute(true)},async maybeSingle(){return execute(true)},then(a,b){return Promise.resolve(execute(false)).then(a,b)}};
 function execute(single){let rows=(tables[table]||[]).filter(row=>filters.every(([k,v])=>row[k]===v)).slice(start,end+1);if(mutation){if(failWrite)return {data:null,error:{message:'database unavailable'}};rows.forEach(row=>Object.assign(row,mutation));}return {data:structuredClone(single?rows[0]||null:rows),error:null};}return q;
}
function stub(path,exports){const filename=require.resolve(path);require.cache[filename]={id:filename,filename,loaded:true,exports};}
stub('../dist/config/supabaseClient.js',{supabaseAdmin:{from:query,rpc:async(name,args)=>{
 if(name==='catalog_category_allowed'){
  const category=tables.business_categories.find(c=>c.id===args.p_category);
  return {data:!!category && category.status==='enabled' && category.is_published && category.catalog_kind===args.p_type && args.p_business_category==='bc',error:null};
 }
 return {data:!!tables.business_categories.find(c=>c.id===args.p_id && c.status==='enabled' && c.is_published),error:null};
}}});
stub('../dist/utils/cloudinaryAsset.js',{cloudinaryPublicIdFromUrl:()=>null,deleteCloudinaryImage:async()=>{}});
const {validateCategory,publicItems,requireCategoryOwner,loadGlobalCategories}=require('../dist/modules/categories/categories.service.js');
const {productsService}=require('../dist/modules/products/products.service.js');
const {servicesService}=require('../dist/modules/services/services.service.js');
function reset(){failWrite=false;tables={businesses:[{id:'b',owner_id:'owner',is_published:true,global_category_id:'bc'}],business_categories:[{id:'c',catalog_kind:'product',business_id:'original-business',type:'product',name:'Global',status:'enabled',is_published:true},{id:'s',catalog_kind:'service',name:'Services',status:'enabled',is_published:true}],products:[{id:'p',business_id:'b',folder_category_id:null,name:'Original',price:120}],services:[{id:'s',business_id:'b',folder_category_id:null,name:'Original service'}]};}
test('global category assignments, item ownership and publication',async t=>{
 await t.test('rejects foreign owners and missing businesses',async()=>{reset();await assert.rejects(requireCategoryOwner('b',{user:{id:'other'}}),e=>e.status===403);await assert.rejects(requireCategoryOwner('missing',{user:{id:'owner'}}),e=>e.status===404);await requireCategoryOwner('b',{user:{id:'owner'}});});
 await t.test('product and service assignments respect their catalog type',async()=>{reset();await productsService.update('p',{categoryId:'c'});await servicesService.update('s',{categoryId:'s'});await assert.rejects(productsService.update('p',{categoryId:'s'}),e=>e.status===400);assert.equal(tables.products[0].folder_category_id,'c');assert.equal(tables.services[0].folder_category_id,'s');assert.equal(tables.products[0].category_id,'c');});
 await t.test('invalid and disabled selections are rejected before writes',async()=>{reset();await assert.rejects(productsService.update('p',{categoryId:'missing'}),e=>e.status===400);tables.business_categories[0].status='disabled';await assert.rejects(servicesService.update('s',{categoryId:'c'}),e=>e.status===400);assert.equal(tables.products[0].folder_category_id,null);});
 await t.test('moves preserve item fields and unassigning a required category is rejected',async()=>{reset();await productsService.update('p',{categoryId:'c'});assert.equal(tables.products.length,1);assert.equal(tables.products[0].price,120);assert.equal(tables.products[0].folder_category_id,'c');await assert.rejects(productsService.update('p',{categoryId:null}),e=>e.status===400);assert.equal(tables.products[0].folder_category_id,'c');assert.equal(tables.products[0].category_id,'c');});
 await t.test('disabled assignments remain readable but require recategorization on save',async()=>{reset();await productsService.update('p',{categoryId:'c'});tables.business_categories[0].name='Renamed';tables.business_categories[0].status='disabled';tables.business_categories[0].is_published=false;await assert.rejects(productsService.update('p',{categoryId:'c',price:140}),e=>e.status===400);const saved=tables.products[0];assert.equal(saved.folder_category_id,'c');assert.equal(saved.price,120);});
 await t.test('failed writes retain the old assignment',async()=>{reset();failWrite=true;await assert.rejects(productsService.update('p',{categoryId:'c'}));assert.equal(tables.products[0].folder_category_id,null);});
 await t.test('public output excludes drafts and disabled ancestors',async()=>{reset();tables.business_categories[1].parent_id='c';const items=[{id:'legacy'},{id:'visible',folder_category_id:'s'},{id:'draft',is_published:false},{id:'unavailable',is_available:false},{id:'missing',folder_category_id:'missing'}];assert.deepEqual((await publicItems('b','product',items)).map(x=>x.id),['legacy','visible','unavailable']);tables.business_categories[0].is_published=false;assert.deepEqual((await publicItems('b','product',items)).map(x=>x.id),['legacy','unavailable']);tables.businesses[0].is_published=false;assert.deepEqual(await publicItems('b','product',items),[]);});
 await t.test('large hierarchies are paginated without truncating at 1000 categories',async()=>{reset();tables.business_categories=Array.from({length:1005},(_,i)=>({id:String(i),name:'Category '+i,status:'enabled',is_published:true}));assert.equal((await loadGlobalCategories()).length,1005);});
});
