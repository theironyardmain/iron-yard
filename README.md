# The Iron Yard

Offline-first gym management app — Flutter + Supabase + Drift.

- [`brain.md`](brain.md) — source of truth for features and architecture decisions
- [`tasks.md`](tasks.md) — implementation task list and build order
- [`pitch.md`](pitch.md) — owner-facing summary

---

## Requirements

| Tool | Version used |
|------|--------------|
| Flutter | 3.41.9 (stable) |
| Dart | 3.11.5 |
| Android SDK | 36.1.0 |
| minSdk | 23 |

Target platform is **Android** (app ID `com.theironyard.app`).

Web is enabled as a **development preview only** — so the app can be opened in a
browser without installing an APK. It is not a shipping target: local
notifications do not work on web at all, so membership/payment/class reminders
and the daily check-in (`brain.md` §6.7, §6.9) are Android-only.

---

## Setup

1. Install dependencies:

   ```sh
   flutter pub get
   ```

2. Create `env.json` in the project root (it is gitignored — never commit it):

   ```sh
   cp env.example.json env.json
   ```

   Then fill in the values from your Supabase dashboard
   (Project Settings → API).

---

## Running

```sh
flutter run --dart-define-from-file=env.json
```

Or pass the values individually:

```sh
flutter run \
  --dart-define=SUPABASE_URL=https://your-ref.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=your-key
```

Building without these values is not a crash — the app starts and shows a
"Configuration required" screen naming the missing variables.

### Preview in a browser

```sh
flutter run -d chrome --dart-define-from-file=env.json
```

The local database runs on WebAssembly there. `web/sqlite3.wasm` and
`web/drift_worker.js` are committed and **must stay in step with the `drift` and
`sqlite3` versions in `pubspec.lock`** — a mismatch fails at runtime, not at
build time. After upgrading either package, re-download both:

```sh
curl -L -o web/sqlite3.wasm \n  https://github.com/simolus3/sqlite3.dart/releases/download/sqlite3-<ver>/sqlite3.wasm

curl -L -o web/drift_worker.js \n  https://github.com/simolus3/drift/releases/download/drift-<ver>/drift_worker.js
```

Currently pinned to sqlite3 2.9.0 (wasm) and drift 2.34.0 (worker).

### Build

```sh
flutter build apk --release --dart-define-from-file=env.json
flutter build appbundle --release --dart-define-from-file=env.json

# Preview build only
flutter build web --dart-define-from-file=env.json
```

Release builds are minified and resource-shrunk (R8). Keep rules in
`android/app/proguard-rules.pro` — Drift, `flutter_local_notifications` and
`mobile_scanner` all load code reflectively and would otherwise be stripped.

---

## Releasing

### 1. Apply the database schema

```sh
supabase link --project-ref <your-project-ref>
supabase db push
```

### 2. Claim the first admin

A fresh database has no admin, and RLS locks everyone out until one exists.
Sign up in the app, then call the one-time bootstrap:

```sql
select public.claim_first_admin();
```

It promotes the caller **only while no admin exists**; a second call is
refused, so it cannot be used to escalate later. Three starter membership
plans are seeded so the gym is usable on day one.

### 3. Sign the build

```sh
keytool -genkey -v -keystore upload-keystore.jks -keyalg RSA   -keysize 2048 -validity 10000 -alias upload

cp android/key.properties.example android/key.properties
# fill in the paths and passwords
```

`android/key.properties` and `*.jks` are gitignored. Without the file the
release build falls back to debug signing, which Play will reject — deliberate,
so an unsigned build cannot be uploaded by accident.

### 4. Upload

```sh
flutter build appbundle --release --dart-define-from-file=env.json
```

The bundle lands in `build/app/outputs/bundle/release/app-release.aab`.

---

## Tests

```sh
flutter test                                    # 411 tests
psql -d <db> -f supabase/tests/rls_test.sql     # 28 RLS assertions
psql -d <db> -f supabase/tests/bootstrap_test.sql
python supabase/tests/check_schema_parity.py --dsn "..."
```

`test/unit/offline_capability_test.dart` covers every feature `brain.md` §7
promises works offline, with no Supabase client constructed — if a path reached
for the network it would fail there.

---

## Checks

```sh
flutter analyze     # must report no issues
flutter test
```

Both are expected to pass before any commit.

---

## Project layout

```
lib/
  core/
    config/       Env (build-time Supabase config)
    constants/    App constants, role/source/payment enums
    theme/        Material 3 theming
    utils/
    errors/
  data/
    local/        Drift database, tables, DAOs        (Phase 1)
    remote/       Supabase client wrapper
    models/       Shared domain models
    repositories/ Local-first repositories             (Phase 3+)
    sync/         Sync engine, queue, conflict policy  (Phase 10)
  features/       One folder per feature area
  shared/         Cross-feature widgets and providers
test/
  unit/
  widget/
```

---

## Notes

- **Secrets.** The Supabase publishable ("anon") key is safe to ship in a client
  binary — it is public by design, and every table is protected by Row Level
  Security. It is still kept out of source control so keys can be rotated and
  builds retargeted without a code change.
- **Generated code.** Drift output (`*.g.dart`) is committed, so a clean checkout
  builds without running codegen first. Regenerate with:

  ```sh
  dart run build_runner build --delete-conflicting-outputs
  ```

- **Dependency pins.** `drift`/`drift_dev` are held at `^2.34.0`. Version 2.34.6+
  requires `analyzer >=13`, which needs `meta ^1.18.3`, but Flutter 3.41.9 pins
  `meta 1.17.0`. Revisit when the Flutter SDK ships a newer `meta`.
- **`sqlite3_flutter_libs`** resolves to `0.6.0+eol`. This is the current
  supported path for Drift on Flutter — `drift_flutter` requires it. Not a
  problem to fix.
- **Core library desugaring** is enabled in `android/app/build.gradle.kts`;
  `flutter_local_notifications` requires it for scheduled reminders.
- **`AppDatabase.memory()` is test-only** and resolved by conditional import
  (`lib/data/local/connection/`). It pulls in `package:drift/native.dart`, which
  imports `dart:ffi` and cannot compile for the web — importing it
  unconditionally breaks `flutter build web` even though only tests use it.
