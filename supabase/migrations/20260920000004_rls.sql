-- The Iron Yard — Row Level Security (brain.md §2)
--
--   Admin   — full access
--   Trainer — assigned members, plan creation/assignment, attendance view,
--             class schedule
--   Member  — own rows only
--
-- RLS is the real access boundary. The role-gated Flutter navigation is a
-- convenience; a client holding the publishable key can call the REST API
-- directly, so anything not enforced here is not enforced.

-- ---------------------------------------------------------------------------
-- Role helpers
-- ---------------------------------------------------------------------------
-- SECURITY DEFINER so these read profiles without invoking profiles' own RLS
-- policies — a policy on profiles that called a non-definer function selecting
-- from profiles would recurse infinitely.
create or replace function public.current_role_name()
returns text
language sql
stable
security definer
set search_path = public
as $$
  select role from public.profiles where id = auth.uid() and is_deleted = false;
$$;

create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.profiles
     where id = auth.uid() and role = 'admin' and is_deleted = false
  );
$$;

create or replace function public.is_staff()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.profiles
     where id = auth.uid()
       and role in ('admin', 'trainer')
       and is_deleted = false
  );
$$;

-- Whether the current trainer is assigned to this member.
--
-- "Assigned" means the trainer created a workout or diet plan for them. There
-- is no explicit trainer↔member assignment table in brain.md §5; if one is
-- added later, widen this function rather than every policy.
create or replace function public.trainer_has_member(target_member uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
      from public.workout_plans wp
      join public.trainers t on t.id = wp.created_by_id or t.profile_id = wp.created_by_id
     where wp.assigned_to_id = target_member
       and t.profile_id = auth.uid()
       and wp.is_deleted = false
  )
  or exists (
    select 1
      from public.diet_plans dp
      join public.trainers t on t.id = dp.created_by_id or t.profile_id = dp.created_by_id
     where dp.assigned_to_id = target_member
       and t.profile_id = auth.uid()
       and dp.is_deleted = false
  );
$$;

-- ---------------------------------------------------------------------------
-- Enable RLS everywhere
-- ---------------------------------------------------------------------------
-- A table with RLS enabled and no policy denies everything, which is the
-- correct default: a table added later without a policy fails closed.
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
    execute format('alter table public.%I enable row level security', t);
    execute format('alter table public.%I force row level security', t);
  end loop;
end;
$$;

-- ---------------------------------------------------------------------------
-- profiles
-- ---------------------------------------------------------------------------
drop policy if exists profiles_select on public.profiles;
create policy profiles_select on public.profiles
  for select using (
    id = auth.uid()
    or public.is_admin()
    or (public.current_role_name() = 'trainer' and role in ('member', 'trainer'))
  );

drop policy if exists profiles_insert on public.profiles;
create policy profiles_insert on public.profiles
  for insert with check (
    -- A user may create their own profile row on first sign-in; staff may add
    -- members who have no login yet.
    id = auth.uid() or public.is_staff()
  );

drop policy if exists profiles_update on public.profiles;
create policy profiles_update on public.profiles
  for update using (id = auth.uid() or public.is_admin())
  with check (id = auth.uid() or public.is_admin());

drop policy if exists profiles_delete on public.profiles;
create policy profiles_delete on public.profiles
  for delete using (public.is_admin());

-- A member must not be able to promote themselves to admin. UPDATE policies
-- cannot compare old and new values, so the check lives in a trigger.
create or replace function public.guard_profile_role_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.role is distinct from old.role and not public.is_admin() then
    raise exception 'Only an admin may change a profile role'
      using errcode = 'insufficient_privilege';
  end if;
  return new;
end;
$$;

drop trigger if exists guard_role_change on public.profiles;
create trigger guard_role_change
  before update on public.profiles
  for each row execute function public.guard_profile_role_change();

-- ---------------------------------------------------------------------------
-- trainers
-- ---------------------------------------------------------------------------
drop policy if exists trainers_select on public.trainers;
create policy trainers_select on public.trainers
  for select using (true);  -- members may view trainer details (brain.md §6.2)

drop policy if exists trainers_write on public.trainers;
create policy trainers_write on public.trainers
  for all using (public.is_admin() or profile_id = auth.uid())
  with check (public.is_admin() or profile_id = auth.uid());

-- ---------------------------------------------------------------------------
-- membership_plans
-- ---------------------------------------------------------------------------
drop policy if exists plans_select on public.membership_plans;
create policy plans_select on public.membership_plans
  for select using (true);  -- members need to see what they can buy

drop policy if exists plans_write on public.membership_plans;
create policy plans_write on public.membership_plans
  for all using (public.is_admin()) with check (public.is_admin());

-- ---------------------------------------------------------------------------
-- memberships
-- ---------------------------------------------------------------------------
drop policy if exists memberships_select on public.memberships;
create policy memberships_select on public.memberships
  for select using (
    member_id = auth.uid()
    or public.is_admin()
    or (public.current_role_name() = 'trainer'
        and public.trainer_has_member(member_id))
  );

drop policy if exists memberships_write on public.memberships;
create policy memberships_write on public.memberships
  for all using (public.is_admin()) with check (public.is_admin());

-- ---------------------------------------------------------------------------
-- attendance
-- ---------------------------------------------------------------------------
drop policy if exists attendance_select on public.attendance;
create policy attendance_select on public.attendance
  for select using (
    member_id = auth.uid()
    or public.is_staff()
  );

-- A member may record their own self-reported check-in (brain.md §6.7), but
-- must not be able to forge a staff-verified QR scan.
drop policy if exists attendance_insert on public.attendance;
create policy attendance_insert on public.attendance
  for insert with check (
    public.is_staff()
    or (member_id = auth.uid() and source = 'self_reported')
  );

drop policy if exists attendance_update on public.attendance;
create policy attendance_update on public.attendance
  for update using (
    public.is_staff()
    or (member_id = auth.uid() and source = 'self_reported')
  )
  with check (
    public.is_staff()
    or (member_id = auth.uid() and source = 'self_reported')
  );

drop policy if exists attendance_delete on public.attendance;
create policy attendance_delete on public.attendance
  for delete using (public.is_admin());

-- ---------------------------------------------------------------------------
-- payments
-- ---------------------------------------------------------------------------
-- Members read their own history but never write: payments are recorded by
-- staff (brain.md §6.5).
drop policy if exists payments_select on public.payments;
create policy payments_select on public.payments
  for select using (member_id = auth.uid() or public.is_admin());

drop policy if exists payments_write on public.payments;
create policy payments_write on public.payments
  for all using (public.is_admin()) with check (public.is_admin());

-- ---------------------------------------------------------------------------
-- workout_plans / workout_exercises / exercise_completions
-- ---------------------------------------------------------------------------
drop policy if exists workout_plans_select on public.workout_plans;
create policy workout_plans_select on public.workout_plans
  for select using (
    assigned_to_id = auth.uid()
    or public.is_staff()
  );

drop policy if exists workout_plans_write on public.workout_plans;
create policy workout_plans_write on public.workout_plans
  for all using (public.is_staff()) with check (public.is_staff());

drop policy if exists workout_exercises_select on public.workout_exercises;
create policy workout_exercises_select on public.workout_exercises
  for select using (
    public.is_staff()
    or exists (
      select 1 from public.workout_plans p
       where p.id = plan_id and p.assigned_to_id = auth.uid()
    )
  );

drop policy if exists workout_exercises_write on public.workout_exercises;
create policy workout_exercises_write on public.workout_exercises
  for all using (public.is_staff()) with check (public.is_staff());

-- Completions are the member's own progress.
drop policy if exists completions_select on public.exercise_completions;
create policy completions_select on public.exercise_completions
  for select using (member_id = auth.uid() or public.is_staff());

drop policy if exists completions_write on public.exercise_completions;
create policy completions_write on public.exercise_completions
  for all using (member_id = auth.uid() or public.is_staff())
  with check (member_id = auth.uid() or public.is_staff());

-- ---------------------------------------------------------------------------
-- diet_plans
-- ---------------------------------------------------------------------------
drop policy if exists diet_plans_select on public.diet_plans;
create policy diet_plans_select on public.diet_plans
  for select using (assigned_to_id = auth.uid() or public.is_staff());

drop policy if exists diet_plans_write on public.diet_plans;
create policy diet_plans_write on public.diet_plans
  for all using (public.is_staff()) with check (public.is_staff());

-- ---------------------------------------------------------------------------
-- classes
-- ---------------------------------------------------------------------------
drop policy if exists classes_select on public.classes;
create policy classes_select on public.classes
  for select using (true);  -- the schedule is visible to everyone signed in

drop policy if exists classes_write on public.classes;
create policy classes_write on public.classes
  for all using (public.is_staff()) with check (public.is_staff());

-- ---------------------------------------------------------------------------
-- class_bookings
-- ---------------------------------------------------------------------------
drop policy if exists bookings_select on public.class_bookings;
create policy bookings_select on public.class_bookings
  for select using (member_id = auth.uid() or public.is_staff());

drop policy if exists bookings_insert on public.class_bookings;
create policy bookings_insert on public.class_bookings
  for insert with check (member_id = auth.uid() or public.is_staff());

drop policy if exists bookings_update on public.class_bookings;
create policy bookings_update on public.class_bookings
  for update using (member_id = auth.uid() or public.is_staff())
  with check (member_id = auth.uid() or public.is_staff());

drop policy if exists bookings_delete on public.class_bookings;
create policy bookings_delete on public.class_bookings
  for delete using (public.is_admin());

-- ---------------------------------------------------------------------------
-- announcements
-- ---------------------------------------------------------------------------
drop policy if exists announcements_select on public.announcements;
create policy announcements_select on public.announcements
  for select using (published_at is not null or public.is_staff());

drop policy if exists announcements_write on public.announcements;
create policy announcements_write on public.announcements
  for all using (public.is_admin()) with check (public.is_admin());

-- ---------------------------------------------------------------------------
-- feedback
-- ---------------------------------------------------------------------------
-- A member sees only their own submissions; admins see all (brain.md §6.2).
drop policy if exists feedback_select on public.feedback;
create policy feedback_select on public.feedback
  for select using (member_id = auth.uid() or public.is_admin());

drop policy if exists feedback_insert on public.feedback;
create policy feedback_insert on public.feedback
  for insert with check (member_id = auth.uid());

drop policy if exists feedback_update on public.feedback;
create policy feedback_update on public.feedback
  for update using (public.is_admin()) with check (public.is_admin());

drop policy if exists feedback_delete on public.feedback;
create policy feedback_delete on public.feedback
  for delete using (public.is_admin());
