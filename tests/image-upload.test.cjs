const {test,beforeEach}=require('node:test');const assert=require('node:assert/strict');
const stub=(path,exports)=>{const id=require.resolve(path);require.cache[id]={id,filename:id,loaded:true,exports}};
let queued,registerError,uploadConfig,cloudOptions,cloudResult,cloudError,destroyed,received;
stub('../dist/middlewares/authGuard.js',{authGuard:()=>{}});stub('../dist/middlewares/rateLimiter.js',{uploadsRateLimiter:()=>{}});
stub('../dist/config/supabaseClient.js',{supabaseAdmin:{from:()=>({insert:async()=>({error:registerError}),update:value=>({eq:async()=>{queued.push(value);return {error:null}}})})}});
const cloud={uploader:{upload_stream:(options,callback)=>{cloudOptions=options;return {end:buffer=>{received=buffer;callback(cloudError,{...cloudResult,public_id:options.folder+'/'+options.public_id})}}},destroy:async id=>{destroyed.push(id);return {result:'ok'}}}};
stub('../dist/config/cloudinary.js',{__esModule:true,default:cloud});
const multer=options=>{uploadConfig=options;return {single:()=>()=>{}}};multer.memoryStorage=()=>({});stub('multer',multer);
const router=require('../dist/modules/uploads/uploads.routes.js').default;
const handler=router.stack.find(layer=>layer.route).route.stack.at(-1).handle;
const png=(width=1200,height=900)=>{const b=Buffer.alloc(24);Buffer.from([137,80,78,71,13,10,26,10]).copy(b);b.write('IHDR',12);b.writeUInt32BE(width,16);b.writeUInt32BE(height,20);return b};
const run=(imageType='product',file={buffer:png()})=>new Promise((resolve,reject)=>handler({body:{imageType},file,user:{id:'owner'}},{status(value){this.code=value;return this},json(value){resolve({status:this.code||200,body:value})}},reject));
beforeEach(()=>{queued=[];registerError=null;cloudOptions=null;cloudError=null;destroyed=[];cloudResult={public_id:'shopverse/uploads/image',secure_url:'https://example.test/image.png',format:'png',width:1200,height:900,resource_type:'image',bytes:100};});
test('all presets use trusted incoming dimensions, restricted formats and original cropped bytes',async()=>{
 const specs=require('../dist/config/imageSpecs.json');const frontend=require('../../shopverse_frontend/frontend/src/utils/imageSpecs.json');assert.deepEqual(specs,frontend);
 for(const [type,spec]of Object.entries(specs)){cloudResult={...cloudResult,...spec};const result=await run(type,{buffer:png(spec.width,spec.height)});assert.equal(result.status,200);assert.equal(cloudOptions.resource_type,'image');assert.deepEqual(cloudOptions.allowed_formats,['jpg','jpeg','png','webp']);assert.equal(cloudOptions.transformation,undefined);assert.deepEqual(received,png(spec.width,spec.height));}
});
test('invalid/missing types and missing images fail before reaching Cloudinary',async()=>{for(const type of ['invalid','__proto__',undefined]){const result=await run(type===undefined?null:type);assert.equal(result.status,400)}assert.equal((await run('product',null)).status,400);assert.equal(cloudOptions,null)});
test('incorrect processed dimensions trigger cleanup and never return a stored reference',async()=>{cloudResult.width=100;const result=await run();assert.equal(result.status,422);assert.equal(result.body.data,undefined);assert.equal(queued.length,2);assert.deepEqual(destroyed,[])});
test('Cloudinary failure propagates without returning a successful reference',async()=>{cloudError=Error('Cloudinary unavailable');await assert.rejects(run(),/Cloudinary unavailable/)});
test('Multer limits input size and rejects executable/vector MIME types',()=>{assert.equal(uploadConfig.limits.fileSize,10*1024*1024);for(const mimetype of ['image/svg+xml','text/html','application/octet-stream']){uploadConfig.fileFilter({}, {mimetype},error=>assert.equal(error.status,400))}for(const mimetype of ['image/jpeg','image/png','image/webp'])uploadConfig.fileFilter({}, {mimetype},(error,accepted)=>{assert.equal(error,null);assert.equal(accepted,true)})});

test('registration failure prevents upload',async()=>{registerError={message:'offline'};await assert.rejects(run(),/Unable to register/);assert.deepEqual(destroyed,[]);assert.equal(cloudOptions,null)});

test('wrong dimensions and invalid bytes are rejected before Cloudinary',async()=>{for(const buffer of [png(900,900),Buffer.from('invalid')]){const result=await run('product',{buffer});assert.equal(result.status,422);assert.equal(cloudOptions,null)}});
