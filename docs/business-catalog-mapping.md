# Business category mapping (migration 019)

This extends the Category Architecture Desk and canonical `business_categories` table from migration 018. There is no second category editor or duplicate taxonomy.

## Deployment

1. Back up and review your database through the normal deployment process.
2. Apply `migrations/019_business_catalog_mapping.sql` after migrations 001–018, then deploy the backend and frontend together. The new API requires the migration. This change has **not** applied any migration to application or production data.
3. Sign in with an existing Super Admin account (`ADMIN_EMAILS`). Open **Super Admin → Category Architecture Desk**.
4. Create business types such as Jewellery or Hotel using **Category type → Business category**.
5. Create Product and Service trees using the same editor, or import a tree with the appropriate **Import tree type**. Imports are not automatically mapped to every business.
6. In the mapping section, choose a business category and the Products or Services tab. Select permitted category roots, review affected listings, and save.
7. **Create & map product/service category** creates a category and its mapping atomically in the selected business context. The form can also choose an existing same-type parent.
8. Assign an active business category in business onboarding or profile editing. Businesses without an assignment cannot create or save listings until configured.

No additional packages, environment variables, or external services are required.

## Example

Create Jewellery (Business), Gold Jewellery (Product), Earrings and Rings (Product children of Gold Jewellery), and Repair (Service). Map Gold Jewellery in Jewellery's Products tab, and Repair in its Services tab. A Jewellery business then selects Earrings or Rings for products and Repair for services. It cannot select Gold Jewellery itself because it is a group.

## Data and access rules

- `catalog_kind` is `business`, `product`, `service`, or `legacy`. The old provenance `type` column is not repurposed.
- Existing category IDs, bilingual names, images, listing references, and business references remain intact. Existing rows default to **Legacy / unclassified**; no category meaning or business assignment is guessed.
- Classify unused legacy branches explicitly, starting at the root, then their children. Referenced types cannot change through the UI. For referenced historical categories, create the typed replacements and recategorize records deliberately, or prepare an explicit reviewed data migration. There is no automatic name-based merge.
- Business categories are roots. Typed catalog children must have same-type parents. A business category can use many catalog categories; a catalog category can serve many business types without duplication.
- A parent mapping includes active descendants, including future children. Mapping a child includes its ancestors for navigation only, never siblings. Inherited descendants cannot be individually unchecked until the parent mapping is narrowed.
- Only structural leaves are selectable. Disabled children do not turn their parent into a leaf. A disabled ancestor makes the entire branch unavailable.
- Owners cannot edit category definitions or mappings. Mapping tables/RPCs are service-role-only. Existing authenticated session checks, Super Admin checks, business ownership, and package restrictions remain in effect.
- API validation and database triggers enforce allowed type, business mapping, active ancestry, and leaf selection, including direct listing writes and bulk moves. Both relational category columns must agree on new/updated listings.
- Mapping saves are transactional and version checked. Category writes and mapping writes share the existing taxonomy lock; listing checks use a shared transaction lock. Conflicting requests return a reload/retry error rather than silently overwriting mappings.
- Unmapping, changing a business category, or disabling a category preserves existing listing records. Invalid assignments require recategorization on the next save, including unrelated edits. Existing publication rules from migration 018 remain in effect.
- Mapping previews give counts of incompatible listings. Business profile selection previews affected listings. Category edit previews conservatively show all references to a branch that may be affected by hierarchy/status changes.
- Shared category edits affect all mapped business categories. Removing a mapping never deletes the category.
- Existing legacy JSON import requests remain supported. Typed imports deduplicate by type and full path; identically named product/service trees remain separate.

## API additions

All routes use the existing `/api/v1` prefix and authenticated API client.

| Route | Access / purpose |
| --- | --- |
| `GET /categories/:id/mappings` | Super Admin: mapping IDs and current version |
| `POST /categories/:id/mappings/preview` | Super Admin: `{type, categoryIds}` affected-record preview |
| `PUT /categories/:id/mappings` | Super Admin: `{type, categoryIds, version}` atomic replacement for one catalog type |
| `GET /categories/:id/impact` | Super Admin: conservative branch impact |
| `POST /categories` | Adds `catalog_kind`; optional `map_business_category_id` creates and maps together |
| `PATCH /categories/:id` | Adds explicit `catalog_kind` classification, preserving version checks |
| `POST /categories/import` | Optional `kind: product/service/legacy` selects typed import |
| `GET /businesses/:businessId/categories/:type` | Authorized owner/admin: effective tree with `allowed` and `selectable` flags |
| `POST /businesses/:businessId/categories/product/assignment-preview` | Authorized owner/admin: `{categoryId}` previews a business category change for both listing types |

Business `categoryId` continues to reference `businesses.global_category_id`; for new assignments it must now identify an active Business category. Product/service `categoryId` must identify an allowed leaf of the matching catalog type. Gallery category behavior is unchanged.

## Verification

Backend:

```sh
npm run build
node --test tests/*.test.cjs
```

Frontend:

```sh
npm run lint
npm run build
node --import tsx --test tests/*.test.ts tests/*.test.tsx tests/*.test.cjs
node tests/business-catalog.browser.cjs
```

Browser tests use real React components with isolated mocked APIs and local Chrome/Playwright. They do not verify live Supabase sessions or production deployment. Build the backend first because the browser fixture shares the pure catalog resolver.

Database integration, **only in a fresh disposable database**:

```sh
psql "$CATEGORY_TEST_DATABASE_URL" -v ON_ERROR_STOP=1 -f tests/business-catalog-database.sql
```

The SQL fixture creates the baseline schema, runs 018 and 019, verifies reruns/data preservation, then tests inheritance, leaves, type separation, shared mappings, version conflicts, direct-write validation, imports, impact previews, contextual creation rollback, and owner permission boundaries. Never run this fixture against an application database.

## Results from local verification

- Backend build and all 14 Node test-file suites passed. Optional pre-existing database/concurrency suites retain their environment gates.
- Frontend TypeScript check, production build, and all 8 existing frontend test-file suites passed. The production build retains its large-bundle warning.
- New database integration fixture passed against a fresh PostgreSQL 17 instance under `/tmp`, including repeated migration execution and role restrictions.
- New browser integration fixture passed against real React components and mocked APIs. Desktop and 390px mobile screenshots were inspected.
- Live Supabase deployment, production migrations, and real-user end-to-end sessions were not performed.

## Marketplace parent-category navigation (migration 020)

Apply `migrations/020_marketplace_category_hierarchy.sql` after 019, and deploy the updated backend/frontend. The migration adds full ancestry to the existing public product/service views and facet responses. It does not change listing assignments or publication settings.

The marketplace now follows **Food → Maharashtrian → Starters → listings**, with a breadcrumb for returning to any parent. A catalog root that repeats the business category name is shown only once. Other catalog roots remain visible (for example Jewellery → Gold Jewellery → Earrings). Branches appear when they contain published listings; unpublished/disabled records retain the existing visibility boundaries.

Public facet/listing responses add `catalog_category_id` and `category_path` (an ordered array of category IDs, bilingual names, and images). Product/service listing queries accept an optional `node` UUID to match any ancestor in the path. Parent “All” results include descendants. Same-named leaves under different parents remain separate because navigation and filtering use IDs. Historical two-level URLs and sample catalogs remain supported.

Checks:

```sh
# Fresh disposable database only; this fixture creates the baseline schema.
psql "$CATEGORY_TEST_DATABASE_URL" -v ON_ERROR_STOP=1 -f tests/marketplace-hierarchy-database.sql

# Frontend
node --import tsx --test tests/explore-hierarchy.test.ts
PLAYWRIGHT_MODULE=/path/to/playwright CHROME_PATH=/path/to/chrome node tests/explore.browser.cjs
```

The database fixture verifies full parent paths, bilingual labels, ID-based subtree filtering, same-named leaves, product/service facets, unpublished exclusion, disabled ancestors, migration reruns, and service-only database access. Browser tests exercise parent navigation, breadcrumbs, reload/back behavior, branch “All”, sibling separation, service hierarchy, and the existing marketplace journeys against mocked APIs.

### JSONB request encoding

The marketplace node filter passes `JSON.stringify([{id: node}])` to the Supabase `contains` builder. Passing a JavaScript array directly uses PostgreSQL array syntax and causes JSONB queries to fail with `22P02`. `tests/explore-encoding.test.cjs` tests the actual SDK's outgoing URL, alongside route, database, and browser tests. This correction requires only the updated backend; no additional migration is needed after 020. Failed listing requests also clear stale results/counts in the frontend.

### Existing products on public identity pages

Public business responses resolve display categories from the already-published product/service records and their active ancestors, including legacy assignments. New-listing mapping permissions remain enforced separately. This prevents existing published products from disappearing merely because a business has not completed category backfill. Only category metadata associated with public records is exposed.

The shared public category browser also renders API-approved items whose category metadata is absent, including when other category folders exist. Explicitly unavailable categories and unpublished items retain their visibility restrictions. No schema migration is required for this correction.

Regression coverage: `tests/business-catalog.test.cjs` (public metadata and unchanged selection permissions), frontend `tests/public-category-browser.test.tsx` (missing metadata, mixed folders, publication checks), and `tests/public-category-browser.browser.cjs` (all 11 items and legacy folder navigation).

### Deleting unused category branches

Apply `migrations/021_delete_unused_category_branches.sql` after migration 020.
Catalog mappings alone no longer block deletion. The category write RPC removes
an unused category, its descendants, and their mappings in one transaction.
Surviving mapped business categories receive new versions so stale mapping editors
cannot recreate removed assignments. Existing business, product, service, and
gallery references (including archived records) still block the entire deletion.
No listing or business records are deleted. The confirmation dialog describes
branch deletion before the administrator confirms it.

Regression check, on a fresh disposable database only:
`psql -v ON_ERROR_STOP=1 -d <test_database> -f tests/category-deletion-database.sql`.
