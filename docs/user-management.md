# Super Admin User Management

## Deploy in order

1. Back up the database and apply `migrations/017_user_management.sql` after migration 015. This adds an audit table and three service-only functions, plus a transactional Auth trigger. It does not duplicate users or copy passwords. Existing creator information stays unknown; new administrator-created accounts carry a trusted `app_metadata.created_by` ID. Registration and provider changes are audited by the trigger.
2. Configure `PASSWORD_RESET_URL=https://YOUR_FRONTEND/reset-password` on the backend. Allow this exact URL in Supabase Auth redirect URLs. Configure production SMTP and delivery monitoring.
3. Set the Supabase **Reset Password** email template link to:
   `<a href="{{ .RedirectTo }}#token_hash={{ .TokenHash }}">Choose a new password</a>`
   The fragment prevents the recovery token from reaching HTTP access logs. The application removes it from browser history immediately. Do not use the default ConfirmationURL template with this implementation. Ensure the hosting fallback serves the SPA at `/reset-password`.
4. Configure Supabase password requirements, recovery-token expiry, and provider rate limits. The application requires at least 8 and at most 128 characters for recovery; Supabase additionally enforces its configured policy. Leave `PASSWORD_RESET_URL` unset until the template is ready; recovery requests then fail closed.
5. Deploy backend and frontend together. Keep the Supabase service-role key exclusively on the backend. Run a staging recovery end to end with a real mailbox before production rollout.

## Permissions and behavior

The existing `ADMIN_EMAILS` role is displayed as Super Admin; no new roles are introduced. Every management endpoint uses both the existing validated application session and server-side allowlist check. Other users get 403 and a rejection audit. Role and login-email changes are deliberately not available. All Super Admin accounts, including the last active account, are protected against changes through this module. Reserved allowlist emails cannot be claimed through registration or admin Create User; provision administrators through the trusted identity-provider console.

The list queries Supabase Auth through a narrowly projected, service-only SQL function, joined to existing profiles. Search, filters, stable sorting and pagination run in PostgreSQL. Metrics cover all accounts; month boundaries use database UTC. Provider `banned_until` determines active/inactive status. Password status and usernames are omitted because the application does not reliably track/support them. Details include paginated audit history. Full-name edits and audit insertion are atomic.

Recovery requires explicit confirmation and an active, email-confirmed account. The backend asks Supabase to deliver a recovery email; successful delivery acceptance is not reported as a completed password reset. The recovery endpoint verifies a single-use `recovery` token using an isolated client, changes the password under the provider's policy, and signs out provider sessions. The database trigger revokes all application session records in the same transaction as the password change or ban change, so old JWTs and refresh cookies cannot access the backend. A rejected password consumes the link: request a fresh one. No temporary passwords or unsupported “reset required” state are introduced.

Audit records contain only actor/target IDs, fixed event names, outcomes and timestamps. Provider-triggered password/status events have the user/system actor; the administrator's request/result records identify the initiating administrator. Email requests and provider calls cannot share a database transaction: a process interruption can leave a `requested` record without a result; inspect provider logs before retrying. Trigger-generated mutation records remain transactional. Audit history starts with deployment, with no invented historical events. Failed invalid-token recovery attempts have no target ID and are only visible through trusted database operations.

The application limiter allows 10 mutation/recovery attempts per IP per 15 minutes; Supabase limits also apply. For horizontally scaled deployments add a shared limiter or gateway policy. Admin-user creation retains its existing initial-password flow; these are not temporary passwords and do not claim to require a first-login change.

## Validation

- `npm run build` in backend; `npm run lint` and `npm run build` in frontend.
- `node --test tests/user-management.test.cjs tests/admin-user-creation.test.cjs tests/persistent-auth.test.cjs tests/auth-client-isolation.test.cjs` after backend build.
- `tests/user-management-database.sql` runs only against an empty disposable PostgreSQL database; it creates representative Auth/profile/session tables and applies migration 017. It verifies actual SQL execution, legacy records, creator attribution, secret exclusion, access grants, search/filter/sort/pagination, profile auditing, password and ban session revocation.

Live SMTP delivery, hosted Supabase trigger compatibility and browser/mobile interaction require staging verification. The local SQL fixture validates PostgreSQL behavior, not the hosted Auth service. Review managed Auth schema changes on staging before applying to production.
