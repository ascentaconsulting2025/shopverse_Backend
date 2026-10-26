const { test } = require("node:test");
const assert = require("node:assert/strict");
const path = require("node:path");
const build = process.env.EXPLORE_BUILD || path.resolve(__dirname, "../dist");
let calls = [],
  response = { data: [], count: 0, error: null };
const query = new Proxy(
  {},
  {
    get: (_t, key) =>
      key === "then"
        ? (resolve, reject) => Promise.resolve(response).then(resolve, reject)
        : (...args) => {
            calls.push([key, ...args]);
            return query;
          },
  },
);
const config = path.join(build, "config/supabaseClient.js");
require.cache[config] = {
  id: config,
  filename: config,
  loaded: true,
  exports: {
    supabaseAdmin: {
      from: (name) => {
        calls.push(["from", name]);
        return query;
      },
      rpc: (name) => {
        calls.push(["rpc", name]);
        return Promise.resolve(response);
      },
    },
  },
};
const router = require(
  path.join(build, "modules/explore/explore.routes.js"),
).default;
function run(route, q = {}, params = {}) {
  calls = [];
  const handler = router.stack.find((s) => s.route?.path === route).route
    .stack[0].handle;
  return new Promise((resolve, reject) =>
    handler({ query: q, params }, { json: resolve }, reject),
  );
}
test("Explore validates and composes paginated scoped queries", async () => {
  response = { data: [{ id: "product" }], count: 30, error: null };
  const result = await run("/products", {
    category: "Jewellery",
    subcategory: "Gold Jewellery",
    page: "2",
    sort: "price-asc",
    min: "100",
    max: "2000",
    available: "true",
    metal: "Gold",
    purity: "22 Karat (916)",
    search: "50%_off",
  });
  assert.equal(result.data.total, 30);
  assert.deepEqual(
    calls.find((c) => c[0] === "range"),
    ["range", 24, 47],
  );
  for (const pair of [
    ["category", "Jewellery"],
    ["subcategory", "Gold Jewellery"],
    ["available", true],
    ["specifications->>Metal", "Gold"],
    ["specifications->>Purity", "22 Karat (916)"],
  ])
    assert.ok(
      calls.some((c) => c[0] === "eq" && c[1] === pair[0] && c[2] === pair[1]),
    );
  assert.deepEqual(
    calls.find((c) => c[0] === "ilike"),
    ["ilike", "name", "%50\\%\\_off%"],
  );
  assert.ok(
    calls.some((c) => c[0] === "order" && c[1] === "price" && c[2].ascending),
  );
  for (const invalid of [
    { page: "0" },
    { page: "1.5" },
    { min: "500", max: "1" },
    { sort: "invalid" },
    { seller: "not-an-id" },
    { ids: "invalid" },
  ])
    await assert.rejects(run("/products", invalid));
  response = { data: null, error: null };
  await assert.rejects(
    run("/products/:id", {}, { id: "20000000-0000-4000-8000-000000000001" }),
    (e) => e.status === 404,
  );
  response = { data: null, error: { message: "internal database detail" } };
  await assert.rejects(
    run("/products"),
    (e) => e.status === 503 && !e.message.includes("internal"),
  );
  await assert.rejects(run("/categories"), (e) => e.status === 503);
  response = { data: [], error: null };
  const facets = await run("/categories");
  assert.deepEqual(facets.data, []);
  assert.deepEqual(calls, [["rpc", "explore_facets"]]);
  await run("/categories", { kind: "service" });
  assert.deepEqual(calls, [["rpc", "explore_service_facets"]]);
  await assert.rejects(run("/categories", { kind: "invalid" }));
  await run("/services", {
    page: "2",
    min: "200",
    available: "true",
    metal: "Gold",
  });
  assert.ok(calls.some((c) => c[0] === "from" && c[1] === "explore_services"));
  assert.deepEqual(
    calls.find((c) => c[0] === "range"),
    ["range", 24, 47],
  );
  assert.ok(
    !calls.some(
      (c) =>
        c[0] === "eq" && ["available", "specifications->>Metal"].includes(c[1]),
    ),
  );
  response = { data: null, error: null };
  await assert.rejects(
    run("/services/:id", {}, { id: "20000000-0000-4000-8000-000000000001" }),
    (e) => e.status === 404,
  );
});

test("Explore scopes parent-category filters by ancestry IDs for products and services", async()=>{
 response={data:[],count:0,error:null};
 const node='30000000-0000-4000-8000-000000000001';
 for(const route of ['/products','/services']) {
  await run(route,{category:'Food',node,page:'2'});
  assert.deepEqual(calls.find(c=>c[0]==='contains'),['contains','category_path',JSON.stringify([{id:node}])]);
  assert.ok(calls.some(c=>c[0]==='eq'&&c[1]==='category'&&c[2]==='Food'));
  await assert.rejects(run(route,{node:'invalid'}));
 }
});
