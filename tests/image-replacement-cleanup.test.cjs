const {test,beforeEach}=require('node:test');
const assert=require('node:assert/strict');
const stub=(path,exports)=>{const id=require.resolve(path);require.cache[id]={id,filename:id,loaded:true,exports}};
let result;
stub('../dist/config/cloudinary.js',{__esModule:true,default:{uploader:{destroy:async()=>result}}});
stub('../dist/config/supabaseClient.js',{supabaseAdmin:{}});
const {deleteCloudinaryImage,cloudinaryPublicIdFromUrl}=require('../dist/utils/cloudinaryAsset.js');
const {runCloudinaryCleanup}=require('../dist/utils/cloudinaryCleanup.js');
beforeEach(()=>{result={result:'ok'}});
function database(jobs,error=null,ackError=null){
 const writes=[];
 return {writes,rpc:async()=>({data:jobs,error}),from:()=>({update:change=>({eq:async()=>{writes.push(change);return {error:change.state?ackError:null}}})})};
}
test('legacy URLs never become deletion identifiers',()=>{
 for(const url of ['https://res.cloudinary.com/demo/image/upload/v123/a.b.jpg','https://res.cloudinary.com/demo/image/upload/c_fill/v123/a.png',null]) assert.equal(cloudinaryPublicIdFromUrl(url),null);
});
test('only confirmed deletion and already missing assets are accepted',async()=>{
 for(const value of ['ok','not found']){result={result:value};assert.equal(await deleteCloudinaryImage('nested/a.b','id'),value)}
 result={result:'error'};await assert.rejects(deleteCloudinaryImage('asset','id'));
});
test('database claim failure never calls Cloudinary',async()=>{
 let calls=0;await assert.rejects(runCloudinaryCleanup(database([],{message:'offline'}),async()=>calls++));assert.equal(calls,0);
});
test('shared or unchanged assets excluded by claim are never destroyed',async()=>{
 let calls=0;await runCloudinaryCleanup(database([]),async()=>calls++);assert.equal(calls,0);
});
test('successful cleanup acknowledges the durable job',async()=>{
 const db=database([{public_id:'old'}]);const ids=[];
 await runCloudinaryCleanup(db,async id=>ids.push(id));assert.deepEqual(ids,['old']);assert.equal(db.writes[0].state,'deleted');
});
test('provider timeout preserves job for idempotent retry',async()=>{
 const db=database([{public_id:'old'}]);await runCloudinaryCleanup(db,async()=>{throw Error('timeout')});
 assert.equal(db.writes[0].state,undefined);assert.match(db.writes[0].last_error,/retry/);
 await runCloudinaryCleanup(db,async()=> 'not found');assert.equal(db.writes.at(-1).state,'deleted');
});
test('database acknowledgement failure remains recoverable',async()=>{
 const db=database([{public_id:'old'}],null,{message:'offline'});await runCloudinaryCleanup(db,async()=> 'ok');
 assert.match(db.writes.at(-1).last_error,/retry/);
});
