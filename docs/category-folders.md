# Product and service category folders

Apply `migrations/010_category_folders.sql` after migrations 001–009 and before deploying the updated API/frontend. The inspected Supabase schema already has `products.category_id` and `services.category_id` referencing the shared `listing_categories` table. The migration **preserves those columns, foreign keys and records**. Business folders use the separate `folder_category_id` column; the frontend/API property remains `categoryId`.

Assigned listing categories are imported once per business and item type, retaining their names, images, ordering and active status. The same shared category used by products and services becomes two independent folders. `legacy_category_id` records the source, and `folder_assignment_migrated` prevents reruns from reversing intentional moves, unassignments or category deletions. Existing item fields are untouched. Items without a listing-category assignment remain Uncategorized. New folders do not require a shared listing-category record. Product availability remains independent of publication.

The migration is transactional and rerunnable. Live-schema inspection was read-only; the revised migration must still be run in the Supabase SQL editor, followed by rebuilding/redeploying the updated backend.

Category names/images/order/publication are authoritative in `business_categories`, scoped by business and type. Database composite foreign keys enforce that assignments cannot cross businesses or types. Deletion sets only `folder_category_id` to null. Bulk moves and reorder operations run in database transactions; their RPCs are restricted to the backend service role. Owner/admin authorization is checked before each management route.

The admin Products and Services screens independently support image folders, editing, publication, ordering buttons, item checkboxes, drag/drop and Move to Category. Both existing item forms retain all fields and add a category selector and publication checkbox. Public sections use circular folder navigation with Back to Categories. Empty folders are omitted; businesses without folders retain their direct item listings. Category publication and item publication are enforced by public endpoints and restrictive item RLS policies.

Management routes under `/api/v1/businesses`:

- `GET/POST /:businessId/categories/:type`
- `PATCH/DELETE /:businessId/categories/:type/:id`
- `POST /:businessId/categories/:type/move` with `{ids, categoryId}` (`null` unassigns)
- `POST /:businessId/categories/:type/reorder` with the complete ordered `{ids}` list
- `GET /:businessId/products/manage` and `GET /:businessId/services/manage`

All management routes require authentication and ownership (or existing platform admin authorization). The original public item list/detail URLs remain public, with visibility filtering. Images use the existing upload picker/Cloudinary flow. Replacing/deleting a category does not delete uploaded media, avoiding damage to shared image URLs.

## Verification

Backend: `npm run build && node --test tests/*.test.cjs`.
Frontend: `npm run lint && npm run build`. Browser fixtures: `node tests/category-folders.browser.cjs` from the frontend directory, with `PLAYWRIGHT_MODULE` and `CHROME_PATH` set if Playwright/Chrome are installed outside that project. This uses mocked API responses, tests public navigation, editing, image URLs, moves, failure recovery, deletion and mobile overflow, and writes screenshots to a temporary directory.

SQL regression suite, **only against a fresh disposable database**, never production:

```sh
cat tests/category-fixture.sql migrations/010_category_folders.sql tests/category-folders.sql | psql "$TEST_DATABASE_URL" -v ON_ERROR_STOP=1
```

The SQL suite checks migration execution, cross-business/type rejection, atomic failed bulk moves, ordering, safe deletion, and anonymous publication policies. Browser fixtures do not verify a live Cloudinary upload or a deployed Supabase session; run that final smoke test after applying the migration in staging.

For the inspected legacy schema, run `psql "$TEST_DATABASE_URL" -v ON_ERROR_STOP=1 -f tests/category-legacy.sql` against a fresh disposable database. It tests shared categories across two businesses and both item types, repeated migration, metadata preservation, intentional unassignment/deletion, and independent new folders.

## Bilingual categories and move permissions

Apply `migrations/011_bilingual_category_names.sql` to add the optional Marathi name. The original `name` remains the English/legacy fallback; `name_mr` is edited separately. Both the admin interface and public folder navigation follow the selected English/Marathi language. Unassigned public items continue to render directly without an Uncategorized folder.

The backend must be rebuilt/restarted after the auth-client fix. Login and registration now use fresh anonymous Supabase clients, while database operations retain the service-role authorization header. Do not grant `move_category_items` or `reorder_categories` to anonymous/authenticated roles to work around a permission error; their existing backend-only grants are intentional. `tests/auth-client-isolation.test.cjs` verifies login, registration, and subsequent service-role RPC calls with the real SDK and mocked network responses.
