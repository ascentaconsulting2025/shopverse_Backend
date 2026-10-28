const {test}=require('node:test');
const assert=require('node:assert/strict');
const {categoryBusinesses,validateWrite}=require('../dist/modules/categories/integrity');
const {resolveCatalog}=require('../dist/modules/categories/catalog');
const category=(id,kind,parent_id=null)=>({id,name:id,catalog_kind:kind,parent_id,available:true});
const source=[category('Automobile','business'),category('Restaurant','business'),category('Jewellery','business'),category('Two-Wheelers','product'),category('Motorcycles','product','Two-Wheelers'),category('Scooters','product','Two-Wheelers'),category('Food','product'),category('Accessories','product')];
const mappings=[{business_category_id:'Automobile',catalog_category_id:'Two-Wheelers'},{business_category_id:'Restaurant',catalog_category_id:'Food'},{business_category_id:'Automobile',catalog_category_id:'Accessories'}];
const rows=categoryBusinesses(source,mappings);
test('mapping-derived ownership isolates both Automobile descendants from Restaurant',()=>{
 for(const id of ['Motorcycles','Scooters'])assert.deepEqual(rows.find(c=>c.id===id).business_category_ids,['Automobile']);
 assert.deepEqual(resolveCatalog(rows,['Food'],'product',true).map(c=>c.id),['Food']);
});
test('cross-business, missing, incompatible and circular parents are rejected',()=>{
 assert.throws(()=>validateWrite(rows,{name:'New',catalog_kind:'product',parent_id:'Two-Wheelers'},undefined,'Restaurant'),/Parent is not assigned/);
 assert.throws(()=>validateWrite(rows,{name:'New',catalog_kind:'service',parent_id:'Two-Wheelers'}),/same category type/);
 assert.throws(()=>validateWrite(rows,{parent_id:'Motorcycles'},'Two-Wheelers'),/beneath itself/);
 assert.throws(()=>validateWrite(rows,{name:'New',parent_id:'missing'}),/same category type/);
});
test('shared parents cannot silently propagate contextual or context-free creation',()=>{
 const shared=categoryBusinesses(source,[...mappings,{business_category_id:'Restaurant',catalog_category_id:'Two-Wheelers'}]);
 for(const business of [undefined,'Automobile'])assert.throws(()=>validateWrite(shared,{name:'New',catalog_kind:'product',parent_id:'Two-Wheelers'},undefined,business),/shared/);
});
test('normalized duplicates are blocked, similar spellings require override, different businesses can reuse names',()=>{
 assert.throws(()=>validateWrite(rows,{name:'  MOTORCYCLES ',catalog_kind:'product',parent_id:'Two-Wheelers'},undefined,'Automobile'),/Already Exists/);
 assert.throws(()=>validateWrite(rows,{name:'Motor cycle',catalog_kind:'product',parent_id:'Two-Wheelers'},undefined,'Automobile'),/Similar category/);
 assert.doesNotThrow(()=>validateWrite(rows,{name:'Motor cycle',catalog_kind:'product',parent_id:'Two-Wheelers'},undefined,'Automobile',true));
 assert.doesNotThrow(()=>validateWrite(rows,{name:'Accessories',catalog_kind:'product'},undefined,'Jewellery'));
 assert.doesNotThrow(()=>validateWrite(rows,{name:'Motorcycles'},'Motorcycles','Automobile'));
});
test('moves cannot gain unrelated business assignments',()=>{
 assert.throws(()=>validateWrite(rows,{parent_id:'Food'},'Motorcycles'),/business assignments/);
});
test('valid legacy children retain their existing business-parent relationship',()=>{
 const legacy=categoryBusinesses([category('Furniture','business'),category('Sofa','legacy','Furniture')],[]);
 assert.deepEqual(legacy[1].business_category_ids,['Furniture']);
 assert.doesNotThrow(()=>validateWrite(legacy,{name:'Sofa',parent_id:'Furniture'},'Sofa'));
});
