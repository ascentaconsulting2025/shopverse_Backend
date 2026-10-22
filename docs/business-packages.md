# Business packages

Apply `migrations/014_business_packages.sql` in the Supabase SQL editor (or with `psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f migrations/014_business_packages.sql`) after migrations 001–013, **before deploying the new API/frontend**. This migration has been tested on PostgreSQL 17, including a rerun. It takes write locks while initializing counts; schedule deployment accordingly. No production migration was run as part of this change.

The authoritative matrix is `business_package_rules.capabilities` in PostgreSQL. Express reads this through the service-only `get_business_package` RPC. `/businesses/:id/usage` returns `planId`, `capabilities`, and `usage`, plus the old flat counts for compatibility. Only the owner or an authenticated administrator may read this endpoint. The dashboard fetches these rules and counts; the frontend's plan descriptions do not authorize database writes.

| Feature | Basic | Standard | Premium |
| --- | --- | --- | --- |
| Profile, logo, leadership, About, QR | Yes | Yes | Yes |
| Gallery images | 20 | 20 | 20 |
| Events | 5 | 5 | 5 |
| Products | Disabled | 20 | 20 |
| Services | Disabled | 20 | 20 |
| Offers | Disabled | Disabled | Enabled, no quota |
| Custom theme/template | Disabled | Disabled | Enabled |
| Package verification | None | 10,000 trusted views | Immediate |

## Counting and writes

- Products/services count every stored row, including drafts, unavailable listings, and items in hidden folders. Hard deletion releases a slot.
- Gallery images/events count active rows whose `deleted_at` is null. Inactive or soft-deleted records do not consume slots; activation/restoration is checked again. Event dates/attendance do not change quotas. Offers use the same active/non-deleted usage convention, but Premium has no offer quota.
- “Images” means the existing gallery section, not logo, leadership portraits, product pictures or event posters. Generic Cloudinary uploads remain shared across these uses; an uploaded asset is not a gallery listing until attached through the gallery API. Attaching via URL, duplicates, bulk inserts and restores all meet the same database rules. Orphan upload storage is not a newly introduced package quota.
- No monthly reset or billing period is introduced. Quotas apply to the current counted set.
- Database triggers lock the parent business, then atomically update usage in the same transaction as the content write. Concurrent requests, bulk statements and service-role RPC writes cannot exceed quotas. A failing statement rolls back both listings and counts.
- Owner/admin authorization remains in Express. Database write grants for business/profile content, categories and section visibility are removed from `anon`/`authenticated`; the browser must use Express for mutations. Service-only RPCs and private usage/view tables cannot be used by an owner to change entitlements or counters.
- Owner full-card payloads may include unchanged `planId`/`isVerified`; changing either is rejected. Nested metadata, embedded listing arrays, ownership fields and client counters are discarded. Table-backed children are the source for public and management responses.

## Activation, downgrade and verification

Package assignment uses the existing authenticated admin workflow: the Admin Panel offers Basic/Standard/Premium both in the business-creation form and on existing business rows. Creation sends the selected package with the business request; existing rows patch the business. The form waits for the API to confirm creation before reporting success. The backend's existing `isAdminUser` check uses the server-managed `ADMIN_EMAILS` list. Owners cannot self-upgrade. New businesses default to Basic; legacy `free` and unknown values are normalized to Basic without deleting their content.

The administrative verify action and package verification use the existing `businesses.is_verified` column and API write path. `apply_business_package` grants the same flag on Premium activation and when Standard's trusted counter reaches **at least** 10,000. It is idempotent; it does not revoke badges on downgrade. An explicit administrator verification change still uses this field; an eligible package immediately satisfies verification again. No public verification endpoint exists.

Per the confirmed product decision, **existing publication and custom theme display survive downgrade**. Nothing is deleted, hidden, or automatically unpublished. Existing records may be edited/deleted; creation and new publication/activation use the current package. Re-enabling a hidden folder/section/profile or moving an item out of a hidden folder is also checked. Existing over-limit content remains intact; adding or reactivating a counted record requires an available slot. Custom appearance data remains stored and displayed, but changing it requires Premium. New non-Premium profiles use the application's baseline Corporate Navy appearance.

Premium and eligible Standard rows are reconciled by the migration using canonical columns. Historical `details.stats.totalViews` was client-writable and is retained in storage for audit purposes but is **not imported as trusted views or used for verification**. The new `profile_views` counter starts at zero where no trusted counter existed. If externally audited historical counts become available, an operator can import them into `profile_views` through trusted SQL; the same trigger applies verification. No additional verification state is needed.

## Protected views

Public profile rendering posts `/businesses/:slug/views`. Express supplies an HMAC of the server-observed client IP and UTC date; clients cannot supply counts or visitor IDs. PostgreSQL deduplicates per business, IP hash and UTC day; raw IP addresses are not stored. Changing browser user-agent strings does not produce extra views. The endpoint is rate-limited, atomic and only counts published profiles. This is a protected daily visitor count rather than unfiltered browser reloads. IP-based counting groups visitors behind shared NATs and cannot prove a human visit.

If deployed behind a reverse proxy, configure `TRUSTED_PROXY_CIDRS` with that deployment's known proxy addresses/CIDRs so Express observes the actual visitor IP. By default forwarded headers are not trusted. Existing client-side interaction analytics are otherwise preserved. There is no public/admin API for setting the trusted counter.

Marketplace browsing and listing reads stay public. No visitor package check was added. Existing cart, saved businesses, connections and authentication/checkout behavior are unchanged; no service booking or checkout behavior was introduced.

## Verification commands

From `shopverse_Backend`:

```sh
npm run build
node --test tests/*.test.cjs
# A fresh disposable local PostgreSQL DB/cluster only; fixture creates Supabase-like roles.
psql "$PACKAGE_TEST_DATABASE_URL" -v ON_ERROR_STOP=1 -f tests/packages-fixture.sql
PACKAGE_TEST_DATABASE_URL="$PACKAGE_TEST_DATABASE_URL" node --test tests/packages-database.test.cjs
```

The database suite is explicitly skipped without `PACKAGE_TEST_DATABASE_URL`. It writes test businesses and intentionally exercises rejected writes and concurrent statements; never point it at production. The fixture includes the legacy social-link columns required by existing migration 008, which are missing from the current schema snapshot.

From `shopverse_frontend/frontend`: `npm run lint` and `npm run build`. Existing plan price numbers are retained; this change adds no billing, payment, expiry, or package-purchasing flow.
