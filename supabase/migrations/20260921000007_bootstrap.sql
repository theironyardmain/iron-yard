-- The Iron Yard — first-run bootstrap (tasks.md 16.7)
--
-- A fresh install has an empty `profiles` table, so the very first person to
-- sign up has no role and RLS locks them out of everything. Something has to
-- make the first admin, and it cannot be the app: a client that could promote
-- itself to admin would be a privilege-escalation hole.

-- ---------------------------------------------------------------------------
-- Profile on sign-up
-- ---------------------------------------------------------------------------
-- Every Supabase Auth user gets a profile row automatically, so a member
-- invited by the gym can sign in and immediately have somewhere to be.
--
-- The role is always 'member'. Staff are promoted deliberately, never by
-- signing up.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, role, full_name, email, joined_at)
  values (
    new.id,
    'member',
    coalesce(
      new.raw_user_meta_data ->> 'full_name',
      nullif(split_part(coalesce(new.email, ''), '@', 1), ''),
      'New member'
    ),
    new.email,
    now()
  )
  on conflict (id) do nothing;

  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------------------------------------------------------------------------
-- Claiming the first admin
-- ---------------------------------------------------------------------------
-- Promotes the caller to admin, but **only while no admin exists**. Once the
-- gym owner has claimed it, this can never be used again — a second caller is
-- refused, so a member cannot promote themselves later.
-- The role-change guard from 20260920000004_rls.sql refuses any promotion by a
-- non-admin — correct in general, but it also blocks the very first one, since
-- at that moment no admin exists to authorise it. The guard is relaxed for the
-- duration of this function only, via a session flag it checks.
create or replace function public.claim_first_admin()
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  admin_count integer;
begin
  if auth.uid() is null then
    raise exception 'Must be signed in to claim admin'
      using errcode = 'insufficient_privilege';
  end if;

  -- Lock the table so two people signing up simultaneously cannot both
  -- become admin.
  lock table public.profiles in exclusive mode;

  select count(*) into admin_count
    from public.profiles
   where role = 'admin' and is_deleted = false;

  if admin_count > 0 then
    raise exception 'An admin already exists'
      using errcode = 'insufficient_privilege',
            hint = 'admin_exists';
  end if;

  -- Local to this transaction, so it cannot leak into any other statement.
  perform set_config('app.bootstrapping_admin', 'on', true);

  update public.profiles
     set role = 'admin'
   where id = auth.uid();

  perform set_config('app.bootstrapping_admin', 'off', true);

  if not found then
    raise exception 'No profile for the current user'
      using errcode = 'no_data_found';
  end if;

  return 'admin';
end;
$$;

-- Re-declare the guard to honour the bootstrap flag. Everything else about it
-- is unchanged: a member still cannot promote themselves.
create or replace function public.guard_profile_role_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.role is distinct from old.role
     and not public.is_admin()
     and coalesce(
           current_setting('app.bootstrapping_admin', true),
           'off'
         ) <> 'on' then
    raise exception 'Only an admin may change a profile role'
      using errcode = 'insufficient_privilege';
  end if;
  return new;
end;
$$;

grant execute on function public.claim_first_admin() to authenticated;

comment on function public.claim_first_admin is
  'One-time bootstrap: promotes the caller to admin only while the gym has '
  'none. Refused once an admin exists, so it cannot be used to escalate.';

-- ---------------------------------------------------------------------------
-- Starter membership plans
-- ---------------------------------------------------------------------------
-- Seeded so the owner can assign a membership on day one rather than having to
-- build plans before the app is usable. Prices are placeholders in paise;
-- editing or retiring them is a normal admin action.
insert into public.membership_plans (id, name, description, duration_days, price_minor)
values
  (
    gen_random_uuid(),
    'Monthly',
    'One month of full gym access',
    30,
    150000
  ),
  (
    gen_random_uuid(),
    'Quarterly',
    'Three months, discounted',
    90,
    400000
  ),
  (
    gen_random_uuid(),
    'Annual',
    'Twelve months, best value',
    365,
    1400000
  )
on conflict do nothing;
