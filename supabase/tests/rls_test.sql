-- The Iron Yard — RLS verification (tasks.md 2.7)
--
-- Every assertion attempts a breach that must fail, or an access that must
-- succeed. Run against a scratch database:
--
--   psql -d <db> -f supabase/tests/rls_test.sql
--
-- Exits non-zero on the first failed assertion. Policies are the real access
-- boundary (the Flutter role gating is convenience only), so these run as the
-- `authenticated` role with auth.uid() impersonated, exactly as a client does.

\set ON_ERROR_STOP on
\timing off

begin;

-- ---------------------------------------------------------------------------
-- Fixtures
-- ---------------------------------------------------------------------------
\set admin_id   '''11111111-1111-4111-8111-111111111111'''
\set trainer_id '''22222222-2222-4222-8222-222222222222'''
\set member_id  '''33333333-3333-4333-8333-333333333333'''
\set other_id   '''44444444-4444-4444-8444-444444444444'''

-- Seed as owner, bypassing RLS.
insert into public.profiles (id, role, full_name) values
  (:admin_id,   'admin',   'Admin User'),
  (:trainer_id, 'trainer', 'Trainer User'),
  (:member_id,  'member',  'Member User'),
  (:other_id,   'member',  'Other Member');

insert into public.trainers (id, profile_id, specialization)
values ('55555555-5555-4555-8555-555555555555', :trainer_id, 'Strength');

insert into public.membership_plans (id, name, duration_days, price_minor)
values ('66666666-6666-4666-8666-666666666666', 'Monthly', 30, 150000);

insert into public.memberships (id, member_id, plan_id, start_date, end_date)
values (
  '77777777-7777-4777-8777-777777777777',
  :member_id,
  '66666666-6666-4666-8666-666666666666',
  now(), now() + interval '30 days'
);

insert into public.payments (id, member_id, amount_minor, method, paid_at)
values (
  '88888888-8888-4888-8888-888888888888',
  :member_id, 150000, 'cash', now()
);

insert into public.classes (id, name, starts_at, ends_at, capacity)
values (
  '99999999-9999-4999-8999-999999999999',
  'Yoga', now() + interval '1 day', now() + interval '1 day 1 hour', 2
);

insert into public.feedback (id, member_id, message)
values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', :member_id, 'Great gym');

-- Helper: become a user.
create or replace function pg_temp.become(uid text)
returns void language plpgsql as $$
begin
  execute format('set local role authenticated');
  execute format('set local request.jwt.claim.sub = %L', uid);
end; $$;

create or replace function pg_temp.become_owner()
returns void language plpgsql as $$
begin
  reset role;
  set local request.jwt.claim.sub = '';
end; $$;

-- Helper: assert a boolean.
create or replace function pg_temp.check(label text, condition boolean)
returns void language plpgsql as $$
begin
  if condition then
    raise notice 'PASS  %', label;
  else
    raise exception 'FAIL  %', label;
  end if;
end; $$;

-- Privileges come from 20260920000006_grants.sql, not from this test. If they
-- were granted here, the suite would pass against a schema that denies every
-- client in production.

-- ---------------------------------------------------------------------------
-- Member isolation
-- ---------------------------------------------------------------------------
select pg_temp.become('33333333-3333-4333-8333-333333333333');

select pg_temp.check(
  'member sees own profile',
  (select count(*) from public.profiles where id = '33333333-3333-4333-8333-333333333333') = 1
);

select pg_temp.check(
  'member cannot see another member profile',
  (select count(*) from public.profiles where id = '44444444-4444-4444-8444-444444444444') = 0
);

select pg_temp.check(
  'member sees own payments',
  (select count(*) from public.payments) = 1
);

select pg_temp.check(
  'member sees own membership',
  (select count(*) from public.memberships) = 1
);

select pg_temp.check(
  'member sees own feedback only',
  (select count(*) from public.feedback) = 1
);

-- A member must not be able to record a payment for themselves.
do $$
begin
  begin
    insert into public.payments (id, member_id, amount_minor, method, paid_at)
    values ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
            '33333333-3333-4333-8333-333333333333', 999999, 'cash', now());
    raise exception 'FAIL  member was able to insert a payment';
  exception
    when insufficient_privilege then raise notice 'PASS  member cannot insert a payment';
    when others then
      if sqlstate = '42501' then
        raise notice 'PASS  member cannot insert a payment';
      else
        raise;
      end if;
  end;
end; $$;

-- A member must not be able to forge a staff-verified QR scan.
do $$
begin
  begin
    insert into public.attendance (id, member_id, attendance_date, source)
    values ('cccccccc-cccc-4ccc-8ccc-cccccccccccc',
            '33333333-3333-4333-8333-333333333333', current_date, 'qr_scan');
    raise exception 'FAIL  member forged a qr_scan attendance record';
  exception
    when insufficient_privilege then raise notice 'PASS  member cannot forge a qr_scan';
    when others then
      if sqlstate = '42501' then
        raise notice 'PASS  member cannot forge a qr_scan';
      else raise; end if;
  end;
end; $$;

-- But a member may record their own self-report (brain.md §6.7).
insert into public.attendance (id, member_id, attendance_date, source)
values ('dddddddd-dddd-4ddd-8ddd-dddddddddddd',
        '33333333-3333-4333-8333-333333333333', current_date, 'self_reported');

select pg_temp.check(
  'member can self-report attendance',
  (select count(*) from public.attendance where source = 'self_reported') = 1
);

-- A member must not be able to record attendance for someone else.
do $$
begin
  begin
    insert into public.attendance (id, member_id, attendance_date, source)
    values ('eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',
            '44444444-4444-4444-8444-444444444444', current_date, 'self_reported');
    raise exception 'FAIL  member recorded attendance for another member';
  exception
    when insufficient_privilege then raise notice 'PASS  member cannot record for others';
    when others then
      if sqlstate = '42501' then
        raise notice 'PASS  member cannot record for others';
      else raise; end if;
  end;
end; $$;

-- Privilege escalation: a member must not be able to promote themselves.
do $$
begin
  begin
    update public.profiles set role = 'admin'
     where id = '33333333-3333-4333-8333-333333333333';
    raise exception 'FAIL  member escalated to admin';
  exception
    when insufficient_privilege then raise notice 'PASS  member cannot self-promote';
    when others then
      if sqlstate = '42501' then
        raise notice 'PASS  member cannot self-promote';
      else raise; end if;
  end;
end; $$;

-- ---------------------------------------------------------------------------
-- Trainer scope
-- ---------------------------------------------------------------------------
select pg_temp.become('22222222-2222-4222-8222-222222222222');

select pg_temp.check(
  'trainer sees member profiles',
  (select count(*) from public.profiles where role = 'member') = 2
);

select pg_temp.check(
  'trainer cannot see payments',
  (select count(*) from public.payments) = 0
);

select pg_temp.check(
  'trainer can see attendance',
  (select count(*) from public.attendance) >= 1
);

-- Trainer is staff, so may record a QR scan.
insert into public.attendance (id, member_id, attendance_date, source, recorded_by)
values ('ffffffff-ffff-4fff-8fff-ffffffffffff',
        '44444444-4444-4444-8444-444444444444', current_date, 'qr_scan',
        '22222222-2222-4222-8222-222222222222');

select pg_temp.check(
  'trainer can record a qr_scan',
  (select count(*) from public.attendance where source = 'qr_scan') = 1
);

-- Trainer must not be able to create a membership plan.
do $$
begin
  begin
    insert into public.membership_plans (id, name, duration_days, price_minor)
    values ('12121212-1212-4212-8212-121212121212', 'Hacked', 1, 0);
    raise exception 'FAIL  trainer created a membership plan';
  exception
    when insufficient_privilege then raise notice 'PASS  trainer cannot create a plan';
    when others then
      if sqlstate = '42501' then raise notice 'PASS  trainer cannot create a plan';
      else raise; end if;
  end;
end; $$;

-- ---------------------------------------------------------------------------
-- Admin
-- ---------------------------------------------------------------------------
select pg_temp.become('11111111-1111-4111-8111-111111111111');

select pg_temp.check(
  'admin sees all profiles',
  (select count(*) from public.profiles) = 4
);

select pg_temp.check(
  'admin sees all payments',
  (select count(*) from public.payments) = 1
);

select pg_temp.check(
  'admin sees all feedback',
  (select count(*) from public.feedback) = 1
);

-- Admin may change a role.
update public.profiles set role = 'trainer'
 where id = '44444444-4444-4444-8444-444444444444';
select pg_temp.check(
  'admin can change a role',
  (select role from public.profiles
    where id = '44444444-4444-4444-8444-444444444444') = 'trainer'
);
update public.profiles set role = 'member'
 where id = '44444444-4444-4444-8444-444444444444';

-- ---------------------------------------------------------------------------
-- Class capacity (brain.md §6.8)
-- ---------------------------------------------------------------------------
select pg_temp.become_owner();

-- Capacity is 2.
insert into public.class_bookings (id, class_id, member_id)
values ('13131313-1313-4313-8313-131313131313',
        '99999999-9999-4999-8999-999999999999',
        '33333333-3333-4333-8333-333333333333');
insert into public.class_bookings (id, class_id, member_id)
values ('14141414-1414-4414-8414-141414141414',
        '99999999-9999-4999-8999-999999999999',
        '44444444-4444-4444-8444-444444444444');

select pg_temp.check(
  'two bookings fit a capacity-2 class',
  (select count(*) from public.class_bookings where status = 'booked') = 2
);

-- The third must be refused by the trigger, not the client.
do $$
begin
  begin
    insert into public.class_bookings (id, class_id, member_id)
    values ('15151515-1515-4515-8515-151515151515',
            '99999999-9999-4999-8999-999999999999',
            '11111111-1111-4111-8111-111111111111');
    raise exception 'FAIL  overbooking was allowed';
  exception
    when check_violation then raise notice 'PASS  overbooking rejected';
  end;
end; $$;

-- Cancelling frees a slot.
update public.class_bookings set status = 'cancelled'
 where id = '13131313-1313-4313-8313-131313131313';

insert into public.class_bookings (id, class_id, member_id)
values ('16161616-1616-4616-8616-161616161616',
        '99999999-9999-4999-8999-999999999999',
        '11111111-1111-4111-8111-111111111111');

select pg_temp.check(
  'cancelling frees a slot',
  (select count(*) from public.class_bookings
    where status = 'booked' and is_deleted = false) = 2
);

-- A cancelled class refuses bookings.
update public.classes set status = 'cancelled'
 where id = '99999999-9999-4999-8999-999999999999';

do $$
begin
  begin
    insert into public.class_bookings (id, class_id, member_id)
    values ('17171717-1717-4717-8717-171717171717',
            '99999999-9999-4999-8999-999999999999',
            '22222222-2222-4222-8222-222222222222');
    raise exception 'FAIL  booked a cancelled class';
  exception
    when check_violation then raise notice 'PASS  cancelled class refuses bookings';
  end;
end; $$;

-- ---------------------------------------------------------------------------
-- Duplicate attendance (brain.md §6.4)
-- ---------------------------------------------------------------------------
do $$
begin
  begin
    insert into public.attendance (id, member_id, attendance_date, source)
    values ('18181818-1818-4818-8818-181818181818',
            '33333333-3333-4333-8333-333333333333', current_date, 'qr_scan');
    raise exception 'FAIL  duplicate attendance was allowed';
  exception
    when unique_violation then raise notice 'PASS  duplicate attendance rejected';
  end;
end; $$;

-- A soft-deleted record frees the day again (partial unique index).
update public.attendance set is_deleted = true
 where id = 'dddddddd-dddd-4ddd-8ddd-dddddddddddd';

insert into public.attendance (id, member_id, attendance_date, source)
values ('19191919-1919-4919-8919-191919191919',
        '33333333-3333-4333-8333-333333333333', current_date, 'qr_scan');

select pg_temp.check(
  'soft delete frees the attendance day',
  (select count(*) from public.attendance
    where member_id = '33333333-3333-4333-8333-333333333333'
      and is_deleted = false) = 1
);

-- ---------------------------------------------------------------------------
-- updated_at is server-authoritative (brain.md §4)
-- ---------------------------------------------------------------------------
-- A client with a skewed clock must not be able to write a past timestamp,
-- which would make every other device skip the row on incremental sync.
insert into public.announcements (id, title, body, updated_at)
values ('1a1a1a1a-1a1a-4a1a-8a1a-1a1a1a1a1a1a', 'Test', 'Body',
        timestamptz '2000-01-01');

select pg_temp.check(
  'trigger overrides a client-supplied updated_at',
  (select updated_at from public.announcements
    where id = '1a1a1a1a-1a1a-4a1a-8a1a-1a1a1a1a1a1a') > now() - interval '1 minute'
);

-- ---------------------------------------------------------------------------
-- expire_memberships
-- ---------------------------------------------------------------------------
insert into public.memberships (id, member_id, plan_id, start_date, end_date, status)
values ('1b1b1b1b-1b1b-4b1b-8b1b-1b1b1b1b1b1b',
        '44444444-4444-4444-8444-444444444444',
        '66666666-6666-4666-8666-666666666666',
        now() - interval '60 days', now() - interval '30 days', 'active');

select pg_temp.check(
  'expire_memberships flips lapsed rows',
  public.expire_memberships() >= 1
);

select pg_temp.check(
  'expire_memberships leaves current rows alone',
  (select status from public.memberships
    where id = '77777777-7777-4777-7777-777777777777'
       or id = '77777777-7777-4777-8777-777777777777') = 'active'
);

rollback;

\echo ''
\echo 'All RLS and constraint assertions passed.'

-- ---------------------------------------------------------------------------
-- Concurrency note
-- ---------------------------------------------------------------------------
-- The capacity trigger takes `select ... for update` on the class row, so two
-- transactions racing for the last slot serialise: the second blocks, then
-- sees the first one's committed booking and is rejected. That path cannot be
-- exercised from a single psql session (it needs two concurrent connections),
-- so it is verified separately — see supabase/tests/README.md.
