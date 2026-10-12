// Run after npm run build: node --test tests/theme-publishing.test.cjs
const { test } = require('node:test');
const assert = require('node:assert/strict');
let rows;
let failWrite = false;
const makeQuery = table => {
  const filters = [];
  let update;
  const execute = single => {
    if (table !== 'businesses') return { data: single ? null : [], error: null };
    const row = rows.find(row => filters.every(([key, value]) => row[key] === value));
    if (!row) return { data: null, error: { message: 'not found' } };
    if (update && failWrite) return { data: null, error: { message: 'write failed' } };
    if (update) Object.assign(row, structuredClone(update));
    return { data: structuredClone(row), error: null };
  };
  const query = {
    select() { return query; }, eq(key, value) { filters.push([key, value]); return query; },
    is() { return query; }, order() { return query; },
    update(value) { update = value; return query; },
    single: async () => execute(true), maybeSingle: async () => execute(true),
    then(resolve, reject) { return Promise.resolve(execute(false)).then(resolve, reject); },
  };
  return query;
};
const stub = (path, exports) => {
  const filename = require.resolve(path);
  require.cache[filename] = { id: filename, filename, loaded: true, exports };
};
// No credentials, network requests, or real business writes in this suite.
stub('../dist/config/supabaseClient.js', { supabaseAdmin: { from: makeQuery } });
stub('../dist/utils/cloudinaryAsset.js', { cloudinaryPublicIdFromUrl: () => null, deleteCloudinaryImage: async () => {} });
const { updateBusiness, getBusinessBySlug } = require('../dist/modules/business/business.controller.js');
const { businessPayloadSchema } = require('../dist/modules/business/business.schema.js');
const config = {
  version: 1, theme: 'dark-elegant', primary: '#D7A94B', secondary: '#F2C66D', accent: '#F8E5B2',
  background: '#0B0B10', text: '#F7F3EA', surface: '#17151B', border: '#3A3030', glass: 'light',
  cardStyle: 'solid', radius: 'rounded', shadow: 'strong', header: 'floating', font: 'Inter', section: 'outlined',
};
const run = (handler, req) => new Promise((resolve, reject) => handler(req, { json: resolve }, reject));
const patch = (body, user = 'owner-a', id = 'a') => run(updateBusiness, {
  params: { id }, user: { id: user }, body: businessPayloadSchema.parse(body),
});
const reset = () => {
  failWrite = false;
  rows = ['a', 'b'].map(id => ({ id, slug: id, owner_id: `owner-${id}`, plan_id: 'premium',
    is_published: true, status: 'active', details: { about: 'Original business content', products: [] } }));
};
test('publish round trip, isolated drafts, authorization and failed saves', async t => {
  await t.test('the entire configuration survives publishing and the public API', async () => {
    reset();
    await patch({ themeConfig: config, themeDraft: null });
    const published = await run(getBusinessBySlug, { params: { slug: 'a' } });
    assert.deepEqual(published.data.themeConfig, config);
    assert.equal(published.data.about.en, 'Original business content');
    assert.equal(published.data.themeDraft, undefined);
    assert.equal(rows[1].details.themeConfig, undefined);
  });
  await t.test('saving a different draft does not change the published theme', async () => {
    reset();
    await patch({ themeConfig: config });
    await patch({ themeDraft: { ...config, primary: '#123456' } });
    const published = await run(getBusinessBySlug, { params: { slug: 'a' } });
    assert.deepEqual(published.data.themeConfig, config);
    assert.equal(published.data.themeDraft, undefined);
    assert.equal(rows[0].details.themeDraft.primary, '#123456');
  });
  await t.test('another business owner cannot publish', async () => {
    reset();
    await assert.rejects(patch({ themeConfig: config }, 'owner-b'), error => error.status === 403);
    assert.equal(rows[0].details.themeConfig, undefined);
  });
  await t.test('a payload cannot self-upgrade the plan to unlock publishing', async () => {
    reset(); rows[0].plan_id = 'basic';
    await assert.rejects(patch({ planId: 'premium', themeConfig: config }), error => error.status === 403);
  });
  await t.test('database failure rejects the publish', async () => {
    reset(); failWrite = true;
    await assert.rejects(patch({ themeConfig: config }), error => error.status === 400);
    assert.equal(rows[0].details.themeConfig, undefined);
  });
  await t.test('invalid colours, arbitrary CSS and unknown versions are rejected', () => {
    for (const patch of [{ primary: 'url(https://example.com)' }, { glass: 'extreme' }, { version: 2 }, { css: 'body{display:none}' }]) {
      assert.equal(businessPayloadSchema.safeParse({ themeConfig: { ...config, ...patch } }).success, false);
    }
  });
});
