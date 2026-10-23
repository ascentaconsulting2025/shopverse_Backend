const { test, beforeEach } = require('node:test');
const assert = require('node:assert/strict');
const stub = (path, exports) => { const id = require.resolve(path); require.cache[id] = { id, filename: id, loaded: true, exports }; };
const jwt = id => `header.${Buffer.from(JSON.stringify({session_id:id})).toString('base64url')}.signature`;
const user = {id:'owner', email:'owner@example.com'};
let sessions, rotations, providerRevocations, refreshFailure, dbFailure;
stub('../dist/config/supabaseClient.js', {
  createAuthClient: () => ({auth:{refreshSession: async ({refresh_token}) => {
    rotations++;
    await new Promise(resolve=>setTimeout(resolve,15));
    if(refreshFailure) return {error:refreshFailure,data:{session:null}};
    return {data:{user,session:{access_token:jwt(refresh_token),refresh_token:refresh_token+'-rotated',expires_at:123}},error:null};
  }}}),
  supabaseAdmin: {
    auth: {getUser:async token=>({data:{user:token===jwt('active')?user:null},error:null}),admin:{signOut:async()=>{providerRevocations++;return {error:null}}}},
    from: () => {
      let id, owner, update;
      const q = {
        select(){return q}, eq(key,value){if(key==='id')id=value;if(key==='user_id')owner=value;return q},
        insert:async row=>{sessions.set(row.id,row);return {error:dbFailure}},
        update(value){update=value;return q},
        async maybeSingle(){const data=sessions.get(id);return {data: data && (!owner || data.user_id===owner) ? data:null,error:dbFailure}},
        then(resolve,reject){const row=sessions.get(id);if(row && (!owner || row.user_id===owner))Object.assign(row,update);return Promise.resolve({error:dbFailure}).then(resolve,reject)}
      }; return q;
    }
  }
});
const {assertSession,issueSession,readRefresh} = require('../dist/modules/auth/session.js');
const {refresh,logout} = require('../dist/modules/auth/auth.controller.js');
const {authGuard} = require('../dist/middlewares/authGuard.js');
const response = () => ({cookies:[],status(){return this},setHeader(){},cookie(...args){this.cookies.push(args)},clearCookie(...args){this.cleared=args},json(value){this.body=value;return value}});
const run=(handler,req,res=response())=>new Promise((resolve,reject)=>{const original=res.json;res.json=value=>{original.call(res,value);resolve(res)};handler(req,res,reject)});
beforeEach(()=>{sessions=new Map([['active',{id:'active',user_id:'owner',expires_at:new Date(Date.now()+86400000).toISOString(),revoked_at:null}]]);rotations=0;providerRevocations=0;refreshFailure=null;dbFailure=null;});
test('refresh cookie is HttpOnly, persistent, scoped and secrets are omitted from JSON',async()=>{
 const res=response();const result=await issueSession(res,{access_token:jwt('active'),refresh_token:'secret',expires_at:123},user);
 assert.equal(result.session.refresh_token,undefined);assert.equal(res.cookies[0][2].httpOnly,true);assert.equal(res.cookies[0][2].path,'/api/v1/auth');assert.ok(res.cookies[0][2].expires > new Date());
 const old=process.env.NODE_ENV;process.env.NODE_ENV='production';const prod=response();await issueSession(prod,{access_token:jwt('active'),refresh_token:'secret'},user);assert.equal(prod.cookies[0][2].secure,true);process.env.NODE_ENV=old;
});
test('concurrent refresh operations rotate once and preserve the absolute lifetime',async()=>{
 const results=await Promise.all(Array.from({length:8},()=>run(refresh,{headers:{cookie:'shopverse_refresh=active'}})));
 assert.equal(rotations,1);assert.ok(results.every(r=>r.body.data.session.access_token===jwt('active')));assert.equal(results[0].cookies[0][2].expires.toISOString(),sessions.get('active').expires_at);
});
test('missing, expired, revoked and mismatched sessions cannot authorize',async()=>{
 for(const mode of ['missing','expired','revoked','other-owner']){
  if(mode==='missing')sessions.delete('active');else sessions.set('active',{user_id:mode==='other-owner'?'other':'owner',expires_at:new Date(Date.now()+(mode==='expired'?-1000:1000)).toISOString(),revoked_at:mode==='revoked'?'now':null});
  await assert.rejects(assertSession(jwt('active'),'owner'),e=>e.status===401);
 }
});
test('logout revokes registry and provider session and old access JWT fails immediately',async()=>{
 const res=await run(logout,{headers:{authorization:'Bearer '+jwt('active')}});
 assert.ok(res.cleared);assert.equal(providerRevocations,1);await assert.rejects(assertSession(jwt('active'),'owner'),e=>e.status===401);
});
test('provider/network outages are recoverable and do not clear the refresh cookie',async()=>{
 refreshFailure={status:503};const res=response();await assert.rejects(run(refresh,{headers:{cookie:'shopverse_refresh=unavailable'}},res),e=>e.status===503);assert.equal(res.cleared,undefined);
});
test('invalid refresh cookie clears saved credentials',async()=>{
 refreshFailure={status:400};const res=response();await assert.rejects(run(refresh,{headers:{cookie:'shopverse_refresh=invalid'}},res),e=>e.status===401);assert.ok(res.cleared);
});
test('database validation errors fail closed as 503',async()=>{dbFailure={message:'offline'};await assert.rejects(assertSession(jwt('active'),'owner'),e=>e.status===503)});
test('cookie parsing and malformed bearer inputs fail safely',async()=>{
 assert.equal(readRefresh({headers:{cookie:'shopverse_refresh=%XX'}}),'');
 for(const authorization of ['token','Bearer','Bearer a b']){const res=response();let status;res.status=value=>{status=value;return res};await authGuard({headers:{authorization}},res,()=>{throw Error('must not authorize')});assert.equal(status,401)}
});
