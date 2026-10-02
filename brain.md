# The Iron Yard — Brain.md

This is the living source of truth for the app's structure, features, and decisions.
Update this file whenever the gym owner requests a change or a new feature — do not rebuild
from scratch, patch this document so the history of decisions stays intact.

Last updated: 2026-09-22

---

## 1. App Identity

- **Name:** The Iron Yard
- **Type:** Single Flutter app, two roles (Admin/Trainer view + Member view), role selected
  after login
- **Core principle:** Offline-first. Supabase is used for auth, storage, and sync — not as a
  live dependency for every screen. The app must be fully usable (for cached data) with no
  internet connection.

---

## 2. Roles & Permissions

| Role    | Access |
|---------|--------|
| Admin   | Full access — members, plans, payments, trainers, classes, announcements, reports, export |
| Trainer | Assigned members, workout/diet plan creation & assignment, attendance view, class schedule |
| Member  | Own profile, membership status, QR card, plans, attendance history, payments, classes, feedback |

Enforced via Supabase Row Level Security (RLS) at the database level, mirrored by
role-gated UI/navigation in Flutter.

---

## 3. Tech Stack

- **Frontend:** Flutter (single codebase, role-based navigation)
- **Backend:** Supabase (Postgres, Auth, Storage, Realtime — used sparingly)
- **Local DB:** Drift (SQLite) — chosen over Isar for relational integrity between members,
  payments, attendance, bookings, and plans
- **Local notifications:** flutter_local_notifications (daily reminders, expiry alerts,
  class reminders — no push service required for v1)
- **QR:** on-device QR generation (member card) + on-device QR scanning (staff attendance)

---

## 4. Data Sync Strategy

- **Incremental sync:** every table has `id`, `created_at`, `updated_at`, `is_deleted`.
  Sync pulls `where updated_at > last_sync_time`.
- **Sync triggers:** after login, on opening a major section, manual pull-to-refresh, and
  automatically when Wi-Fi is available. Never on every navigation.
- **Batched uploads:** local pending changes (attendance, bookings, draft payments) are
  queued locally and uploaded in a single batch request, not one row at a time.
- **Realtime usage (limited to):**
  - New announcement / urgent admin message
  - Class cancellation
  - Everything else is pull-based sync, not realtime, to keep costs and complexity down.

---

## 5. Supabase Tables

```
profiles
memberships
membership_plans
attendance
invoices
payments
trainers
workout_plans
workout_exercises
diet_plans
diet_meals
diet_food_items
classes
class_bookings
announcements
equipment_items
equipment_service_logs
```

`sync_queue` is optional / can stay fully local on-device instead of a server table.

---

## 6. Feature Map

### 6.1 Authentication & Roles
- Email/password login via Supabase Auth
- **Member self-registration** (added 2026-09-22): a member creates their own
  account from the login screen. The server trigger gives them `role = 'member'`;
  sign-up never grants staff access. Their membership plan is still assigned at
  the desk by staff.
- Role-based routing after login (admin / trainer / member)
- Profile editing
- Password reset
- RLS-enforced data access

### 6.2 Member Features
- Membership status + expiry date
- Digital QR membership card (offline-renderable)
- Assigned workout plans (cached, viewable offline) — including a bodyweight-
  relative load shown as an actual kg figure, where the trainer set one (6.11)
- Assigned diet plans (cached, viewable offline) — including BMI and a
  suggested daily calorie target, where height/weight are on record (6.11)
- Attendance history
- Payment history
- **Outstanding balance** — what they currently owe, if anything (see 6.5)
- Gym announcements (cached)
- Book / cancel available classes
- View trainer details
- Submit feedback / support requests
- Emergency contact details (stored locally on device)
- **Daily "Did you go to the gym?" self-check-in** (see 6.7)

### 6.3 Management / Admin Features
- Add / edit / deactivate members
- Search & filter members
- View member profiles
- Record attendance (QR scan)
- Manage membership plans
- Track membership expiry
- Record payments against an invoice, in full or in installments
- Create ad-hoc charges (registration fees, PT add-ons, manual late fees)
- Apply a discount (flat or percent) to an invoice
- View outstanding balances / dues report, per member and system-wide
- Manage equipment inventory and log service events (see 6.10)
- Record a member's height/weight (see 6.11)
- Assign workout & diet plan templates, with structured, editable content and
  bodyweight-relative loads/calorie targets (see 6.11)
- Manage trainers
- Create classes & schedules
- Publish announcements
- Basic reports (attendance, revenue, active/expiring members)
- Export member & payment data (CSV)

### 6.4 Attendance System (local-first)
- Staff scans member's QR membership card
- Record saved locally first, synced to Supabase when online
- Duplicate attendance prevented for same day (checked locally + enforced server-side)
- Today's attendance count shown on admin home, computed from local cache

### 6.5 Payments & Invoicing (v1 — manual, no gateway)
- **No online payment gateway in v1** — avoids transaction fees, webhook infra, PCI-adjacent
  complexity. Revisit only if the owner explicitly wants online collection later. Everything
  below is a manual record of money that changed hands elsewhere.
- **Invoicing model** (added 2026-09-26): payments settle *invoices*, not each other.
  - Assigning or renewing a membership plan **automatically creates an invoice** for the
    plan price (`MembershipRepository.assignPlan`/`renew`, wrapping `MembershipDao` +
    `InvoiceDao` in one local transaction so a membership never exists without its
    charge). Membership assignment on its own no longer implies "this is free."
  - Staff can also create an **ad-hoc charge** — a registration fee, a PT add-on, or a
    manual late fee. There is no separate late-fee mechanism; a late fee is just an
    ad-hoc charge staff decide to add. No automatic penalty engine.
  - An invoice supports a **flat-amount or percent discount**, resolved into paise at
    apply time. Cannot be changed once the invoice is `paid` or `void`.
  - **Partial payments / installments**: an invoice tracks `totalMinor` vs.
    `amountPaidMinor`; any number of payments can apply against it until it reaches
    `paid`. A payment cannot exceed the remaining balance (pending payments are
    exempt, since they are not yet counted).
  - **Outstanding balance / dues**: `InvoiceDao.balanceFor`/`totalOutstanding` and the
    dues screen (admin → Payments → outstanding-balances icon) surface what's owed,
    per member and system-wide. A member sees their own balance on their profile.
  - `amountPaidMinor`/`status` are **denormalized on the invoice**, not derived live by
    summing payments, and are kept correct by `InvoiceDao.applyPayment`/
    `voidLinkedPayment` updating both rows in one local transaction. This is a deliberate
    tradeoff against the sync engine's row-level (not cross-table-transactional) model:
    the dues list is read often and a stored total avoids a join/sum on every render.
    **Accepted limitation:** two devices applying partial payments to the *same* invoice
    while both offline can leave the stored total wrong after sync (last-write-wins on
    the invoice row, while the underlying payment rows are never lost). `InvoiceDao
    .recomputeFromPayments` re-derives the correct total from the surviving payments and
    is the repair path if this is ever suspected — there is no automatic post-sync
    reconciliation pass yet.
  - `Payments.membershipId` is kept alongside the new `Payments.invoiceId` (not replaced)
    so pre-invoicing rows stay meaningful without a join.
- Manual recording: cash / bank transfer / UPI / external
- Receipt/photo + notes stored (Supabase Storage)
- Payment status + history
- Renewal reminder notifications
- **Historical data**: existing `payments`/`memberships` rows recorded before invoicing
  existed have **no local backfill** — the client migration only adds the `invoices`
  table and `payments.invoice_id` column. A **server-side Supabase migration**
  (`20260926000011_invoices_backfill.sql`) is the sole source of truth for
  reconstructing history: one `kind = 'backfill'` invoice per pre-existing membership
  (priced at the plan's price, status derived from any payments already linked to it),
  plus one per ad-hoc historical payment with no membership. Idempotent
  (`where not exists`), and deliberately not duplicated client-side — running the same
  transformation on both sides would risk each device synthesizing invoices with
  different ids for the same history.

### 6.6 Workout & Diet Plans
- Admin/trainer builds reusable templates
- Templates assigned to individual members (copy-on-assign, not a reference —
  editing a template never rewrites a plan a member is already following)
- Cached fully on-device for offline viewing
- Exercise completion tracked locally, synced later
- Exercise instructions + optional images
- **Bodyweight-relative loads** (added 2026-09-26): a workout exercise may
  carry an optional "% of bodyweight" figure, additive to the existing
  free-text weight/intensity note, never a replacement. On an assigned plan
  it renders as an actual kg figure using the member's *live current* weight
  (see 6.11 for why this differs from the BMI/calorie snapshot behaviour). On
  a template (no assigned member) it shows only the raw percentage.
- **Diet plans are structured** (added 2026-09-26): a plan holds ordered
  meals, each with ordered food items (name, quantity, optional calories/
  protein/carbs/fat) — mirroring how a workout plan holds ordered exercises.
  Replaces the earlier single `mealsJson` text blob for every plan created
  going forward; see 6.11 for what happens to plans that predate this.
- **BMI and a suggested daily calorie target** are computed for an assigned
  diet plan from the member's height/weight and a staff-picked activity
  level — see 6.11 for the full model.

### 6.7 Daily Gym Check-in (self-reported attendance) — NEW
- Once per day, local notification asks: "Did you go to the gym today?"
- Tapping "Yes" opens a lightweight form: start time, end time
- Confirming saves a local attendance record (same attendance table as QR scans, tagged
  `source: self_reported` vs `source: qr_scan`)
- Syncs to Supabase in the same batched attendance sync — no extra infra cost
- **Relationship to QR attendance:** treated as a fallback/secondary source, not a
  replacement. QR-scanned attendance (staff-verified) is the primary/trusted record for
  admin reporting; self-reported check-ins are visible to the member and optionally
  flagged separately in admin reports as "unverified."
- Zero additional backend cost — runs entirely on `flutter_local_notifications` + existing
  Drift/Supabase sync pipeline.
- **RESOLVED 2026-09-21 (owner decision):** self-reported attendance stays
  **member-facing only** and does NOT count toward official attendance stats. Admin
  figures and reports count staff-verified QR scans; self-reports appear beside them,
  labelled separately ("+N self-reported"), and in the member's own history. This is
  what the app already did, so the behaviour is confirmed rather than changed.
- Reminder is **opt-in** and off by default, with a member-configurable time
  (default 20:00). Scheduled locally; re-armed on each sign-in, because scheduled
  notifications do not survive a reinstall or an OS clear.

### 6.8 Classes & Bookings
- Weekly class schedule display
- Book / cancel classes (offline-queued, synced when online)
- Class capacity enforced locally and server-side (prevents double-booking / overbooking
  on reconnect)

### 6.9 Notifications & Announcements
- In-app announcements, cached locally
- Membership expiry reminders
- Payment due reminders
- Class reminders
- Daily gym check-in reminder (6.7)
- All via local notifications in v1 — no FCM/APNs push infrastructure required

### 6.10 Equipment Tracking (added 2026-09-26)
- **Inventory**: name, category, quantity, location, purchase date, cost. Admin
  creates/edits/retires (soft-delete — retiring keeps service history intact, matching
  how retiring a membership plan works in §6.3).
- **Maintenance/service tracking**: each item optionally carries a service interval
  (in days). A service event is logged with a description, date, optional cost, and who
  performed it; the item's `last_serviced_at` updates from the latest log entry.
  "Due for service" is derived (never serviced, or serviced longer ago than the
  interval) — it is a separate signal from `status`, not folded into it: a machine can
  be `working` and still be overdue for its scheduled service.
- **Access**: admins manage equipment; trainers can view the inventory and service
  history but cannot create/edit/retire or log a service; members have no equipment UI
  or API access at all (RLS-enforced, `is_staff()`/`is_admin()` — see
  `20260926000014_equipment_rls.sql`).
- **Not in this pass**: assignment of equipment to specific classes/trainers, warranty
  expiry tracking/reminders, and an automatic penalty/alert engine beyond the plain
  "due for service" list. Revisit if the owner asks for these.

### 6.11 Body Metrics & Calculated Plan Targets (added 2026-09-26)
- **Height/weight live on the member profile** (`Profiles.heightCm`/`weightKg`,
  metric — see below), editable by staff/trainer via the member form. Not exposed as
  a member self-report field in the UI, though RLS does not enforce that column-level
  (no column-level RLS exists anywhere in this schema — a member with direct API
  access could in principle edit their own height/weight, exactly as they already can
  edit their own name/phone; accepted as a pre-existing pattern, not a new hole).
- **Snapshotted at assignment time**: assigning a workout or diet plan to a member
  copies their current `heightCm`/`weightKg` onto the new plan row
  (`snapshotHeightCm`/`snapshotWeightKg`). A later edit to the member's profile never
  changes the numbers already shown on a plan they are following — the whole point of
  the snapshot. A template (never assigned) has no snapshot.
- **Units**: plain metric, centimeters and kilograms, no imperial toggle. The app's
  locale is already `en_IN` throughout (see `core/utils/money.dart`), and there was no
  existing unit-conversion utility to build a dual-unit display on top of. If imperial
  display is ever wanted, add a `BodyMetricsFormat` alongside `Money`'s
  format/parse/toInput pattern — storage stays metric regardless, exactly as `Money`
  keeps storage in paise regardless of the currency symbol shown.
- **BMI** is computed (`BodyMetrics.bmi`, `lib/core/utils/body_metrics.dart`) and shown
  wherever a plan's snapshot height/weight are both present, with the standard WHO
  category label (Underweight/Normal/Overweight/Obese).
- **Daily calorie target** (diet plans only): Mifflin-St Jeor BMR from the plan's
  snapshot weight/height, the member's age (derived from `dateOfBirth`), and gender,
  multiplied by a staff-picked activity level (`DietPlans.activityLevel`: sedentary
  ×1.2, light ×1.375, moderate ×1.55, active ×1.725), rounded to the nearest 10 kcal.
  **Gender mapping**: `'Male'` uses the male formula term (+5), `'Female'` uses the
  female term (−161); anything else (`'Other'`, unset) **averages the two constants**
  rather than forcing a blocking choice — the sex term only captures a
  population-average lean-mass difference, and the result is shown as an estimate
  regardless of which branch computed it.
- **Bodyweight-relative exercise loads** (workout plans): `WorkoutExercises
  .bodyweightPercent` is optional and additive to the existing free-text `weightNote`
  — never a replacement. Unlike BMI/calorie targets, its displayed kg figure uses the
  member's **live current weight**, not the plan's snapshot: this field exists
  specifically to stay correct as the member's weight changes over a programme, so
  freezing it to assignment-time weight would make it *wrong* by design, the opposite
  failure mode the snapshot exists to prevent for BMI/calories. Falls back to the
  snapshot only if the member has no live weight on record. A template (no assigned
  member to compute against) shows only the raw percentage.
- **Diet plans are structured, not migrated**: `DietMeals`/`DietFoodItems` replace the
  earlier `DietPlans.mealsJson` blob for every plan created going forward. Existing
  plans are **not** automatically migrated — their free-text meal lines have no
  quantity/calorie/macro fields to migrate into, and an automated parse would only
  produce a bare food-item name with everything else null, which is barely better than
  leaving them as-is. `mealsJson` is kept (nullable, unused by new plans) purely as a
  read-only legacy fallback: a plan with no structured meals still decodes and shows
  its `mealsJson`, labelled "from before structured meals." Staff can re-enter an old
  plan in the new structured editor if they want it upgraded — diet templates are a
  small, staff-curated set, unlike thousands of historical records, so manual
  re-entry is a reasonable cost here.
- **Files**: `lib/core/utils/body_metrics.dart` (pure functions, no DB/Flutter
  dependency — BMI, BMR, calorie target, age-from-DOB, bodyweight-relative load);
  `lib/data/local/daos/plan_dao.dart` (snapshot capture in `assignWorkoutPlan`/
  `assignDietPlan`, meal/food-item CRUD); `lib/features/plans/screens/
  diet_plan_editor_screen.dart` (rewritten to a structured meal/food-item builder,
  mirroring the workout exercise editor); `supabase/migrations/20260927000015-017`.

---

## 7. Offline-Capable Feature List

Works fully offline (cached/local):
login session, member profile, QR card, workout plans, diet plans, attendance scanning,
attendance history, downloaded payment history, downloaded class schedule, announcement
history, exercise progress, draft payments/attendance records, daily check-in capture.

---

## 8. Build Order (v1 Roadmap)

1. Login + role management
2. Member profiles
3. Membership plans
4. Attendance (QR scan + local-first sync)
5. Payment records (manual)
6. Workout & diet plans
7. Announcements
8. Offline local database (Drift) foundation — should actually be built early/in parallel,
   not after, since everything above depends on it
9. Background synchronization
10. Basic admin dashboard
11. Daily self-check-in attendance (6.7) — additive, low cost, can slot in anytime after
    attendance (step 4) is stable

---

## 9. Change Log

- 2026-09-18 — Initial brain.md created from full feature spec.
- 2026-09-18 — Added daily self-reported gym check-in feature (6.7): local notification,
  time-range entry, saved as secondary attendance source. Confirmed no additional cost —
  uses existing local-notification + Drift/Supabase sync infrastructure.
- 2026-09-20 — Owner decision: signing out **purges all local data** on that device.
  The app runs on a shared front-desk tablet, so member records must not survive a
  sign-out. Consequence: re-login needs a connection, and the app warns before
  discarding unsynced work.
- 2026-09-20 — Web added as a **development preview only** (`flutter run -d chrome`),
  so the app can be checked without installing an APK. Android remains the shipping
  target: local notifications do not work on web at all, so §6.7 and §6.9 reminders
  are Android-only.
- 2026-09-21 — Owner decision on the §6.7 open question: self-reported attendance
  stays **member-facing only**. Staff-verified QR scans remain the official record.
  Self-reports are shown separately, never folded into admin figures.
- 2026-09-22 — Added member self-registration (§6.1). Until now there was no way
  to get an account from inside the app: staff could add a member *profile*, but
  that creates no login, so the person could not sign in. Members now register
  themselves; staff link them to a plan afterwards. **Known gap:** a
  staff-created member profile and a self-registered account are still separate
  records — matching them by email is not implemented.
- 2026-09-22 — v1 feature build complete (all 16 phases). Added a first-run
  bootstrap: the first signed-up user can claim admin once, after which the path
  closes. Release signing and R8 minification configured. **Not yet run against a
  live Supabase project** — schema, RLS and sync are verified locally only.
- 2026-09-26 — Added a full invoicing/dues system on top of the existing manual
  payment recording (§6.5), still with no payment gateway. Owner decisions: (1)
  assigning/renewing a plan auto-creates an invoice; (2) invoices support partial
  payments/installments; (3) discounts are per-invoice, flat or percent; (4) late
  fees are manual (an ad-hoc charge, no penalty engine); (5) historical
  payments/memberships are backfilled with invoices **server-side only** (one SQL
  migration, idempotent), not duplicated by a client-side migration, to avoid two
  devices synthesizing divergent backfill rows for the same history. New
  `Invoices` Drift table + Supabase table, `InvoiceDao`, `MembershipRepository`
  (the new home for "assigning a plan also charges for it" — `MembershipDao`
  itself stays single-table), `InvoiceRepository`, a dues screen, and an ad-hoc
  charge form. `amountPaidMinor`/`status` are denormalized on the invoice for
  read performance, with a known limitation around concurrent offline partial
  payments to the same invoice — see §6.5 for the full tradeoff and the repair
  path (`recomputeFromPayments`).
- 2026-09-26 — Added equipment tracking (§6.10): inventory plus maintenance/service
  logging, the other gap from the September audit alongside invoicing. Owner decisions:
  (1) scope is inventory + maintenance tracking only, not equipment-to-class/trainer
  assignment or warranty tracking; (2) admins manage equipment, trainers can view it
  read-only, members have no access at all. New `EquipmentItems`/`EquipmentServiceLogs`
  Drift + Supabase tables (the Drift table is named `EquipmentItems`, not `Equipment`,
  purely so the generated row class doesn't collide with the table class name),
  `EquipmentDao`, list/form/detail/log-service screens, and an "Equipment" destination
  in both the admin and trainer shells. "Due for service" is derived from
  `last_serviced_at` + `service_interval_days`, kept deliberately separate from the
  staff-set `status` field.
- 2026-09-26 — Made workout/diet templates customizable around a member's body
  (§6.6, new §6.11): height/weight on the profile, snapshotted onto each plan at
  assignment so a later profile edit never rewrites numbers already shown; BMI always
  computed; a Mifflin-St Jeor daily calorie target for diet plans from a staff-picked
  activity level (non-binary/unset gender averages the male/female formula constants
  rather than forcing a choice); workout exercises gain an optional bodyweight-%
  load, additive to the existing free-text weight note, displayed against the
  member's *live* weight rather than the snapshot (an intentional asymmetry — see
  §6.11 for why); diet plans move from a single `mealsJson` blob to structured
  `DietMeals`/`DietFoodItems` tables, with existing plans deliberately not migrated
  (kept as a read-only legacy fallback instead — see §6.11 for the full rationale).
  Schema version 3 → 4; three new Supabase migrations continuing the sequence after
  equipment tracking.

**How to use this log:** every time the owner requests a change, append a dated entry here
summarizing what changed and why, then update the relevant section above. Keep entries
even if a feature is later removed, so the reasoning trail isn't lost.
