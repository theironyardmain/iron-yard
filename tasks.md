# The Iron Yard — Task Breakdown

Implementation task list derived from `brain.md` §8 (Build Order). This file tracks *what
gets built and in what order*; `brain.md` remains the source of truth for *what the app is*.

When a feature changes, update `brain.md` first (and its change log), then adjust the
affected tasks here.

Last updated: 2026-09-19

**Status key:** `[ ]` not started · `[~]` in progress · `[x]` done · `[!]` blocked

---

## Phase 0 — Project Foundation ✅

Completed 2026-09-19. Flutter 3.41.9 / Dart 3.11.5, Android-only, app id `com.theironyard.app`.

- [x] **0.1** Create Flutter project, set package name / app id, configure Android target
      (iOS dropped — Android-only per owner decision)
- [x] **0.2** Add dependencies: `supabase_flutter`, `drift`, `drift_flutter`,
      `sqlite3_flutter_libs`, `flutter_local_notifications`, `qr_flutter`, `mobile_scanner`,
      `connectivity_plus`, `flutter_riverpod`, `path_provider`, `intl`, `timezone`,
      `shared_preferences`; dev: `drift_dev`, `build_runner`
- [x] **0.3** Set up folder structure (`core/`, `data/`, `features/`, `shared/`)
- [x] **0.4** Supabase config via `--dart-define-from-file=env.json`; `env.json` gitignored,
      `env.example.json` committed. *(Creating the actual Supabase project is Phase 2.1.)*
- [x] **0.5** Lint rules + `flutter analyze` clean, `flutter test` green (11 tests)
- [x] **0.6** Verified: debug APK builds for Android
- [x] **0.7** Web target added 2026-09-20 as a **development preview only**
      (`flutter run -d chrome`), so the app can be checked without installing an
      APK. Android remains the shipping target — local notifications do not work
      on web, so `brain.md` §6.7/§6.9 reminders and daily check-in are
      Android-only. Required wiring Drift's WASM backend (`web/sqlite3.wasm` +
      `web/drift_worker.js`, both committed) and moving `AppDatabase.memory()`
      behind a conditional import: `package:drift/native.dart` pulls in
      `dart:ffi`, which broke the web compile even though only tests used it.

**Notes carried forward:**
- `drift`/`drift_dev` pinned to `^2.34.0` — 2.34.6+ needs `analyzer >=13` → `meta ^1.18.3`,
  but Flutter 3.41.9 pins `meta 1.17.0`. Revisit on SDK upgrade.
- `sqlite3_flutter_libs` resolves to `0.6.0+eol`; this is the supported path for Drift on
  Flutter (required by `drift_flutter`), not a defect.
- Core library desugaring enabled in `android/app/build.gradle.kts` —
  `flutter_local_notifications` requires it. `minSdk` raised to 23 for `mobile_scanner`.
- `*.g.dart` is committed (not gitignored) so clean checkouts build without codegen.

---

## Phase 1 — Drift Local Database ✅ (brain.md §8 step 8, pulled forward)

> Built early, not late — every feature below depends on it. See `brain.md:192`.

Completed 2026-09-19. 17 tables, 5 DAOs, 37 database tests (48 total), analyzer clean.

- [x] **1.1** Drift tables mirroring the 12 Supabase tables, plus 5 local additions:
      `emergency_contacts`, `exercise_completions`, `feedback`, `sync_queue`, `sync_state`
- [x] **1.2** `SyncColumns` mixin — `id`, `created_at`, `updated_at`, `is_deleted`,
      plus `is_dirty` (local-only, never uploaded) to mark rows awaiting upload
- [x] **1.3** Foreign keys defined **and enforced** — `PRAGMA foreign_keys = ON` in
      `beforeOpen`; Drift leaves them off by default, so without it the references
      would be decorative. Covered by a test that fails if the pragma is removed.
- [x] **1.4** `sync_queue` (device-only) + `sync_state` (per-table high-water mark,
      so one table failing does not stall the others)
- [x] **1.5** DAOs: `ProfileDao`, `MembershipDao`, `AttendanceDao`, `PaymentDao`,
      `SyncDao`, over a shared `SyncedDaoMixin` (soft delete, dirty tracking, batch upload)
- [x] **1.6** `schemaVersion = 1`, `MigrationStrategy` with an `onUpgrade` stub and indexes
      created in `onCreate`
- [x] **1.7** 37 tests against an in-memory database
- [x] **1.8** Riverpod providers exposing the database and each DAO

**Design decisions made here:**
- **Money as integer paise**, not double — floating point accumulates error across
  revenue reports.
- **Date-only `attendance_date`** separate from `check_in_at`, so the one-visit-per-day
  rule is a plain uniqueness check that two timestamps either side of midnight cannot
  defeat. Partial unique index `WHERE is_deleted = 0`, so a soft-deleted record frees
  the day again.
- **QR upgrades a self-report** for the same day rather than being rejected as a
  duplicate — the staff-verified source must win for reporting (`brain.md` §6.7).
- **`countForDay` defaults to `verifiedOnly: true`** — the safe default while open
  question #1 is unanswered.
- **UUIDs generated on-device**, so rows created offline have stable identity from
  creation and never need a local→server id remap on upload.
- **Templates are copied on assign**, not referenced, so editing a template does not
  silently rewrite a plan a member is already following.
- **`emergency_contacts` excluded from `syncedTableNames`** — device-only per
  `brain.md` §6.2, and kept off `profiles` so a future profile sync cannot sweep it up.

---

## Phase 2 — Supabase Schema & RLS ✅ *(written, not yet applied)*

Completed 2026-09-20. 6 migrations, 28 RLS/constraint assertions passing.

> **Not yet pushed to a live project.** Validated against a throwaway
> PostgreSQL 18.6 cluster with Supabase objects stubbed (no Docker on this
> machine for `supabase start`). Apply with `supabase link` + `supabase db push`.

- [x] **2.1** 14 tables in `supabase/migrations/20260920000001_schema.sql`
- [x] **2.2** `updated_at` index per synced table + foreign-key and query indexes
      (Postgres does not index FKs automatically)
- [x] **2.3** RLS for all three roles, with `force row level security` so even a
      table owner is subject to policies
- [x] **2.4** Partial unique index on `(member_id, attendance_date)` where
      `is_deleted = false` — matches the local Drift index
- [x] **2.5** Capacity trigger holding `select ... for update` on the class row.
      **Verified with two concurrent connections:** the second is rejected with
      "Class is full", final count 1 — a plain count-then-insert would overbook.
- [x] **2.6** Three buckets: `receipts` (private), `exercise-images` and
      `profile-photos` (public, so the client can cache by URL for offline view)
- [x] **2.7** `supabase/tests/rls_test.sql` — 28 assertions, each attempting a
      real breach
- [x] **2.8** `supabase/tests/check_schema_parity.py` — mechanically diffs the
      Drift schema against Postgres; verified it fails on an injected mismatch

**Found and fixed during this phase:**
- **Missing table grants.** RLS filters rows only *after* the role holds the
  table privilege; policies alone would have returned "permission denied" on a
  self-hosted or restored database. Added `20260920000006_grants.sql`. Hosted
  Supabase grants these by default, so this was latent rather than breaking.
- **The RLS suite was initially passing on leftover privileges** from an earlier
  run. Moved grants out of the test and re-verified on a clean database, so the
  suite cannot pass against a schema that denies every real client.

**Design decisions:**
- **`updated_at` set by trigger, not client** — a skewed device clock writing a
  past timestamp would be skipped by every other device's incremental pull
  forever.
- **`text` + `CHECK` instead of pg enums** — adding an enum value needs a
  migration and cannot run in a transaction.
- **Members may insert `self_reported` attendance but not `qr_scan`** — the
  policy checks the `source` column, so a staff-verified visit cannot be forged.
- **Role changes guarded by a trigger** — an UPDATE policy cannot compare old and
  new values, so self-promotion to admin needs `guard_profile_role_change`.

**Deferred:**
- `expire_memberships()` exists but is not scheduled (needs `pg_cron` or an
  app-side call).
- Realtime publications for announcements and class cancellation — Phases 9/11.
- `trainer_has_member` infers assignment from plan authorship; `brain.md` §5 has
  no explicit trainer↔member table.

---

## Phase 3 — Authentication & Role Routing ✅ (§8 step 1)

Completed 2026-09-20. 24 new tests (72 total), analyzer clean, APK builds.

- [x] **3.1** Login screen with validation, error display, password visibility
      toggle, and autofill hints
- [x] **3.2** Session persisted by `supabase_flutter`; `restoreSession()` resolves
      the role from the **local profile cache first**, so a returning user opens
      the app signed in and correctly routed with no network
- [x] **3.3** Role cached in `SharedPreferences`, keyed by user id so a second
      account on the same device cannot inherit the first one's role
- [x] **3.4** Three shells over a shared `RoleShell`, with `go_router` redirect
      gating. Unbuilt destinations show an explicit "Built in Phase N" marker
      rather than a fake empty state.
- [x] **3.5** Password reset request, with a neutral confirmation that does not
      reveal whether the email exists
- [x] **3.6** Profile view + edit (name, phone; email read-only — it belongs to
      the auth account, not the profile row)
- [x] **3.7** Logout purges the local database — **owner decision 2026-09-20**

**Logout policy (open question #2, now resolved):** sign-out wipes all local
data, because the app runs on a shared front-desk tablet and member records must
not survive for the next person. Consequences handled:
- `hasUnsyncedChanges()` checks both the queue and dirty rows; the confirmation
  dialog warns explicitly before destroying offline work.
- `signOut()` throws unless `force: true`, so no code path can purge silently.
- `wipeAllData()` deletes children before parents (foreign keys are enforced)
  and re-seeds `sync_state`, so the app is usable immediately after.
- Re-login now requires a network connection. Stated in the dialog.

**Verified, not assumed:**
- Role gating was deliberately disabled and the suite re-run: **exactly the 3
  cross-role tests failed**, confirming they catch a real breach rather than
  passing trivially.
- `hasUnsyncedChanges()` is tested for dirty rows, queued entries, and the
  cleared state after the server accepts rows.

**Notes:**
- Our exception is `SignInException`, not `AuthException` — the latter is
  Supabase's and shadowing it breaks the `on` clauses.
- Routing tests use bounded `pump()` rather than `pumpAndSettle()`: the splash
  and profile screens show indefinite progress indicators that never settle.
- `AuthFailure.invalidCredentials` deliberately does not say which field was
  wrong, so the login screen cannot be used to enumerate members.

---

## Phase 4 — Member Profiles ✅ (§8 step 2)

Completed 2026-09-20. 36 new tests (108 total), analyzer clean, APK builds.

- [x] **4.1** Member list — live search (name/phone/email) and six status filters
      with counts, reading entirely from the local cache
- [x] **4.2** Add form with validation (name required, phone digit count, email
      shape), date-of-birth picker, gender, address, staff notes
- [x] **4.3** Edit + deactivate/reactivate, with a dialog that states history is
      kept and the action is reversible
- [x] **4.4** Detail screen — membership, contact, details, emergency contact,
      staff notes. Attendance/payment history is marked as coming in Phases 6–7
      rather than shown as an empty section.
- [x] **4.5** Member "my profile" already built in Phase 3.6
- [x] **4.6** Emergency contact sheet, stating on screen that it is device-only

**Design decisions:**
- **One join, not N+1.** `watchMembers()` left-joins memberships in a single
  query and reduces to the latest `end_date` per member, matching
  `MembershipDao.currentFor`. A per-row lookup would issue one query per list
  item on every rebuild.
- **Search and filter run in memory**, over the already-cached list, so typing
  does not rebuild the stream on every keystroke. Safe at gym roster size.
- **"All" excludes deactivated members**, which have their own filter — a
  deactivated member must not be mistaken for a current one. Tested as an
  invariant: every active member matches exactly one status filter, so the chip
  counts cannot mislead.
- **Trainers see the same list screen.** RLS is the real scope boundary
  (`brain.md` §2); a separate screen would duplicate the UI without adding
  security.

**Boundary cases tested:** a membership ending *today* reads as expiring rather
than expired; day 6 is inside the 7-day warning window and day 7 is outside;
members with several memberships appear exactly once.

---

## Phase 5 — Membership Plans ✅ (§8 step 3)

Completed 2026-09-20. 30 new tests (138 total), analyzer clean, both builds pass.

- [x] **5.1** Plan CRUD — create, edit, retire/restore, with preset durations
      (1/3/6/12 months) plus a custom-days option
- [x] **5.2** Assign/renew sheet on the member detail screen, with a live preview
      of the resulting expiry date before confirming
- [x] **5.3** Status computation was built in Phase 1; now driven by real plans
- [x] **5.4** `expiringWithin()` + provider ready for the admin dashboard
      (Phase 12 renders it)
- [x] **5.5** Member-facing status chip already shipped in Phase 4
- [x] **5.6** `Money` utility — paise ↔ rupees, Indian lakh/crore grouping

**Renewal keeps paid-for days.** `renew()` continues from the current expiry
rather than starting today, so a member renewing a week early does not lose that
week. Verified by replacing it with the naive "always start today" version:
**3 tests failed**, so they catch the real bug rather than passing trivially.
- Renewing *after* expiry starts today, not from the lapsed date — otherwise a
  member who lapsed for months would receive backdated days.
- A *cancelled* term is never continued from.
- Repeated renewals stack with no gaps or overlaps.

**Design decisions:**
- **Retiring a plan ≠ cancelling memberships.** Retired plans disappear from the
  assign picker but existing memberships keep their expiry dates, and past
  revenue still attributes correctly. The confirm dialog states this with the
  affected count, since staff otherwise assume retiring cancels members.
- **Editing a plan does not rewrite sold memberships.** The form says so
  explicitly — price and duration apply to new memberships only.
- **Money is parsed with rounding, not truncation** (`10.555` → 1056 paise);
  truncating would lose a paisa on every such amount.

**Note:** `RadioListTile.groupValue`/`onChanged` are deprecated in Flutter
3.41.9; migrated to a `RadioGroup` ancestor.

---

## Phase 6 — Attendance: QR ✅ (§8 step 4)

Completed 2026-09-20. 33 new tests (171 total), analyzer clean, both builds pass.

- [x] **6.1** `MemberQrCard` renders on-device from cached data — works offline
- [x] **6.2** `ScannerScreen` using `mobile_scanner`, QR format only,
      `DetectionSpeed.noDuplicates`
- [x] **6.3** Writes locally first, tagged `source: qr_scan`, attributed to the
      scanning staff member via `recorded_by`
- [x] **6.4** Duplicate guard was built in Phase 1; the scanner surfaces it as
      "already checked in at <time>" rather than an error
- [x] **6.5** Six distinct scan outcomes, each with its own colour and icon so
      staff can read the result at a glance across a busy desk
- [x] **6.6** Attendance history grouped by month, with self-reported entries
      marked distinctly from staff-verified scans
- [x] **6.7** Live today-count badge on the scanner, from the local cache
- [x] **6.8** Camera + internet permissions declared in the Android manifest,
      with `android.hardware.camera` marked `required="false"` so a member's
      device without a camera can still install the app

**QR payload is an identifier, not a credential.** `{"v":1,"id":...,"n":...}` —
versioned so the format can change without old cards scanning as garbage. Anyone
who reads the code can reproduce it, exactly like a printed membership number;
it is scanned on a staff-authenticated device and the server still applies RLS,
so a forged card cannot create attendance a real one could not. Signing was
considered and rejected: it needs a shared secret on every member device, a
larger exposure than the thing it protects.

**Scan decisions:**
- **An expired member is still recorded.** They physically visited; discarding
  that leaves the gym with no trace of the entry. Staff see the lapse so they
  can ask about renewal.
- **A deactivated member is refused and not recorded.** Verified as
  load-bearing: removing the guard fails the test.
- **An unsynced member reports "not on this device yet"**, not "bad card" —
  blaming the card sends staff chasing a problem that does not exist.
- **A scan upgrades a same-day self-report** rather than being rejected as a
  duplicate (`brain.md` §6.7).

**16 rejection cases tested** on the payload parser, since a scanner picks up
every barcode in view: plain text, URLs, bare UUIDs, malformed JSON, JSON arrays
and scalars, missing/empty/non-string ids, and a *future* version tag (rejected
rather than misread).

**Web:** `mobile_scanner` compiles for web, and the scanner screen shows an
explicit "needs the app" message behind a `kIsWeb` guard rather than failing.

---

## Phase 7 — Payments ✅ (§8 step 5)

Completed 2026-09-20. 21 new tests (192 total), analyzer clean, both builds pass.

- [x] **7.1** Record form — amount, all four methods, date picker (capped at
      today: this records money already received), notes
- [x] **7.2** Receipt capture via `image_picker`, copied into app storage and
      queued for upload
- [x] **7.3** Per-member payment history with a running total
- [x] **7.4** Paid/pending tracking — pending amounts are struck through so they
      never read as money received
- [x] **7.5** Drafts captured offline; `awaitingReceiptUpload()` feeds Phase 10
- [x] **7.6** Admin payments list grouped by day, with this month's revenue
- [x] **7.7** `voidPayment()` — soft-deletes, so a correction keeps an audit
      trail rather than vanishing from the books

**Receipts are copied into app storage immediately.** The picker hands back a
path in an OS temp directory that can be cleared at any moment — keeping only
that path would lose the receipt before sync ever uploads it.

**Pending ≠ revenue.** Verified as load-bearing: removing the `status = 'paid'`
filter fails 3 tests. Counting pending money would overstate the gym's income.

**Month boundaries tested explicitly** — a payment at 22:00 on the 31st and one
at the first instant of the 1st both fall inside `currentMonthRange()`. An
exclusive end bound would silently drop month-end takings.

**Web:** `dart:io` (file storage and image display) is behind conditional
imports — `receipt_store.dart` and `receipt_image.dart`. Receipt capture is
absent in the browser preview and the form says so; everything else works.

**Note:** the Android build logs a Kotlin incremental-cache `AssertionError`
from `image_picker_android`. It is a Windows file-locking quirk in the Kotlin
daemon, not a code fault — the APK builds successfully, verified twice
including after deleting the cache directory.

---

## Phase 8 — Workout & Diet Plans ✅ (§8 step 6)

Completed 2026-09-20. 38 new tests (230 total), analyzer clean, both builds pass.

- [x] **8.1** Workout template builder — exercises grouped by day, with sets,
      reps, weight note, rest, and per-day ordering
- [x] **8.2** Instructions per exercise. *(Image upload deferred — see below.)*
- [x] **8.3** Diet template builder with meals and items, stored as JSON
- [x] **8.4** Assign sheet for both kinds, from the member detail screen
- [x] **8.5** Member plan viewer, reading entirely from cache; today's weekday
      is highlighted
- [x] **8.6** Exercise completion ticked locally, soft-deleted on un-tick so the
      change syncs instead of reappearing on the next pull
- [x] **8.7** Trainers reach the same builder; RLS scopes what they can act on
      *(see the open gap below)*

**Assignment copies the template.** Verified as load-bearing: replacing the copy
with a reference fails **9 tests**. Without it, a trainer editing a template
would silently rewrite the plan of every member mid-programme. `templateId`
records provenance; deleting a template leaves assigned copies untouched, and
both confirm dialogs say so.

**Positions are per day, not per plan**, so each day restarts at 0 and
reordering within a day cannot disturb another.

**Un-ticking soft-deletes rather than removing the row.** A hard delete would
have no tombstone to sync, so the completion would reappear on the next pull.
Re-ticking revives the same row, which also keeps the unique
`(exercise, member, day)` index intact.

**`MealPlan.decode` tolerates malformed stored JSON** — 6 rejection cases plus
partial recovery (valid meals kept, malformed entries skipped). A plan written
by an older version should not crash a member's plan screen.

**Deferred, flagged rather than silently dropped:**
- **8.2 exercise images.** The `image_url` column and the `exercise-images`
  storage bucket both exist, but upload needs the sync layer (Phase 10) to
  push files to Supabase Storage. Wiring it now would store a local path that
  never reaches other devices.
- **8.7 trainer scoping** still depends on `trainer_has_member`, which infers
  assignment from plan authorship. A trainer who has not yet written a plan for
  a member has no scoped access to them — the open gap from Phase 2.

---

## Phase 9 — Announcements ✅ (§8 step 7)

Completed 2026-09-21. 22 new tests (252 total), analyzer clean, both builds pass.

- [x] **9.1** Compose screen with drafts, urgency flag, publish/save-as-draft
- [x] **9.2** Member feed, cached locally, with per-device unread tracking
- [x] **9.3** Realtime subscription — one of only two sanctioned uses
      (`brain.md` §4)
- [x] **9.4** Local notification on a new announcement, via a platform-guarded
      `Notifications` facade
- [x] **9.5** Feedback DAO + admin inbox groundwork (screens land in Phase 15)
- [x] **9.6** `POST_NOTIFICATIONS` declared in the manifest (Android 13+)

**Realtime is an accelerator, never a dependency.** Every failure in the
subscription is logged and swallowed: the same rows arrive through normal sync
later, so a dropped socket must not break anything. The channel is opened when
the feed screen mounts rather than at startup, keeping the socket closed while
nobody is reading.

**An edit does not re-notify.** The handler checks whether the row is already
known and only fires a notification for genuinely new ones — otherwise fixing a
typo would ping every member again. Notification ids are derived from the
announcement id, so a re-delivery replaces the existing notification instead of
stacking duplicates.

**Read state is per device and never uploaded.** `markRead()` deliberately does
not touch `updated_at` or `is_dirty`; uploading it would mark one member's
announcement read for everyone. Covered by an explicit test.

**Editing a published announcement keeps its original timestamp**, so fixing a
typo does not push an old notice back to the top of every feed.

**Found while testing:** Drift stores `DateTime` as **Unix seconds**, so rows
created in the same second tie on sort and their order is undefined. The feed
ordering test now uses explicit timestamps a day apart. Worth remembering for
every other ordered list in the app.

**Web:** `flutter_local_notifications` has no web implementation at all, so
`Notifications` resolves through a conditional import and is a silent no-op in
the browser preview.

---

## Phase 10 — Background Synchronization ✅ (§8 step 9)

Completed 2026-09-21. 31 new tests (283 total), analyzer clean, both builds pass,
schema parity re-verified against Postgres.

- [x] **10.1** Incremental pull per table, filtering `updated_at > last_synced_at`
- [x] **10.2** `last_synced_at` advanced from the **newest server timestamp**, not
      the device clock — a skewed clock would otherwise skip rows forever
- [x] **10.3** Batched upsert per table (200 rows/request), not row by row
- [x] **10.4** Triggers: login, section (throttled to 5 min), manual
      pull-to-refresh, and connectivity returning
- [x] **10.5** Conflict resolution — a locally dirty row is never overwritten by
      a pull; it wins and is pushed on the next run
- [x] **10.6** Rejections classified, recorded, and surfaced with a "Details"
      sheet; permanent refusals stop being retried
- [x] **10.7** Sync indicator with a pending-change badge, plus a
      `LastSyncedLabel`
- [x] **10.8** Backoff 30s → 2m → 5m → 15m, capped; a manual sync always runs
- [x] **10.9** Receipt uploader — **unblocks the deferred work from Phase 7**

**Local-only columns never cross the boundary.** `is_dirty`, `is_read` and
`receipt_local_path` are stripped going up and ignored coming down. Verified as
load-bearing: emptying the strip list fails **5 tests**. Re-confirmed against a
live Postgres — those three are exactly the columns absent server-side.

**Upload order follows foreign keys.** Profiles before memberships, memberships
before payments, plans before exercises. Uploading a payment before its
membership would be rejected by the FK. Tested as an ordering invariant rather
than a fixed list.

**Date-only columns are parsed as calendar dates**, not timestamps. Treating
`2026-03-10` as an instant applies the device's UTC offset and can move a
check-in to the wrong day — which would defeat the duplicate-attendance guard.

**Push before pull**, so a row this device just created is on the server before
the pull and is not fetched back and compared against itself.

**Found while testing:** the login-trigger sync in `RoleShell` threw when
Supabase was not initialised, taking the whole screen down. That would have
broken a real device with no network, violating the offline-first guarantee. Sync
triggers are now best-effort at every call site, including startup.

**Still deferred:** exercise image upload (Phase 8.2). The receipt uploader gives
it a working pattern, but it needs its own bucket path convention and an
`image_url` write-back; not in this phase's scope.

---

## Phase 11 — Classes & Bookings ✅ (§6.8)

Completed 2026-09-21. 23 new tests (306 total), analyzer clean, both builds pass.

- [x] **11.1** Trainer CRUD — **completed in Phase 15**, not here
- [x] **11.2** Class create/edit with duration presets, capacity and location
- [x] **11.3** Weekly schedule with week navigation, grouped by day
- [x] **11.4** Book / cancel, written locally and queued for sync
- [x] **11.5** Local capacity check — a fast answer, not the decision
- [x] **11.6** Realtime class cancellation — the second and last sanctioned use
      (`brain.md` §4)
- [x] **11.7** Cancellation notification to members who hold a booking
- [x] **11.8** Rejected-booking banner, so a refused offline booking is
      explained rather than silently lost

**The local capacity check is advisory.** Two devices booking the last space
offline both see it free; the server's `for update` trigger (built and
concurrency-tested in Phase 2) serialises them on upload. The loser is marked
`rejected` and shown a banner. The booking snackbar says *"Booked — confirmed
once synced"* rather than promising a place the server may refuse.

**Cancelling a class keeps its bookings.** A member needs to see the class they
booked was cancelled, not find it silently missing from their list.

**A cancellation arriving from the server is applied clean, not dirty.**
`applyRemoteCancellation()` leaves `is_dirty` false — the server already knows,
and marking it dirty would push its own decision straight back. Same for a
rejected booking. Both are covered by tests contrasting them with the local
paths, which *do* mark dirty.

**Re-booking revives the cancelled row** rather than inserting, so the unique
`(class, member)` index holds on both sides.

**Realtime notifies only members who hold a booking** — everyone else picks the
change up silently on their next sync, rather than being pinged about a class
they were never attending.

**11.1 trainer management was deferred from this phase and built in Phase 15.**
At the time classes took a `trainer_id` that nothing populated; trainers are now
creatable, editable and assignable.

---

## Phase 12 — Admin Dashboard & Reports ✅ (§8 step 10)

Completed 2026-09-21. 27 new tests (333 total), analyzer fully clean, both
builds pass.

- [x] **12.1** Home dashboard — today's attendance, active members, month
      revenue, upcoming classes, pending payments
- [x] **12.2** 14-day attendance trend, verified and self-reported kept apart
- [x] **12.3** 6-month revenue report
- [x] **12.4** "Needs attention" card listing expiring and expired members,
      each tappable straight through to their profile
- [x] **12.5** CSV export of members, payments and attendance
- [x] **12.6** Every figure from the local cache — the dashboard opens offline
- [x] **12.7** Pull-to-refresh triggers a manual sync

**Membership status is derived from dates, not the stored column.** The server's
`expire_memberships()` is not scheduled yet (flagged in Phase 2), so a lapsed
membership may still read `active` in the database. The dashboard must not
repeat that.

**Self-reported check-ins are shown beside the headline figure, never folded
in.** Owner question #1 is still open; merging them would silently decide it.

**CSV is written for Excel, not for re-import:**
- Amounts as decimal rupees, not paise. Verified as load-bearing — writing the
  raw integer fails the test, and would be a **100× error** in an accounting
  export.
- A UTF-8 BOM, or member names with non-ASCII characters render as mojibake.
- Methods and sources spelled out ("Bank Transfer", "Staff scan") rather than
  wire values.
- Deactivated members are included and flagged, not dropped — the owner is
  exporting their own records.
- Comma-containing names are quoted, tested explicitly: an unquoted comma
  shifts every later column in the row.

**Cleared the accumulated lint backlog** — 8 `unnecessary_underscores` in the
router and a missing `sqlite3` dev dependency. `flutter analyze` is now
completely clean, not just error-free.

**Web:** CSV export needs `dart:io` to stage the file, so it is behind a
conditional import and the reports screen says export needs the Android app.

---

## Phase 13 — Notifications ✅ (§6.9)

Completed 2026-09-21. 24 new tests (357 total), analyzer clean, both builds pass.

- [x] **13.1** Plugin init, three Android channels, permission request
      (Android-only: `brain.md` §3 targets Android, and the plugin has no web
      implementation)
- [x] **13.2** Membership expiry — 7 days out, then the day before
- [x] **13.3** Payment due — a week after a payment is recorded as pending
- [x] **13.4** Class reminders — 2 hours before a booked class starts
- [x] **13.5** `NotificationPayload` (`type:id`) and tap navigation —
      **completed 2026-09-22**, see below
- [x] **13.6** `NotificationKind` id ranges, one per category
- [x] **13.7** Timezone-aware scheduling; `scheduleDaily` ready for Phase 14

**Phase 9 built immediate notifications only.** Reminders need *scheduled*
ones, which is timezone-aware work: a 10:00 reminder must fire at 10:00 local,
including across a DST change. `tz_data.initializeTimeZones()` now runs at init.

**Each category owns a disjoint id range.** Android identifies a notification by
a single int, so without this a membership reminder could silently replace a
class reminder. Verified as load-bearing: collapsing every kind onto one base
fails 2 tests.

**Reminders are rebuilt wholesale, not diffed.** A renewed membership or a
cancelled class must not leave a stale reminder queued, and rebuilding is far
easier to get right than reconciling. Rescheduling runs after each sync, since
that is when the underlying data may have changed elsewhere.

**Sign-out cancels every reminder**, alongside the existing data purge — a
notification about a membership this device no longer holds would be confusing.

**`inexactAllowWhileIdle` scheduling**, so no exact-alarm permission is needed.
A reminder a few minutes late is fine; being refused the permission is not.

**Correction to an assumption I made while testing:** `Notifications.isSupported`
is **true** in the test VM, because the VM has `dart:io` and the conditional
import resolves to the Android implementation. The scheduler therefore runs for
real in tests; the plugin calls fail with no platform behind them and are
swallowed — which is the guarantee the tests actually check.

**13.5 tap navigation — completed 2026-09-22.** 15 further tests (426 total).

Three awkward moments a tap can arrive in, all handled by holding rather than
dropping the payload:
- **Cold start** — the app was *launched by* the notification, so the tap
  callback never fires and no screen exists yet.
  `Notifications.launchPayload()` reads it back explicitly.
- **While signed out** — the session is still restoring, so navigating would be
  discarded by the router's redirect.
- **While running** — consumed immediately.

Verified as load-bearing: dropping the payload instead of holding it fails 3
tests. Without it, tapping "membership expiring" from a closed app would just
open the home screen — the feature would look implemented and do nothing.

**Consuming clears the payload**, so it is acted on once rather than
re-navigating on every rebuild. A second tap before the first is consumed
replaces it: the most recent is what the user meant.

**Sign-out clears anything pending**, alongside the reminder cancellation and
data purge — the payload points at records this device is about to delete.

**Tab mapping is data, not navigation** (`tabFor`), so it is testable without a
widget tree. Membership, payment and check-in open Home; classes open Classes;
announcements open News. A stray payload on a staff device is ignored rather
than jumping to an index that shell does not have.

---

## Phase 14 — Daily Self-Check-in ✅ (§6.7, §8 step 11)

Completed 2026-09-21. 20 new tests (377 total), analyzer clean, both builds pass.

- [x] **14.1** Daily "Did you go to the gym today?" local notification
- [x] **14.2** Member-configurable time, **opt-in and off by default** — the app
      must not start notifying someone who never asked
- [x] **14.3** Lightweight start/finish time sheet, defaulting to the last hour
- [x] **14.4** Saved to the same `attendance` table tagged `self_reported`
- [x] **14.5** Rides the existing batched sync — no new infrastructure
- [x] **14.6** Shown distinctly in the member's history and on the home card
- [x] **14.7** **UNBLOCKED — owner decision 2026-09-21:** self-reports stay
      member-facing and do not count toward official attendance

**Open question #1 is resolved.** Self-reported attendance stays member-facing
only; staff-verified QR scans remain the official record. This confirms what
Phases 6 and 12 already built, so no rework was needed. `brain.md` §6.7 and its
change log are updated.

**The separation is enforced by tests, not just convention.** Flipping
`countForDay`'s default to include self-reports fails tests in *both* the
check-in and dashboard suites — so the decision cannot be reversed by accident.

**A member can never downgrade a verified record.** A self-report is refused
when a staff scan already exists for the day; the reverse — a scan arriving
after a self-report — still upgrades it. Both directions tested.

**The reminder is re-armed on each sign-in.** Scheduled notifications do not
survive a reinstall or an OS "clear data", so the saved preference is reapplied
rather than assumed still active.

**Found while testing:** the new re-arm call read `sharedPreferencesProvider`,
which throws outside a fully configured app and took down the whole shell in
widget tests. Same class of bug as the Phase 10 sync trigger — now guarded the
same way. On a real device this would have been a crash on a screen that is
supposed to work offline.

## Phase 15 — Member Feedback & Trainers ✅ (§6.2)

Completed 2026-09-21. 15 new tests (392 total), analyzer clean, both builds pass.

- [x] **15.1** Member feedback form with optional subject
- [x] **15.2** Written locally and queued — a member can raise something on the
      gym floor with no signal
- [x] **15.3** Admin inbox with open/all filter and inline reply
- [x] **15.4** Member-facing trainer list
- [x] **15.5** **Closes the Phase 11 gap:** trainer CRUD — add, edit,
      retire/reinstate, and trainers are now assignable to classes

**Trainer management was the outstanding gap from Phase 11.** `brain.md` §6.3
lists "manage trainers" and the table existed, but no query or screen did —
classes took a `trainer_id` that nothing populated. Now built.

**Creating a trainer writes the profile and trainer row in one transaction.**
Either alone is useless: a trainer row without its profile is invisible
everywhere, a profile without the trainer row has no specialisation or bio.
Verified as load-bearing — skipping the trainer row fails 7 tests.

**Retiring a trainer is reversible and preserves history.** Past classes keep
their trainer, and the dialog says so, because staff would otherwise avoid a
safe action fearing it erases records.

**Trainer phone numbers are admin-only.** A member should reach a trainer
through the gym, not their personal number. The form labels the field
"Staff only — not shown to members".

**The add-trainer form states plainly that it does not create a login.** A
trainer record is for scheduling; sign-in access needs a Supabase Auth user set
up separately. Without that line, an owner would reasonably assume the trainer
can now sign in.

**Replying resolves the message.** An answered question is handled; the member
raises a new one if they need more. The member sees the reply inline under
their original message.

**Note:** the admin dashboard comment about open question #1 was stale after
yesterday's decision — updated to record the resolution rather than the
pending question.

## Phase 16 — Hardening & Release ✅

Completed 2026-09-22. 19 new tests (411 total), analyzer clean, release APK and
app bundle both build.

- [x] **16.1** Offline pass over every feature in `brain.md` §7 —
      `test/unit/offline_capability_test.dart`, 19 tests with **no Supabase
      client constructed at all**
- [x] **16.2** RLS re-verified after the bootstrap migration: 28 assertions
      still pass, schema parity still holds
- [x] **16.3** Long-offline scenario — a full day of scans, payments, plan
      assignment and bookings with no sync, nothing lost
- [x] **16.4** Empty, error and loading states were built per screen throughout
- [x] **16.5** Release signing via `android/key.properties` (gitignored);
      falls back to debug signing without it, which Play rejects — deliberate
- [x] **16.6** Release builds: APK 80.5 MB, **app bundle 59.6 MB** (from
      205 MB debug), R8 minification and resource shrinking enabled with keep
      rules for Drift, notifications and `mobile_scanner`
- [x] **16.7** First-run bootstrap — `20260921000007_bootstrap.sql`

**A real bug, caught before shipping.** The `guard_profile_role_change` trigger
from Phase 2 blocked `claim_first_admin()`: at that moment no admin exists, so
`is_admin()` is false and the promotion was refused. **A fresh gym could never
create its first admin.** Fixed with a transaction-local flag the guard honours,
and covered by `supabase/tests/bootstrap_test.sql` — whose last assertion
confirms an ordinary member still cannot self-promote, so the relaxation is not
a hole.

**A second bug, caught by the clock rolling over mid-run.** Three check-in tests
failed at 00:01 because they logged a session "an hour ago", which lands on the
previous day. The *code* was right — a session starting before midnight does
belong to yesterday — but it exposed a real UX trap: a member logging at 00:30
would silently file under the wrong day. The sheet now defaults both times to
*now* rather than an hour back.

**Not done — what still needs a live Supabase project:**
- Nothing in this project has run against real Supabase. The migrations, RLS and
  sync engine are verified against a local PostgreSQL 18.6 with the Supabase
  objects stubbed, but the actual round trip is unproven.
- Realtime (announcements, class cancellation) cannot be exercised without a
  server.
- `expire_memberships()` is still unscheduled — needs `pg_cron` or an app-side
  call.
- App icon and store listing assets (16.5) are still Flutter defaults.

## Added after the phase plan

### Member self-registration ✅ (2026-09-22)

5 new tests (431 total), analyzer clean, both builds pass.

**The app had no registration at all.** Three unauthenticated routes existed —
splash, login, forgot-password — and nothing called `signUp()`. An account could
only be created by hand in the Supabase dashboard.

- [x] Sign-up screen: name, email, password, with a link from the login screen
- [x] `AuthRepository.signUp()` passing `full_name` as user metadata, which the
      `handle_new_user` trigger reads
- [x] `/sign-up` added as a third unauthenticated route — verified as
      load-bearing: omitting it from the auth-route check bounces a signed-out
      user straight back to login, so registration is unreachable
- [x] Three new `AuthFailure` cases with their own classifier, because
      "already registered" is a normal sign-up outcome rather than a
      credential error
- [x] `confirmationRequired` gets its own screen state, not an error box: the
      account *was* created and the user has one step left

**Known gap, flagged not fixed:** a staff-created member profile (Phase 4) and a
self-registered account are separate records. Staff adding "Priya Sharma" does
not let Priya sign in, and Priya registering does not link her to the profile
staff made. Matching them by email needs a decision about what wins on
conflict — worth doing before real data exists.

---

## Open Questions

| # | Question | Source | Status |
|---|----------|--------|--------|
| 1 | ~~Do self-reported check-ins count toward official attendance stats?~~ | `brain.md` §6.7 | ✅ **No — member-facing only** (2026-09-21) |
| 2 | ~~On logout, is local cached data purged or retained?~~ | Phase 3.7 | ✅ **Purge all** (2026-09-20) |
| 3 | Do trainers record attendance, or is QR scanning admin-only? | `brain.md` §2 | Needs decision |
| 4 | Is UPI a distinct payment method or grouped under "external"? `pitch.md` lists it separately, `brain.md` §6.5 does not | `pitch.md` | Needs decision |
| 5 | Should a self-registered account link to a staff-created member profile with the same email? | 2026-09-22 | Needs decision |

---

## Dependency Notes

- **Phase 1 gates everything.** No feature work starts until the Drift schema and DAOs exist.
- **Phase 2 should run alongside Phase 1** so local and server schemas stay identical.
- **Phase 10 (sync) can be stubbed** during Phases 3–9 — write to local, defer the upload —
  but must be finished before any real-device testing with multiple users.
- **Phase 6 gates Phase 14.**
- **Phase 13.1 gates Phase 14.1.**
