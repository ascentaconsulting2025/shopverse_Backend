# Persistent authentication and image processing

## Verified causes

- Login returned a Supabase session, but the browser saved only its access token. There was no refresh endpoint or shared recovery handler; expired credentials were consequently rejected by every protected API.
- Startup restored the displayed identity and role from local storage without checking the provider. This let the UI appear authenticated while the API correctly rejected missing/expired credentials.
- Administrator navigation to the landing page cleared the displayed identity. Account switching changed that identity without changing the bearer token. Legacy unused OTP/registration/password-reset methods also created local-only identities.
- Logout previously returned a message without revoking anything.
- The cropper allowed arbitrary ratios, Reset returned to Original, and exports retained arbitrary source dimensions. Offers/events used banner presets. Imported URLs could bypass cropping/uploading.
- Product/service/logo replacement deleted the old asset before the database update succeeded.

Supabase admin/database client isolation was already present and has been retained. No alternative JWT secret or second authentication provider was introduced.

## Authentication implementation

- `src/modules/auth/session.ts`: persistent HttpOnly refresh cookie, absolute session lifetime, registry validation, and access-only session responses. Cookies use Secure in production (also whenever SameSite=None), Path=/api/v1/auth, and SameSite=Lax by default.
- `src/modules/auth/auth.controller.ts`, `auth.routes.ts`: login/register create a registry entry; POST /auth/refresh rotates through Supabase; logout revokes the registry and the local Supabase session and clears the cookie. A process-local operation coalesces simultaneous rotations.
- `src/middlewares/authGuard.ts`: strict bearer parsing, provider validation, registry validation, banned-account checks, current server-derived administrator permissions, and private/no-store responses. Provider outages return 503 rather than masquerading as invalid credentials.
- `src/app.ts`: credential-aware CORS and origin checks on authentication mutations, with no-store authentication responses.
- Frontend `src/api/client.ts`: memory-only access tokens; shared refresh; Web Locks to serialize refresh/logout across tabs; one replay preserving the request configuration; no recursive refresh; no logout for 403/network/5xx errors. Public requests omit credentials. Login changes notify other tabs; logout clears their active state. Responses from a previous identity generation are rejected.
- Frontend `src/context/AppContext.tsx`, `src/App.tsx`: server-validated startup, protected-content loading/error/retry state, one business fetch during restoration, consistent session-ended handling, removal of private entity caches and stored passwords, and persistent administrator navigation. Public pages remain usable when restoration encounters an outage. Local-only identity switching/OTP/password resets no longer claim to authenticate users.

The product has one authenticated account per browser cookie context. Switching to another account requires sign-out and another sign-in; this avoids displaying one account while sending another account's token. There is no separate saved-session account manager.

## Image implementation

Presets live in backend `src/config/imageSpecs.json` and frontend `src/utils/imageSpecs.json`, with a contract test requiring them to match. Each repository remains independently buildable; a build-time import from the sibling repository is deliberately avoided.

| Type | Output |
| --- | --- |
| Profile / logo / category square upload | 512 × 512 |
| Product / service / gallery / event / offer | 1200 × 900 |
| Existing business cover banner | 1600 × 900 |

- The shared ImageUploadField → MediaUploadModal → ImageCropper flow locks the relevant ratio, supports repositioning/zoom/rotation, exports configured dimensions, and provides final previews. Logos can retain the whole mark on white padding.
- Required media types use the processed upload path for device images and newly imported remote images. Remote sources must permit browser CORS access; otherwise download the image and choose the local file. Category URL entry remains compatible with the existing category editor; categories are outside the requested mandatory crop types.
- Uploads require a separate Apply confirmation. Cancel preserves the existing record even after an upload; a failed upload can be retried. An in-flight guard prevents duplicate uploads, and a form submit listener blocks the containing form while the picker is open. A shared image-activity guard also rejects record mutations until the picker is applied or cancelled, covering save buttons outside forms.
- JPG/PNG/WebP and 10 MB limits apply in the frontend and multipart backend. The authenticated backend retains the existing Cloudinary folder, adds owner/type context, restricts decoded formats/resource type, applies a trusted incoming transformation, and verifies returned output dimensions. Incorrect processing results are destroyed instead of returned as successful uploads. API secrets remain on the backend.
- Existing URL/public-ID database relationships are retained; owner/team profile public IDs are inferred when omitted. Product/service/logo replacement cleanup follows a successful database save. Replacement cleanup checks normalized references across image-bearing tables and skips deletion when those checks fail or find another reference.
- Dashboard, public-card, Explore and relevant marketplace image frames use 4:3 containers; profile/logo/QR containers remain square. Existing object-fit behavior avoids stretching.

## Required deployment steps

1. Apply `migrations/015_auth_sessions.sql` as a privileged Supabase migration **before** deploying the new backend. The table is service-role-only, with RLS and foreign keys to auth users/sessions. Provider session deletion cascades into registry removal. Do not expose service-role credentials.
2. Build and deploy both repositories together (`npm run build` in the backend; `npm run lint && npm run build` in frontend/frontend). Generated backend dist files are rebuilt from source; new files under dist may be ignored by Git, so do not deploy a partial hand-copied dist tree.
3. Set `SESSION_DAYS` (default 30, bounded 1–90). This is an absolute lifetime; refresh cannot extend it. Set `NODE_ENV=production` with HTTPS. Keep the provider access JWT lifetime short (for example 15 minutes) and keep Supabase refresh rotation/reuse detection enabled. Supabase's reuse grace handles rotation retries across separate server instances; no distributed lock was added.
4. Configure exact `CORS_ORIGIN` values and `ADMIN_EMAILS`. Prefer same-site frontend/API hostnames. For genuinely cross-site HTTPS deployments set `AUTH_COOKIE_SAME_SITE=none`; browsers that block third-party cookies require a same-site API hostname or reverse proxy.
5. Existing access-only browser sessions require one new sign-in. Existing image records are retained and are not retroactively recropped.
6. For administrative application-session revocation, set `auth_sessions.revoked_at` for the applicable user/session, or revoke the corresponding provider session. Expired/revoked rows fail closed on every protected API request.

## Verification results

- Backend TypeScript build: passed.
- Frontend TypeScript lint and production Vite build: passed. Vite still reports a large-chunk advisory.
- Backend unit/controller suites: 50 assertions/tests passed; one database integration test skipped because PACKAGE_TEST_DATABASE_URL was not configured. Tests use mocked external service boundaries.
- Frontend unit suites: 13 tests passed (description rich text, package usage, theme configuration).
- `tests/auth-images.browser.cjs`: passed with installed Chrome. Covers twelve simultaneous expired protected requests, single refresh, PATCH/body replay, 403/500/network distinctions, bounded retries, startup reload and logout, locked crop/reset output, actual 512×512 and 1200×900 exported pixels, logo padding, cropped PNG multipart upload, upload failure/retry, explicit application, and record-save blocking during unresolved edits. Also mounts the actual AppProvider, restores a protected deep link, verifies one business fetch, preserves login during navigation, and rejects identity-only switching.
- Existing category browser suite: passed, including creation/editing, failed moves, folder isolation, deletion and mobile overflow. Its auth fixture now sets the memory token and returns credential-compatible CORS headers.
- Existing Explore browser suite: passed, including public browsing, detail routes, retries, filters, saved items, gallery/zoom, contact flow and responsive widths.

These browser tests mock Supabase/Cloudinary HTTP boundaries. A live login, browser restart with the real persistent cookie, provider-driven password-change/ban/revocation policies, actual migration execution, actual Cloudinary storage dimensions, and live CRUD across every module still require a configured staging environment. No live database migration or external asset upload was performed.

Cancellation after an upload can leave an unreferenced asset. No background abandoned-upload collector or retroactive legacy image conversion was added. Replacement reference checks are conservative best-effort checks rather than a transactional asset-reference service; failed cleanup retains assets rather than risking data loss.

Provider behavior follows [Supabase sessions](https://supabase.com/docs/guides/auth/sessions), [refreshSession](https://supabase.com/docs/reference/javascript/auth-refreshsession), and [admin signOut](https://supabase.com/docs/reference/javascript/auth-admin-signout).
