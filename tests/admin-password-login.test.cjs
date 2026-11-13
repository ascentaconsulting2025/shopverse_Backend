const { test } = require('node:test');
const assert = require('node:assert/strict');
const stub = (path, exports) => { const id = require.resolve(path); require.cache[id] = { id, filename: id, loaded: true, exports }; };
let user, passwordError, otpCalls, issued;
stub('../dist/config/supabaseClient.js', {
  createAuthClient: () => ({ auth: {
    signInWithPassword: async () => ({ data: { user, session: passwordError ? null : { access_token: 'token' } }, error: passwordError }),
    signInWithOtp: async () => { otpCalls++; return { error: null }; },
  } }),
  supabaseAdmin: { from: () => ({ upsert: async () => ({ error: null }) }) },
});
stub('../dist/modules/auth/session.js', { issueSession: async (_res, _session, account) => { issued++; return { role: 'admin', user: account, session: { access_token: 'token' } }; } });
const { login } = require('../dist/modules/auth/auth.controller.js');
const run = (email, adminLogin = true) => new Promise((resolve, reject) => login({ body: { email, password: 'password123', adminLogin } }, { json: resolve }, reject));
test('only the configured admin@gmail.com account bypasses verification after password authentication', async () => {
  process.env.ADMIN_EMAILS = 'admin@gmail.com,other@example.com';
  otpCalls = 0; issued = 0; passwordError = null;
  user = { id: 'admin', email: 'admin@gmail.com', user_metadata: {} };
  assert.equal((await run(user.email)).data.role, 'admin');
  assert.equal(issued, 1); assert.equal(otpCalls, 0);
  user = { id: 'other', email: 'other@example.com' };
  assert.match((await run(user.email)).data.message, /verification code/);
  assert.equal(otpCalls, 1); assert.equal(issued, 1);
  user = { id: 'admin', email: 'admin@gmail.com' }; passwordError = { message: 'invalid' };
  await assert.rejects(run(user.email), error => error.status === 401);
  assert.equal(issued, 1);
  passwordError = null; process.env.ADMIN_EMAILS = 'other@example.com';
  assert.match((await run(user.email)).data.message, /verification code/);
  assert.equal(issued, 1);
});
