# Category Management investigation and verification — 28 October 2026

## Findings

The deployed data uses `business_categories` (global definitions, `catalog_kind`, one `parent_id`, status/publication and version) and `business_catalog_mappings` (business category → catalog category). `businesses.global_category_id` selects a business type; product/service `folder_category_id` references the global catalog. Existing database guards require typed parents to have the same type, and business categories to be roots. Thus a business chosen in the form must become a mapping, not a typed product's physical parent.

The previous desk displayed all global roots, and the mapping editor displayed the entire catalog regardless of selected business. That made available-to-assign categories look like owned categories. The existing merchant `loadCategories`/`resolveCatalog` path already enforced mapped descendants; replacing it would have risked unrelated consumers. Mapped parents intentionally grant all descendants, including future additions. Contextual creation previously accepted a parent without checking whether that parent was shared with another business.

The parent dropdown excluded business categories by requiring matching `catalog_kind`. It did not provide the business-to-mapping translation. Mapping reload depended only on business ID/version, so category changes without a business-version bump left selected IDs stale. The desk initially expanded all global trees. CRUD lacked normalized sibling duplicate checks. Existing API mutation events already invalidate category selectors and marketplace caches and have been preserved.

Deletion uses the transactional `write_global_category` RPC and hard deletion, not status hiding. Migration 021 permits branch deletion and removes mappings, with restrictive reference checks. This change adds conservative API checks for children/shared categories before invoking it. No evidence of a failed live deletion was available; stale mapping state is confirmed in code, but an additional deployed deletion failure cannot be asserted without reproducing it.

## Live read-only audit

A first network attempt failed; a permitted retry successfully read the category and mapping tables. No live CRUD, SQL migrations, resets or reseeding were performed.

| Record | ID | Verified mapping |
| --- | --- | --- |
| Automobile | `116e2c4a-4947-4040-a829-9ea0023130e5` | Business root |
| Motorcycles | `b1f04bd5-eb38-4fc9-8726-2509d3d40a07` | Automobile only |
| Scooters | `67a8a421-1c74-4d57-b799-b1135fa7cb72` | Automobile only |
| Restaurant | `364ca08e-bace-4fd3-9c20-36d1661261e7` | Main Course; Snacks & Street Food |
| Furniture | `e5ced1a0-653e-4595-a2f0-028138634af8` | Existing directly parented legacy children |

Only four mapping rows were returned. No incorrect Motorcycles/Scooters associations were found, so no recovery writes were justified. Legacy similarly named records were not merged or deleted. Furniture's valid legacy parent links remain supported. Jewellery scenarios use isolated fixtures; no Jewellery business record was returned by this live audit.

## Changed files

Backend paths are relative to `shopverse_Backend`:

- `src/modules/categories/integrity.ts`: derive business membership from actual ancestor/mapping IDs; validate contextual parents, cycles, ownership-changing moves, normalized duplicates and lightweight similar names. Preserve legacy links.
- `src/modules/categories/categories.service.ts`: paginated architecture loader combining definitions and mappings.
- `src/modules/categories/categories.routes.ts`: admin-only architecture read; preflight create/edit/import and safe deletion; retain existing URLs, auth and transactional write RPCs.
- `src/modules/categories/import.ts`: Unicode/whitespace normalization of imported labels.
- `tests/category-integrity.test.cjs`, `tests/global-categories-api.test.cjs`: integrity and HTTP-handler regression coverage.
- This category-specific verification report.

Frontend paths are relative to `shopverse_frontend/frontend`:

- `src/api/client.ts`: one additive category architecture method; other API behavior unchanged.
- `src/components/admin/CategoryArchitectureDesk.tsx`: collapsed business roots, mapping-derived trees, legacy children, unassigned catalog disclosure, contextual parent options, duplicate/similarity dialogs, safer deletion text, request ordering and responsive controls.
- `src/components/admin/BusinessCategoryMapping.tsx`: assigned-only default with explicit catalog-library action, reload on category data changes, guarded asynchronous loading, responsive controls.
- `tests/category-architecture.browser.cjs`: real-component browser checks with isolated API fixtures.
- `tests/business-catalog.browser.cjs`: existing regression fixture updated for architecture responses and collapsed/assigned-only UI.

No authentication, business/user management, product/service implementation, global layout/styles, dependencies or schema files were changed. A concurrent `.gitignore` modification in the backend working tree was observed and left untouched; it is not part of this implementation.

## Verification

- Backend TypeScript build: passed.
- Frontend TypeScript lint and production build: passed. Vite retains its large-chunk warning; no build configuration was changed.
- Integrity tests: 6 passed.
- Global category API tests: 13 passed.
- Business catalog resolution tests: 7 passed.
- Category-folder suite: 8 cases passed (runner counts its containing suite as a ninth test).
- Auth-client isolation: 2 passed; persistent auth: 8 passed; user management: 10 passed.
- Frontend category-folder and public-category-browser test files: passed.
- New browser suite: business isolation, collapsed roots, contextual creation, normalized duplicate dialog, deletion and reload, fresh business parent options, 1440/768/390 px viewports passed using real React components and fixture API responses.
- Existing browser suite: mapping inheritance, product/service separation, bilingual contextual creation, stale edit rejection, dependency-delete error, import, real listing forms, profile impact, unmapping preservation and mobile layout passed with fixture responses.
- Inspected mobile screenshot; corrected cramped search/filter layout and added a minimum-search-width assertion.
- Git schema/migration diff is empty. No schema-altering command was executed. Live audit performed SELECT requests only.

## Limits and acceptance boundaries

This is locally implemented and fixture-tested, not deployed. Live category creation/deletion persistence, live reference-integrity checks after writes, and a production UI session were not exercised. Database SQL fixtures were not executed because they create/alter database objects, contrary to the schema restriction. Existing database functions were inspected from repository SQL; their deployed definitions were not independently exported.

The schema represents business membership through mappings, but each shared category still has one global parent/name. Independent per-business parent/name changes for the same record are impossible without changing that model. Shared-parent contextual additions and ownership-changing moves are rejected; explicit mapping edits remain the supported assignment/removal workflow. Global shared definition edits display an impact confirmation. Removing an inherited child alone requires replacing the ancestor mapping with explicit retained descendants; no independent exclusion relationship exists.

Preflight validation and the existing RPC are separate transactions. Concurrent server instances, direct database writers, or mapping changes between validation and commit can race. Existing RPC version/advisory locks protect their own operations, but do not make these new preflight checks atomic. Absolute duplicate/ownership enforcement across concurrent writers would require changing database functions/constraints or another shared transactional facility; none was introduced. Similar-name matching covers normalized spacing, plurals and Jewellery/Jewelry, not a general linguistic fuzzy matcher.

No claim is made that all 18 acceptance tests passed against production. Isolation, duplicate rules, invalid parents, UI state, references/mapping behavior and responsive layout have local automated coverage. Live recovery found nothing to change for the named Automobile records. Production persistence/concurrency verification remains outstanding within the stated schema limitations.
