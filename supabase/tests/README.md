# Database tests

## RLS and constraints

```sh
psql -d <scratch-db> -f supabase/tests/rls_test.sql
```

28 assertions covering role isolation, privilege escalation, the duplicate
attendance guard, class capacity, and the `updated_at` trigger. The suite runs
in a transaction and rolls back, so it leaves no rows behind.

It deliberately does **not** grant table privileges itself — those come from
`20260920000006_grants.sql`. Granting them in the test would let the suite pass
against a schema that denies every real client.

## Concurrent booking race

The capacity trigger's `for update` lock needs two simultaneous connections, so
it is not covered by the single-session suite. To verify:

1. Create a class with `capacity = 1`.
2. In session A: `begin;` insert a booking; `select pg_sleep(2);` `commit;`
3. In session B, while A sleeps: insert a second booking for the same class.

Session B must block, then fail with `Class is full (1 of 1 booked)`. Verified
2026-09-20 on PostgreSQL 18.6: B was rejected and the final booked count was 1.

Without the row lock both transactions would read the same count and both
insert — the exact failure the offline-queue design has to survive
(`brain.md` §6.8, §10.6).

## Local validation without Docker

These migrations were validated against a throwaway PostgreSQL cluster rather
than a live Supabase project. Supabase-provided objects (`auth.uid()`,
`storage.objects`, the `authenticated` role) were stubbed; that stub is a test
fixture and is not part of the migrations.
