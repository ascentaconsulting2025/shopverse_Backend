# Global Category Architecture Desk

## Legacy analysis and replacement decision

The user explicitly chose replacement of the existing business category system, rather than keeping independent owner-managed folders.

Inspected legacy files in `../shopverse-old`:

- `src/components/AdminDashboard.tsx`: the Category Architecture Desk navigation and UI; create/edit forms, status toggle, recursive tree, expand/collapse, JSON upload/paste/preview/import, and confirmation dialog.
- `src/contexts/CategoryContext.tsx`: authoritative **browser-only** category array and tree builder; appends categories, replaces edited objects, and recursively removes descendants. Changes are lost on reload and are not persisted to the Express API.
- `src/types.ts`, `StoreCategory`: `id`, `name`, optional `parent_id` / compatibility `parent_category`, optional `image`, `icon`, `status` (`enabled`/`disabled`), `visibility`, optional `created_at`, and derived `subcategories`.
- `src/App.tsx`: mounts the shared CategoryProvider around the application.
- `src/components/SellerDashboard.tsx`: cascading category path selection; the deepest selected node is submitted as a product's `subcategory`; category IDs and merchant assignments determine allowed selections.
- `src/components/CustomerDashboard.tsx` and `src/components/MerchantStorefront.tsx`: read the same context for category trees and browsing.
- `server.ts`: a **separate** in-memory `categoriesTable`; `/api/categories` GET/POST/PUT/DELETE; product create/update category and seller assignment checks; ancestor traversal and separate category/template/attribute routes. Category CRUD has no corresponding database persistence or server role guard.
- `schema.sql`: products contain category IDs as strings but no persisted category table or category foreign key.

Legacy category names are trimmed and nonempty in the desk. Manual creation allows duplicate names; JSON import reuses case-insensitive complete paths (therefore same-named nodes under different parents are distinct). There is no category description, slug column, listing pagination, or user-controlled display-order field in the active desk. The visible tree supports arbitrary nested levels, images, status, timestamps, edit, add-child, and deletion confirmation. Attribute/template panels are disabled (`false && ...`), and are not an active part of this desk.

Legacy browser deletion recursively removes children without checking product references, and editing only checks a self-parent choice. Those unsafe behaviors are replaced by the confirmed requirements: referenced nodes cannot be deleted, and full ancestor cycles are rejected. Merchant category assignment restrictions are not transplanted: the confirmed new requirement makes available global categories selectable by all authenticated users, while existing record ownership and package permissions remain enforced.

## Target architecture and flow

The target uses React/Vite and existing dashboard components, Express/Zod APIs, the existing Supabase session guard, PostgreSQL migrations, and backend-only service-role RPCs. Super Admin is the existing backend `ADMIN_EMAILS` allowlist, represented as frontend role `admin`; this change introduces no separate role model.

Previously, `business_categories` was scoped to a business and product/service type, with owner CRUD and deletion that unassigned items. Deployed databases can also have historical `listing_categories` relations. Migration **018** converts the existing `business_categories` table into the single global source. It preserves existing IDs, names, translations, images, order, visibility, timestamps, and item assignments. The old `business_id`, `type`, and `legacy_category_id` fields remain provenance, are not used for access/scoping, and are omitted from global API responses. There is no second live category API or category table.

Flow:

1. Super Admin opens **Super Admin → Category Architecture Desk**.
2. The desk calls `/api/v1/categories` using the existing authenticated API client.
3. Every mutation passes the existing verified-user/session middleware plus the Super Admin check. Validated fields are passed to a service-role-only transactional RPC.
4. PostgreSQL validates parent integrity, protects references, serializes category writes, increments the version, and saves the row.
5. Authenticated forms retrieve the global list. Options show full paths; unavailable options are excluded except for a retained current assignment.
6. Record ownership/package checks still run on item mutations. The server validates availability, and database triggers independently enforce it on direct writes as well.
7. Product/service lists, individual detail endpoints, business cards, gallery records, marketplace results, and Explore projections resolve names from the category relationship. Historical text is a fallback only for records that have not been explicitly assigned a global category.
8. Successful mutations invalidate marketplace caches and refresh managed cards/selectors, including across tabs. Selectors also refresh on focus. Public browsing keeps its existing published-record access; it receives only category metadata attached to public records, never the global taxonomy endpoint.

## Schema and data preservation

Apply `migrations/018_global_category_architecture.sql` **after 001–017**, using the project's existing Supabase SQL deployment process.

The canonical table retains existing `id` UUID, `name` (trimmed, 1–100 characters), optional Marathi `name_mr`, `image_url`, `display_order`, `is_published`, `created_at`, and `updated_at`. It adds:

| Field | Meaning |
| --- | --- |
| `parent_id uuid null` | Optional parent; self-referencing FK, `ON DELETE RESTRICT` |
| `icon text` | Legacy icon identifier, default `Tag` |
| `status text` | `enabled` or `disabled`; synchronized with `is_published` |
| `version bigint` | Starts at 1 and increments on edits; required for update/delete comparisons |

The API also exposes compatibility aliases `image`, `visibility`, and `parent_category`, plus derived `available` (the node and all its ancestors must be enabled).

Migration details:

- Removes business ownership/type scoping and the business cascade FK from the canonical category table. Original scope values remain intact as provenance.
- Preserves independent same-named folders as independent global nodes. No automatic name merging or sample-category seeding occurs.
- Copies historical `listing_categories` rows, if present, using their existing IDs and metadata; ID collisions abort the transaction for manual review. The old table is a frozen archive. Its mutation trigger also rejects writes from obsolete backend deployments.
- Repoints both existing product/service `folder_category_id` and historical `category_id` FKs to the canonical global table with **RESTRICT**, preserving differing old relationships. New explicit assignments write both relational columns consistently; unrelated edits preserve the original relationships.
- Adds optional `businesses.global_category_id` and `gallery_photos.global_category_id`, also with **RESTRICT**. Existing free-text labels are not guessed or automatically mapped. Newly selected relations use dynamically resolved names instead of new name snapshots.
- Adds parent, sibling-name lookup, creation-order, and referencing-column indexes. The primary key is unique. Category names are deliberately not made unique because legacy manual duplicates were allowed.
- Replaces publication/Explore queries to use the global category and its ancestor availability. Public item publication rules and package enforcement remain; category availability is no longer tied to a former originating business's package. Enabling/reparenting a node that would republish Basic-package products/services is rejected until those records are unpublished or the business is upgraded; ancestor-aware item-move checks preserve the same boundary.
- Removes the old category reorder RPC; owner CRUD URLs return 403 (regular user) or 410 (Super Admin must use the desk). Item moves remain scoped by business ownership and run atomically.
- Enables authenticated-only category reads and blocks direct category mutations with both grants and restrictive RLS. Mutation/import/move RPCs are service-role-only. No privileged key is added to the frontend.
- Reruns preserve intentional deletes, edits, and unassignments; the historical listing import occurs only during initial conversion.

No application/staging/production migration has been applied by this task. Migration execution during verification uses disposable local PostgreSQL databases only. No legacy sample data has been imported. No user records or unrelated tables are dropped.

## Integrity, conflicts, and deletion

The hierarchy write/import RPCs hold a transaction advisory lock. Category edits/deletes compare the supplied `version` against the locked row; stale writes return HTTP 409. A recursive check rejects self-parenting and descendant-parent cycles. Import preview and commit use the same parsing/path rules; commit is atomic, with a 1000-node and 32-level import limit.

Before selection, the backend checks that the category is available. PostgreSQL triggers lock the chosen node and every ancestor `FOR SHARE` while checking availability. These locks prevent disabling, reparenting, or deletion from racing a new selection. Existing disabled assignments are retained on unrelated updates or a resubmission of the same ID.

Deletion is confirmed in the desk and is performed by the version-checked RPC. PostgreSQL's RESTRICT FKs make the reference check/deletion atomic. A category referenced by a product, service, business, gallery record (including recoverable soft-deleted gallery data), historical category column, or child category cannot be deleted. No dependent record is cascaded or silently unassigned. An unused category can be deleted. Reference conflicts return an explanatory HTTP 409.

## APIs

All global category routes require authentication:

| Route | Permission / behavior |
| --- | --- |
| `GET /api/v1/categories` | All authenticated users; optional `search` and `available=true/false` |
| `GET /api/v1/categories/:id` | All authenticated users; UUID and existence checks |
| `POST /api/v1/categories` | Super Admin; category fields only |
| `PATCH /api/v1/categories/:id` | Super Admin; changed fields plus required `version` |
| `DELETE /api/v1/categories/:id` | Super Admin; JSON `{version}`; unused categories only |
| `POST /api/v1/categories/import` | Super Admin; `{structure, preview}`; preview before confirmed import |

Global fields accepted for mutation: `name`, optional `name_mr`, `parent_id`, `image_url`, `icon`, and `status`. Extra fields, invalid UUIDs, blank/oversized names, non-HTTP image URLs, invalid statuses, and missing versions are rejected. Database errors are translated to safe application errors.

Legacy authenticated reads `/api/v1/businesses/:businessId/categories/:type` remain compatibility projections of the **same** global IDs, after existing ownership checks. `/move` still permits owners to move their own items between available global categories. The standalone `/categories` route permits authenticated users without a business to read/select categories.

## Important files

Backend:

- `migrations/018_global_category_architecture.sql`: conversion, FKs, indexes, RLS, status/cycle/selection triggers, transactional CRUD/import/moves, and updated Explore views.
- `src/modules/categories/categories.routes.ts`: global endpoints, strict validation, Super Admin guard, and retired-owner-route protection.
- `src/modules/categories/categories.service.ts`: full paginated data retrieval, ancestor availability, category validation, dynamic name resolution, compatibility projections, sanitized errors.
- `src/modules/categories/import.ts`: bounded parser for legacy nested JSON.
- `src/routes/index.ts`: mounts the global category API.
- Product/service services and controllers: validated global references, disabled-assignment preservation, dynamic category names.
- Business schema/mapper/controller and content schema/service/controller: global relations for onboarding, card editing, and gallery records; name resolution on reads.
- `tests/global-categories-api.test.cjs`, `tests/category-folders.test.cjs`, `tests/global-categories-database.sql`, and `tests/global-categories-concurrency.test.cjs`: permission, workflow, migration, and competing-transaction coverage. Existing package/theme mock clients now support category pagination.

Frontend (`shopverse_frontend/frontend`):

- `src/components/admin/CategoryArchitectureDesk.tsx` and `AdminPanel.tsx`: dashboard navigation, category editor/tree, search/status filter, confirmation, version conflicts, and JSON preview/import.
- `src/components/categories/CategoryManager.tsx`: global browsing and item moves, with owner category mutation controls removed.
- `src/components/categories/GlobalCategorySelect.tsx`: shared database-driven selector for business and gallery forms.
- `src/components/dashboard/ProductsTab.tsx`, `ServicesTab.tsx`, `EditCardTab.tsx`, `GalleryTab.tsx`, and `src/components/onboarding/OnboardingWizard.tsx`: replace editable/preset categories with shared selections; preserve current references.
- `src/api/client.ts`, `src/context/AppContext.tsx`, `src/types.ts`, `src/utils/category.ts`: API integration, cache invalidation, managed-card refresh, relation types, and hierarchy paths.
- `tests/global-categories.browser.cjs`: real React desk and real product/service forms against isolated mocked APIs; `tests/category-folders.browser.cjs` retains the old test command as an entry point. Folder-page and owner-form regression fixtures are adapted to the global selector.

## Deployment and local verification

No new packages or environment variables are required. Keep the backend's existing `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`, `SUPABASE_ANON_KEY`, and `ADMIN_EMAILS`; retain existing Cloudinary, CORS, and session settings. Keep the frontend's existing `VITE_API_URL`. Only backend environment configuration contains the service-role key.

1. Apply migrations 001–017 if needed, then 018 through the Supabase SQL editor or your existing migration deployment process. Review any collision/schema error rather than resetting the database. Coordinate API/frontend deployment with the migration because the old owner category behavior is retired.
2. Backend: `npm run build`, then `npm start` (or `npm run dev` locally).
3. Frontend: `npm run lint`, `npm run build`, and `npm run dev` for local use.
4. Sign in with an email listed in `ADMIN_EMAILS`. Open Super Admin → Category Architecture Desk. Create a main category and child; rename them; test status changes and JSON preview/import; delete an unused leaf.
5. Sign in as a regular owner. Create a product and a service using the same category, reopen both, then edit unrelated fields while that category is disabled. Verify current assignments persist and unavailable categories cannot be selected for new records. Check onboarding, business editing, gallery selection, public cards, and Explore.
6. Attempt to delete the referenced category as Super Admin and attempt direct category mutation as a regular user; expect 409 and 403 respectively.

Automated commands:

```sh
# Backend, from shopverse_Backend
npm run build
node --test tests/*.test.cjs

# Frontend, from shopverse_frontend/frontend
npm run lint
npm run build
node --import tsx --test tests/*.test.ts tests/*.test.tsx tests/*.test.cjs
node tests/global-categories.browser.cjs
```

The browser test uses installed Playwright/Chrome; set `PLAYWRIGHT_MODULE` and `CHROME_PATH` if they are elsewhere. It serves an isolated fixture with mocked APIs and never signs into or modifies a real account. Screenshots are written to a temporary directory.

Database suites **only in fresh disposable databases**, never an application database:

```sh
psql "$CATEGORY_TEST_DATABASE_URL" -v ON_ERROR_STOP=1 -f tests/global-categories-database.sql
CATEGORY_TEST_DATABASE_URL="$CATEGORY_TEST_DATABASE_URL" node --test tests/global-categories-concurrency.test.cjs
```

The concurrency fixture intentionally restricts execution to the disposable `/tmp` PostgreSQL instance on port 55438 and a `shopverse_categories_test...` database. Without that environment variable, the concurrency suite is skipped. Do not change this safeguard to point at a live database.

## Verification results and remaining deployment checks

Executed checks and results are recorded after final verification below. The production build reports the existing large-bundle warning; this does not fail the build. Live Supabase deployment, real-user session smoke tests, and a real Cloudinary upload remain deployment checks; mocked browser tests do not claim to verify those services.

Final executed results (25 October 2026):

| Check | Result |
| --- | --- |
| Backend `npm run build` | Passed |
| Backend `node --test tests/*.test.cjs` | Successful run across 13 test-file entries; optional database suites require their environment variables and were also executed separately below |
| Global API/session/role/validation tests | 8 cases passed, including forged roles, old-route bypasses, safe errors, and package errors |
| Category migration with existing folders + historical listing taxonomy | Passed; includes repeated migration, unchanged item data/IDs, safe deletion, disabled selections, cycle/stale-write rejection, imports, direct RLS/grants, business/gallery references, intentional deletion followed by migration rerun, and package-aware activation/reparenting/moves |
| Fresh-install SQL suite without `listing_categories` | Passed, including repeated migration and failed-parent-edit rollback |
| Competing category transactions | All 5 scenarios passed against the completed migration (assignment-before-delete, delete-before-assignment, stale edit, opposing parent changes, disabled ancestor) |
| Existing package database regression suite on migration 018 | All 13 scenarios passed, covering quotas, direct database permissions, concurrent requests, verification, publication, migration reruns, and parent deletion |
| Frontend `npm run lint` | Passed |
| Frontend `npm run build` | Passed; large-bundle warning remains |
| Frontend TypeScript/TSX/CJS regression command | All 8 test-file suites passed |
| Real component browser suite with mocked APIs | Passed: desk CRUD, hierarchy expand/collapse/search, stale-edit failure, JSON preview/import, referenced/unused deletion, product/service creation and reopening using the same category, retaining disabled assignments, excluding unavailable defaults, removed owner controls, public visibility, and mobile overflow |
| Screenshot review | Desktop and 390px mobile screenshots inspected; corrected title contrast and mobile row wrapping |
| `git diff --check` in both repositories | Passed |

The browser fixture exercises real React desk/product/service components but mocks remote APIs. API tests exercise the actual authentication/route handlers with mocked provider data; the SQL and concurrency tests execute real PostgreSQL statements. Live Supabase sessions, production migration/deployment, and real Cloudinary upload remain unverified. Existing unrelated working-tree changes were preserved.
