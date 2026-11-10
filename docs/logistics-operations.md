# Logistics operations rollout

Implemented from the supplied logistics product/design brief, while retaining the earlier decision that a seller must **explicitly select delivery** after confirming the order. This is repository implementation, not a deployed service or an editable Figma file.

## Open the platform

- Admin: `/delivery-management`, also linked in the signed-in administrator profile menu. Existing `/admin` → **Delivery management** remains available.
- Partner: `/delivery-partner` → approved partner overview.
- Seller: store dashboard → Orders → confirmed order → **Manage delivery**.
- Customer: account → order history → **Track delivery** → **Confirm receipt** after arrival.

Use the application's existing origin for these paths. Admin access uses the existing server-side `ADMIN_EMAILS` configuration and authenticated session. No separate logistics password or fleet account is introduced.

## Deployment order

1. Back up the database and apply any missing migrations 029–033 in order. Migration 032 requires Supabase storage. Do not reapply migrations already installed.
2. Apply `migrations/034_logistics_operations.sql` through the normal Supabase migration process. It is additive, creates private service-role tables/functions, and does not enroll historical orders or enable allocation.
3. Deploy the backend and frontend together. Set `LOGISTICS_WORKER_ENABLED=true` on the existing **always-running Express host**, then restart it. Never expose the service-role key to the frontend.
4. Open Reports and verify a recent worker heartbeat. The worker runs every 15 seconds, processes up to 200 tasks per transaction, rotates rows fairly, and uses a database advisory lock across replicas. Deadlines persist through restarts. If the host sleeps or is serverless, use an existing trusted scheduler to invoke `process_delivery_jobs()` with server-side credentials instead; do not expose an unauthenticated HTTP trigger.
5. In Settings enter and save the actual timeout, radius, workload, location, and scoring decisions. No production defaults are assumed; weights must total 100. Enable new requests only when the worker is healthy.
6. Review partner applications as before. In Partner management → **Capacity & shift**, configure structured kg/litre/concurrency limits for approved profiles. The prior free-text vehicle capacity is not parsed automatically. For salaried partners set employee ID, employment active, and a dated shift window. To onboard a new employee use existing account creation and verified partner onboarding, then configure that approved profile as salaried.
7. Partners choose to go online and explicitly share browser GPS. Offline location updates are rejected and going offline clears the stored location. Salaried partners can go online within their configured active shift. New allocation requires fresh, sufficiently accurate GPS and matching service area/vehicle/capacity.
8. Seller/admin selects delivery for a confirmed store order, providing verified pickup/customer coordinates, package weight/volume and eligible vehicles. The destination address comes from the saved marketplace order, not a client-supplied replacement.
9. Run a staging delivery with separate seller, partner, customer and admin accounts before accepting live traffic.

## Workflow and safeguards

- One delivery task per store order, linked to the existing marketplace parent order. Duplicate requests return the same task.
- Eligible independent partners receive private offers during the configured window; first transactional acceptance wins. A late/competing acceptance fails, never creates a second assignment.
- Capacity checks account for all active assignment counts and aggregate package weight/volume. Eligibility is rechecked under the partner lock.
- After timeout the worker searches salaried candidates from the smallest configured radius outward, scores distance/workload/route estimate/availability/vehicle fit, and waits for acknowledgement. Expired/rejected salaried attempts are not retried indefinitely. Exhaustion creates an admin exception.
- Manual reassignment requires a reason, waits for the independent window, rechecks eligibility, and is allowed only before pickup. Post-pickup problems must be reported as exceptions. Cancellation does not silently cancel the marketplace purchase.
- Partner progression: acknowledge (salaried/manual) → reached pickup → picked up → on the way → reached customer. Arrival waits for the authenticated order customer. The partner/admin cannot complete delivery on the customer's behalf.
- Customer confirmation atomically completes delivery and marketplace store order, releases capacity and records one deferred compensation event. Repeated confirmation is idempotent. Overdue receipt becomes an exception, never automatic completion.
- Settings changes, configuration changes, allocation attempts, status transitions, manual reasons and exception resolutions retain actor/time records. Live task configuration is snapshotted; new settings apply to new tasks.
- Customer contact/address is absent from offers and visible only to authorized task viewers after assignment. Task access is checked against customer, seller, current partner or server-derived administrator identity. Private tables and actor-accepting RPCs are inaccessible to browser roles.
- In-app notifications persist in the database for offers, assignment, milestones, completion and admin exceptions. Reassigned/cancelled partners are notified. Notification read actions are scoped to the recipient/admin.

## Deliberate limits and remaining product work

- GPS is explicitly shared by the partner; there is **no background/offline tracking or continuous live map**. Active task details show the most recent online location if less than five minutes old, with timestamp/accuracy and an external map link. Navigation opens the user's map provider. Distances are straight-line estimates, not road routing or ETA promises. The route score estimates proximity of existing delivery destinations to the new pickup (or current location for an idle partner); it is not a road-route optimizer.
- Shift configuration is a dated interval, not a recurring roster. Availability still requires the partner's choice and browser location consent.
- Notifications are in-app only. Push/SMS/WhatsApp dispatch, notification preferences and escalation channels require a provider/decisions.
- Fees, payouts, settlement, incentives and earnings are deferred. Compensation records count completed deliveries and do not invent money amounts.
- Existing per-store checkout is preserved. Multiple store orders can have individual tasks under a parent, but a new shared multi-seller checkout transaction/consolidated route is not added.
- Reports provide all-time state counts, open exceptions and worker heartbeat. Advanced date-range analytics, exports, a live dispatch map and route optimization remain separate work.
- The UI is an operational implementation of the essential flows, not every illustrative Figma screen. No Figma file was created. Existing account, document verification and marketplace features remain in place.
- A single global allocation lock favors correctness at this initial scale. Load-test and partition allocation before high-volume rollout. A failed worker transaction rolls back its batch and retries next tick; stale heartbeat requires operator attention.

## Verification

- Backend TypeScript check/build and frontend TypeScript check/Vite build.
- `node --test tests/logistics-api.test.cjs tests/delivery-admin-api.test.cjs` after backend build: admin gates, authenticated actor propagation, injection rejection, receipt identity, forbidden completion transitions, settings validation.
- `tests/logistics-lifecycle.sql` against an isolated migrated Postgres: ownership, explicit selection, config requirement, priority, capacity, lifecycle, fallback, acknowledgement timeout, exception, confirmation, idempotency, privacy and offline GPS. Fixtures roll back.
- `python3 tests/logistics-concurrency.py`: clones the disposable local test database, races two sessions for one delivery and two reservations for one partner, asserts one winner/capacity ceiling, then drops the clone. Never point it at production.
- Frontend browser tests use real components and compiled CSS with mocked APIs: `tests/logistics-flow.browser.cjs`, `delivery-dashboard.browser.cjs`, `logistics-admin.browser.cjs`. They verify private offers, explicit selection, confirmation/cancel choice, partner restrictions, settings empty state, and mobile layouts. Screenshots inspected at 390 px and 1440 px.
- Vite emits the existing large-bundle warning. No production migration, host restart, push provider integration or live-account delivery test has been performed.
