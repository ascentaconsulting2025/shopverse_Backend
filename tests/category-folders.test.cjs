const {test}=require('node:test');
const assert=require('node:assert/strict');
let tables,failWrite;
function query(table){
 const filters=[];let mutation;
 const q={select(){return q},eq(k,v){filters.push([k,v]);return q},order(){return q},update(v){mutation=v;return q},insert(v){mutation=v;return q},async single(){return execute(true)},async maybeSingle(){return execute(true)},then(a,b){return Promise.resolve(execute(false)).then(a,b)}};
 function execute(single){let rows=(tables[table]||[]).filter(row=>filters.every(([k,v])=>row[k]===v));if(mutation){if(failWrite)return {data:null,error:{message:'database unavailable'}};rows.forEach(row=>Object.assign(row,mutation));}return {data:structuredClone(single?rows[0]||null:rows),error:null};}return q;
}
function stub(path,exports){const filename=require.resolve(path);require.cache[filename]={id:filename,filename,loaded:true,exports};}
stub('../dist/config/supabaseClient.js',{supabaseAdmin:{from:query}});
stub('../dist/utils/cloudinaryAsset.js',{cloudinaryPublicIdFromUrl:()=>null,deleteCloudinaryImage:async()=>{}});
const {validateCategory,publicItems,requireCategoryOwner}=require('../dist/modules/categories/categories.service.js');
const {productsService}=require('../dist/modules/products/products.service.js');
const {servicesService}=require('../dist/modules/services/services.service.js');
function reset(){failWrite=false;tables={businesses:[{id:'b',owner_id:'owner',is_published:true}],business_categories:[{id:'c',business_id:'b',type:'product',is_published:true},{id:'s',business_id:'b',type:'service',is_published:true}],products:[{id:'p',business_id:'b',folder_category_id:null,name:'Original',price:120}],services:[{id:'s',business_id:'b',folder_category_id:null,name:'Original service'}]};}
test('category isolation, item preservation and publication',async t=>{
 await t.test('rejects foreign owners and missing businesses',async()=>{reset();await assert.rejects(requireCategoryOwner('b',{user:{id:'other'}}),e=>e.status===403);await assert.rejects(requireCategoryOwner('missing',{user:{id:'owner'}}),e=>e.status===404);await requireCategoryOwner('b',{user:{id:'owner'}});});
 await t.test('rejects cross-business and cross-type assignments before writes',async()=>{reset();await assert.rejects(validateCategory('other','product','c'));await assert.rejects(productsService.update('p',{categoryId:'s'}));await assert.rejects(servicesService.update('s',{categoryId:'c'}));assert.equal(tables.products[0].folder_category_id,null);assert.equal(tables.services[0].folder_category_id,null);});
 await t.test('moves and unassigns existing records without replacing their fields',async()=>{reset();await productsService.update('p',{categoryId:'c'});assert.equal(tables.products.length,1);assert.equal(tables.products[0].price,120);assert.equal(tables.products[0].folder_category_id,'c');await productsService.update('p',{categoryId:null});assert.equal(tables.products[0].folder_category_id,null);});
 await t.test('failed write retains old assignment',async()=>{reset();failWrite=true;await assert.rejects(productsService.update('p',{categoryId:'c'}));assert.equal(tables.products[0].folder_category_id,null);});
 await t.test('public output excludes drafts and hidden folders while preserving availability',async()=>{reset();const items=[{id:'legacy'},{id:'visible',folder_category_id:'c'},{id:'draft',is_published:false},{id:'unavailable',is_available:false},{id:'wrong',folder_category_id:'s'}];assert.deepEqual((await publicItems('b','product',items)).map(x=>x.id),['legacy','visible','unavailable']);tables.business_categories[0].is_published=false;assert.deepEqual((await publicItems('b','product',items)).map(x=>x.id),['legacy','unavailable']);tables.businesses[0].is_published=false;assert.deepEqual(await publicItems('b','product',items),[]);});
});
