# Cloudinary lifecycle deployment and behavior

Apply `migrations/016_cloudinary_lifecycle.sql` after migrations 001–015, then deploy the backend build. No new environment variables or frontend changes are required. Existing Cloudinary and Supabase service-role configuration remains server-only. The normal server starts the cleanup worker (15-second polling); keep a server process running. Multiple instances are supported.

## Implementation

Previously controllers destroyed assets before database deletion, replacements used fire-and-forget cleanup, and IDs were guessed from URL paths. Offers, profile replacements, product URL galleries, and business cascades were incompletely covered.

Uploads now reserve a unique server-generated ID in a private `cloudinary_assets` ledger before uploading with overwrite disabled. The provider response must match that ID; its exact secure URL is persisted before returning it. A database failure or canceled editor leaves a durable orphan candidate with a 24-hour grace period. Provider failures never change an existing record.

The database trigger covers businesses, leadership, products, services, events, offers, gallery photos, and category images. It resolves URL-only client input against verified upload responses into existing `*_public_id` fields. Partial updates preserve identifiers. Removed or replaced references queue cleanup in the same transaction as the change; transaction rollback also rolls back cleanup. Gallery ordering is untouched. Omitted leadership records retain their historical text but release their photos.

Deletion intentionally commits the reference removal first and performs Cloudinary deletion asynchronously. This differs from the requested delete-first sequence: deleting a cloud asset cannot be rolled back if the database fails. A successful CRUD response confirms the record change, **not physical Cloudinary deletion**. Cleanup normally starts within 15 seconds; provider failures remain pending. The UI and its existing confirmations remain unchanged.

The worker checks every image-bearing table, including URL arrays, business details and inactive records. Soft-deleted content is no longer a live reference. Conservative substring matching protects transformed/URL-only references; a false positive may retain extra storage. Advisory locking coordinates record mutations with claims. Once a job is claimed, new references are rejected, including during timeout retries. Clients must upload again rather than reuse a deleted asset.

Only server-registered assets can be destroyed. Client-supplied IDs never create ledger entries. Existing record ownership checks and upload authentication/rate limits remain intact. Cloudinary `ok` and `not found` are the only accepted results. Failed deletion or acknowledgement leaves a durable five-minute retry deadline; retries use the same identifier. Deleted ledger rows are retained as tombstones.

## Legacy images

Migration 007 historically guessed public IDs from URLs; these are not trusted for deletion. No existing asset is automatically registered. After deployment, optionally run `node dist/scripts/registerLegacyCloudinary.js`. It uses stored IDs solely for read-only Cloudinary lookups, verifies exact returned ID and URL plus the upload's `owner_id` context against its business owner, and registers verified assets. It does not delete assets or modify entity records. Missing IDs, missing ownership context, transformed URLs that cannot be matched exactly, and unmatched records require manual review and remain retained. No database-wide URL rewriting is performed.

## Operations and limitations

Inspect `cloudinary_assets` as a service administrator: `state`, `attempts`, `cleanup_after`, and `last_error` expose retries. A `deleted` row means the worker observed `ok` or `not found`; a `deleting` row must not be reported as confirmed deletion. Do not manually reset deleting/deleted assets to ready while provider calls could still be active.

Grace-period uploads can expire if an editor remains unsaved for more than 24 hours. Reference scans favor safety over throughput and suit this application's scale; monitor their cost before growing to a large catalog. Unknown historical images are deliberately retained. Soft-deleted records cannot be restored with assets already deleted; upload replacements. No actual Cloudinary account or deployed Supabase database was modified or verified during local testing.

## Validation

`npm run build`; `node --test tests/*.test.cjs` for backend regression tests and mocked provider failures. `tests/cloudinary-lifecycle.sql` creates disposable minimal tables and applies the actual migration; never run it against an application database. It verifies shared references, one-image gallery replacement/order, soft deletion, cascades, rollback, orphan grace expiry, reuse rejection and private ledger/RPC access. A separate concurrent PostgreSQL writer/cleanup claim check also passed: the active image was retained. A staging upload/replace/delete smoke test with actual credentials remains required before production deployment.
