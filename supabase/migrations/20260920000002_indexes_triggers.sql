-- The Iron Yard — indexes, constraints and the updated_at trigger

-- ---------------------------------------------------------------------------
-- updated_at is server-authoritative
-- ---------------------------------------------------------------------------
-- Incremental sync pulls `where updated_at > last_sync_time` (brain.md §4).
-- If clients set updated_at themselves, a device with a slow clock writes a
-- timestamp in the past and every other device skips that row forever. The
-- trigger overwrites whatever the client sent.
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

do $$
declare
  t text;
begin
  foreach t in array array[
    'profiles', 'trainers', 'membership_plans', 'memberships',
    'attendance', 'payments', 'workout_plans', 'workout_exercises',
    'exercise_completions', 'diet_plans', 'classes', 'class_bookings',
    'announcements', 'feedback'
  ]
  loop
    execute format(
      'drop trigger if exists set_updated_at on public.%I', t
    );
    execute format(
      'create trigger set_updated_at before insert or update on public.%I '
      'for each row execute function public.set_updated_at()', t
    );
  end loop;
end;
$$;

-- ---------------------------------------------------------------------------
-- Sync indexes
-- ---------------------------------------------------------------------------
-- Every pull filters on updated_at, so each synced table needs this index or
-- the pull degrades to a full scan as the table grows.
do $$
declare
  t text;
begin
  foreach t in array array[
    'profiles', 'trainers', 'membership_plans', 'memberships',
    'attendance', 'payments', 'workout_plans', 'workout_exercises',
    'exercise_completions', 'diet_plans', 'classes', 'class_bookings',
    'announcements', 'feedback'
  ]
  loop
    execute format(
      'create index if not exists idx_%s_updated_at on public.%I (updated_at)',
      t, t
    );
  end loop;
end;
$$;

-- ---------------------------------------------------------------------------
-- Duplicate attendance guard (brain.md §6.4)
-- ---------------------------------------------------------------------------
-- The local database enforces the same rule. This is the half that matters
-- when two devices queue a check-in for the same member offline and both
-- upload on reconnect — only one can win.
--
-- Partial (is_deleted = false) so a soft-deleted record frees the day again,
-- matching the local partial index.
create unique index if not exists uq_attendance_member_day
  on public.attendance (member_id, attendance_date)
  where is_deleted = false;

-- One booking per member per class, same reasoning.
create unique index if not exists uq_booking_class_member
  on public.class_bookings (class_id, member_id)
  where is_deleted = false;

create unique index if not exists uq_completion_exercise_day
  on public.exercise_completions (exercise_id, member_id, completed_on)
  where is_deleted = false;

-- ---------------------------------------------------------------------------
-- Foreign-key and query indexes
-- ---------------------------------------------------------------------------
-- Postgres does not index foreign keys automatically.
create index if not exists idx_memberships_member
  on public.memberships (member_id, end_date);
create index if not exists idx_memberships_plan
  on public.memberships (plan_id);
create index if not exists idx_memberships_expiring
  on public.memberships (end_date)
  where is_deleted = false and status = 'active';

create index if not exists idx_attendance_date
  on public.attendance (attendance_date);
create index if not exists idx_attendance_member
  on public.attendance (member_id, attendance_date desc);
create index if not exists idx_attendance_recorded_by
  on public.attendance (recorded_by);

create index if not exists idx_payments_member
  on public.payments (member_id, paid_at desc);
create index if not exists idx_payments_membership
  on public.payments (membership_id);
create index if not exists idx_payments_paid_at
  on public.payments (paid_at)
  where is_deleted = false and status = 'paid';

create index if not exists idx_trainers_profile
  on public.trainers (profile_id);

create index if not exists idx_workout_plans_assignee
  on public.workout_plans (assigned_to_id)
  where is_deleted = false;
create index if not exists idx_workout_exercises_plan
  on public.workout_exercises (plan_id, day_of_week, position);
create index if not exists idx_completions_member
  on public.exercise_completions (member_id, completed_on desc);
create index if not exists idx_diet_plans_assignee
  on public.diet_plans (assigned_to_id)
  where is_deleted = false;

create index if not exists idx_classes_starts_at
  on public.classes (starts_at)
  where is_deleted = false;
create index if not exists idx_classes_trainer
  on public.classes (trainer_id);
create index if not exists idx_bookings_class
  on public.class_bookings (class_id)
  where is_deleted = false and status = 'booked';
create index if not exists idx_bookings_member
  on public.class_bookings (member_id, booked_at desc);

create index if not exists idx_announcements_published
  on public.announcements (published_at desc)
  where is_deleted = false;

create index if not exists idx_feedback_member
  on public.feedback (member_id, created_at desc);
create index if not exists idx_feedback_open
  on public.feedback (created_at desc)
  where is_deleted = false and status = 'open';

create index if not exists idx_profiles_role
  on public.profiles (role)
  where is_deleted = false;
