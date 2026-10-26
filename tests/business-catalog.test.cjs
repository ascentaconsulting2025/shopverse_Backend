const {test}=require('node:test');
const assert=require('node:assert/strict');
const {resolveCatalog,publicCategoryProjection}=require('../dist/modules/categories/catalog.js');
const rows=[
 {id:'gold',catalog_kind:'product',available:true},
 {id:'earrings',parent_id:'gold',catalog_kind:'product',available:true},
 {id:'rings',parent_id:'gold',catalog_kind:'product',available:true},
 {id:'silver',catalog_kind:'product',available:true},
 {id:'repair',catalog_kind:'service',available:true},
 {id:'old',catalog_kind:'legacy',available:true},
];
test('parent mappings inherit active descendants without duplicates',()=>{
 const result=resolveCatalog(rows,['gold','earrings'],'product',true);
 assert.deepEqual(result.map(c=>c.id),['gold','earrings','rings']);
 assert.equal(result.find(c=>c.id==='gold').selectable,false);
 assert.equal(result.find(c=>c.id==='rings').selectable,true);
});
test('child mapping includes ancestors only for navigation and never siblings',()=>{
 const result=resolveCatalog(rows,['earrings'],'product',true);
 assert.deepEqual(result.map(c=>c.id),['gold','earrings']);
 assert.equal(result[0].allowed,false);assert.equal(result[0].selectable,false);
});
test('listing type, inactive business, missing mappings and legacy rows never grant access',()=>{
 assert.deepEqual(resolveCatalog(rows,['repair'],'product',true),[]);
 assert.deepEqual(resolveCatalog(rows,['gold'],'product',false),[]);
 assert.deepEqual(resolveCatalog(rows,[],'service',true),[]);
 assert.deepEqual(resolveCatalog(rows,['old'],'product',true),[]);
 assert.deepEqual(resolveCatalog(rows,['repair'],'service',true).map(c=>c.id),['repair']);
});
test('disabled descendants do not turn structural parents into selectable leaves',()=>{
 const result=resolveCatalog(rows.map(c=>c.parent_id==='gold'?{...c,available:false}:c),['gold'],'product',true);
 assert.equal(result.length,1);assert.equal(result[0].selectable,false);
});
test('new descendants inherit access and disabled ancestors block it',()=>{
 const expanded=[...rows,{id:'studs',parent_id:'earrings',catalog_kind:'product',available:true}];
 assert.equal(resolveCatalog(expanded,['gold'],'product',true).find(c=>c.id==='studs').selectable,true);
 assert.equal(resolveCatalog(expanded,['gold'],'product',true).find(c=>c.id==='earrings').selectable,false);
 assert.deepEqual(resolveCatalog(expanded.map(c=>c.id==='gold'?{...c,available:false}:c),['gold'],'product',true),[]);
});
test('cycles and missing ancestors cannot grant access',()=>{
 assert.deepEqual(resolveCatalog([{id:'a',parent_id:'b',catalog_kind:'product',available:true},{id:'b',parent_id:'a',catalog_kind:'product',available:true}],['a'],'product',true),[]);
 assert.deepEqual(resolveCatalog([{id:'a',parent_id:'missing',catalog_kind:'product',available:true}],['a'],'product',true),[]);
});

test('public identity retains legacy and unmapped published item categories with their ancestors',()=>{
 const catalog=[{id:'root',name:'Vehicles',available:true,catalog_kind:'legacy'},
  {id:'bike',name:'Bike',parent_id:'root',available:true,catalog_kind:'legacy'},
  {id:'repair',name:'Repair',available:true,catalog_kind:'service'},
  {id:'unrelated',name:'Private unused category',available:true},
  {id:'disabled',name:'Hidden',available:false}];
 const products=[{folder_category_id:'bike',is_published:true},{folder_category_id:'disabled',is_published:true}];
 const result=publicCategoryProjection(catalog,products,[{folder_category_id:'repair',is_published:true}]);
 assert.deepEqual(result.map(c=>[c.id,c.type]),[['root','product'],['bike','product'],['repair','service']]);
 assert.deepEqual(publicCategoryProjection(catalog,[{folder_category_id:'bike',is_published:false}],[]),[]);
 assert.deepEqual(resolveCatalog(catalog,[],'product',false),[],'New listing permissions remain restricted');
});
