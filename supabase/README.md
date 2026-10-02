# Supabase — The Iron Yard

Schema, RLS policies and constraints. **Nothing here has been applied to a live
project yet** — these are migration files awaiting a project to push to.

## Migrations

| File | Contents |
|------|----------|
| `20260920000001_schema.sql` | 14 tables mirroring the Drift schema |
| `20260920000002_indexes_triggers.sql` | Sync/query indexes, `updated_at` trigger |
| `20260920000003_capacity.sql` | Class capacity enforcement, membership expiry |
| `20260920000004_rls.sql` | Row Level Security for all three roles |
| `20260920000005_storage.sql` | Receipt, exercise-image and profile-photo buckets |
| `20260920000006_grants.sql` | Table privileges for `authenticated` |

## Applying them

```sh
supabase link --project-ref <your-project-ref>
supabase db push
```

Then put the project URL and publishable key in `env.json` (see
`env.example.json`) so the Flutter app can reach it.

## What is deliberately not here

The local database carries five things that never reach the server:

- **`is_dirty`** — upload bookkeeping, meaningless to other devices
- **`announcements.is_read`** — read state is per device
- **`payments.receipt_local_path`** — an on-device file path
- **`emergency_contacts`** — device-only by design (`brain.md` §6.2), kept in
  its own table so a future profile sync cannot sweep it up
- **`sync_queue` / `sync_state`** — device-only (`brain.md` §5)

`supabase/tests/check_schema_parity.py` enforces exactly this split and fails if
any other column diverges.

## Design decisions

**`updated_at` is set by a trigger, not the client.** Incremental sync pulls
`where updated_at > last_sync_time`. A device with a skewed clock that wrote its
own timestamp in the past would be skipped by every other device forever.

**Status values are `text` + `CHECK`, not Postgres enums.** Adding a value to a
pg enum needs a migration and cannot run inside a transaction, and the Dart side
already treats them as plain strings.

**Money is integer paise.** Floating point accumulates rounding error across
revenue reports.

**Unique indexes are partial (`where is_deleted = false`).** Soft-deleting a
record frees the slot again — a re-added attendance record for the same day, or
a re-booking after cancellation. The local Drift indexes match.

**Capacity is enforced by a trigger holding `select ... for update` on the class
row.** Two devices booking the last slot offline both upload on reconnect; the
lock serialises them so the second is rejected rather than overbooking. Verified
with concurrent connections — see `tests/README.md`.

**Members can insert `self_reported` attendance but not `qr_scan`.** The RLS
policy checks the `source` column, so a member cannot forge a staff-verified
visit. A QR scan arriving later upgrades the self-report client-side.

**Role changes are guarded by a trigger.** An `UPDATE` policy cannot compare old
and new values, so preventing a member from setting their own role to `admin`
needs `guard_profile_role_change`.

## Known gaps

- **`trainer_has_member`** infers assignment from who created a member's workout
  or diet plan, because `brain.md` §5 has no explicit trainer↔member table. If
  one is added, widen that function rather than every policy.
- **`expire_memberships()`** is not scheduled. Enable `pg_cron` and run it
  nightly, or call it from the app on admin login.
- **Realtime** is not configured. `brain.md` §4 limits it to new announcements
  and class cancellations; enable those two publications in Phase 9/11.

## Testing

See `tests/README.md`. The suite was validated against PostgreSQL 18.6 with
Supabase objects stubbed, since this machine has no Docker for `supabase start`.
