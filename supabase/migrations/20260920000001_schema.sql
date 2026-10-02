-- The Iron Yard — core schema
--
-- Column names mirror the Drift schema exactly (lib/data/local/). Sync maps rows
-- field-for-field, so a rename on either side silently drops data.
--
-- Deliberately NOT mirrored from the local database:
--   * is_dirty            — local upload bookkeeping (lib/.../sync_columns.dart)
--   * announcements.is_read — per-device read state
--   * emergency_contacts  — device-only by design (brain.md §6.2)
--   * sync_queue / sync_state — device-only (brain.md §5)

-- ---------------------------------------------------------------------------
-- Enums
-- ---------------------------------------------------------------------------
-- Stored as text with CHECK constraints rather than Postgres enum types:
-- adding a value to a pg enum needs a migration and cannot run inside a
-- transaction, while the Dart side already treats these as plain strings.

-- ---------------------------------------------------------------------------
-- profiles
-- ---------------------------------------------------------------------------
-- id matches auth.users.id for users who can sign in. Members added by staff
-- who have no login yet get a client-generated UUID, so the FK is deferred to
-- application logic rather than declared against auth.users.
create table if not exists public.profiles (
  id            uuid primary key,
  role          text not null check (role in ('admin', 'trainer', 'member')),
  full_name     text not null,
  email         text,
  phone         text,
  photo_url     text,
  date_of_birth timestamptz,
  gender        text,
  address       text,
  notes         text,
  is_active     boolean not null default true,
  joined_at     timestamptz,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  is_deleted    boolean not null default false
);

comment on column public.profiles.notes is
  'Staff-only notes. Never exposed to the member — see RLS policies.';

-- ---------------------------------------------------------------------------
-- trainers
-- ---------------------------------------------------------------------------
create table if not exists public.trainers (
  id             uuid primary key,
  profile_id     uuid not null references public.profiles (id) on delete cascade,
  specialization text,
  bio            text,
  certifications text,
  hired_at       timestamptz,
  is_active      boolean not null default true,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  is_deleted     boolean not null default false
);

-- ---------------------------------------------------------------------------
-- membership_plans
-- ---------------------------------------------------------------------------
create table if not exists public.membership_plans (
  id            uuid primary key,
  name          text not null,
  description   text,
  duration_days integer not null check (duration_days > 0),
  -- Smallest currency unit (paise). Integer, not numeric/float: floating point
  -- accumulates rounding error across revenue reports.
  price_minor   integer not null check (price_minor >= 0),
  is_active     boolean not null default true,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  is_deleted    boolean not null default false
);

-- ---------------------------------------------------------------------------
-- memberships
-- ---------------------------------------------------------------------------
create table if not exists public.memberships (
  id         uuid primary key,
  member_id  uuid not null references public.profiles (id) on delete cascade,
  plan_id    uuid not null references public.membership_plans (id),
  start_date timestamptz not null,
  end_date   timestamptz not null,
  status     text not null default 'active'
               check (status in ('active', 'expired', 'cancelled')),
  notes      text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  is_deleted boolean not null default false,
  constraint memberships_dates_ordered check (end_date >= start_date)
);

-- ---------------------------------------------------------------------------
-- attendance
-- ---------------------------------------------------------------------------
-- attendance_date is date-only so "one visit per member per day" is a plain
-- uniqueness check that two timestamps either side of midnight cannot defeat.
-- The unique index lives in the constraints migration.
create table if not exists public.attendance (
  id              uuid primary key,
  member_id       uuid not null references public.profiles (id) on delete cascade,
  attendance_date date not null,
  check_in_at     timestamptz,
  check_out_at    timestamptz,
  source          text not null check (source in ('qr_scan', 'self_reported')),
  recorded_by     uuid references public.profiles (id) on delete set null,
  notes           text,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  is_deleted      boolean not null default false
);

comment on column public.attendance.source is
  'qr_scan is staff-verified and trusted for reporting; self_reported comes '
  'from the member daily check-in and is unverified (brain.md §6.7).';

-- ---------------------------------------------------------------------------
-- payments
-- ---------------------------------------------------------------------------
create table if not exists public.payments (
  id            uuid primary key,
  member_id     uuid not null references public.profiles (id) on delete cascade,
  membership_id uuid references public.memberships (id) on delete set null,
  amount_minor  integer not null check (amount_minor >= 0),
  method        text not null
                  check (method in ('cash', 'bank_transfer', 'upi', 'external')),
  status        text not null default 'paid' check (status in ('paid', 'pending')),
  paid_at       timestamptz not null,
  receipt_url   text,
  notes         text,
  recorded_by   uuid references public.profiles (id) on delete set null,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  is_deleted    boolean not null default false
);

-- receipt_local_path is intentionally absent: it is an on-device file path,
-- meaningless on the server. The client clears it once receipt_url is set.

-- ---------------------------------------------------------------------------
-- workout_plans / workout_exercises / exercise_completions
-- ---------------------------------------------------------------------------
create table if not exists public.workout_plans (
  id             uuid primary key,
  name           text not null,
  description    text,
  assigned_to_id uuid references public.profiles (id) on delete cascade,
  created_by_id  uuid references public.profiles (id) on delete set null,
  template_id    uuid,
  assigned_at    timestamptz,
  is_template    boolean not null default true,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  is_deleted     boolean not null default false
);

create table if not exists public.workout_exercises (
  id           uuid primary key,
  plan_id      uuid not null references public.workout_plans (id) on delete cascade,
  name         text not null,
  instructions text,
  image_url    text,
  sets         integer,
  reps         integer,
  weight_note  text,
  rest_seconds integer,
  day_of_week  integer check (day_of_week between 1 and 7),
  position     integer not null default 0,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  is_deleted   boolean not null default false
);

create table if not exists public.exercise_completions (
  id             uuid primary key,
  exercise_id    uuid not null references public.workout_exercises (id) on delete cascade,
  member_id      uuid not null references public.profiles (id) on delete cascade,
  completed_on   date not null,
  sets_completed integer,
  notes          text,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  is_deleted     boolean not null default false
);

-- ---------------------------------------------------------------------------
-- diet_plans
-- ---------------------------------------------------------------------------
create table if not exists public.diet_plans (
  id             uuid primary key,
  name           text not null,
  description    text,
  meals_json     text,
  assigned_to_id uuid references public.profiles (id) on delete cascade,
  created_by_id  uuid references public.profiles (id) on delete set null,
  template_id    uuid,
  assigned_at    timestamptz,
  is_template    boolean not null default true,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  is_deleted     boolean not null default false
);

-- ---------------------------------------------------------------------------
-- classes / class_bookings
-- ---------------------------------------------------------------------------
create table if not exists public.classes (
  id           uuid primary key,
  name         text not null,
  description  text,
  trainer_id   uuid references public.trainers (id) on delete set null,
  starts_at    timestamptz not null,
  ends_at      timestamptz not null,
  capacity     integer not null check (capacity > 0),
  location     text,
  status       text not null default 'scheduled'
                 check (status in ('scheduled', 'cancelled')),
  is_recurring boolean not null default false,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  is_deleted   boolean not null default false,
  constraint classes_times_ordered check (ends_at > starts_at)
);

create table if not exists public.class_bookings (
  id         uuid primary key,
  class_id   uuid not null references public.classes (id) on delete cascade,
  member_id  uuid not null references public.profiles (id) on delete cascade,
  booked_at  timestamptz not null default now(),
  status     text not null default 'booked'
               check (status in ('booked', 'cancelled', 'rejected')),
  attended   boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  is_deleted boolean not null default false
);

comment on column public.class_bookings.status is
  'rejected is set when a queued offline booking arrives after the class '
  'filled up, so the member is told rather than silently losing it.';

-- ---------------------------------------------------------------------------
-- announcements
-- ---------------------------------------------------------------------------
-- is_read is deliberately absent: read state is per-device and stays local.
create table if not exists public.announcements (
  id           uuid primary key,
  title        text not null,
  body         text not null,
  author_id    uuid references public.profiles (id) on delete set null,
  published_at timestamptz,
  is_urgent    boolean not null default false,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  is_deleted   boolean not null default false
);

-- ---------------------------------------------------------------------------
-- feedback
-- ---------------------------------------------------------------------------
create table if not exists public.feedback (
  id             uuid primary key,
  member_id      uuid not null references public.profiles (id) on delete cascade,
  subject        text,
  message        text not null,
  status         text not null default 'open' check (status in ('open', 'resolved')),
  admin_response text,
  responded_at   timestamptz,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  is_deleted     boolean not null default false
);
