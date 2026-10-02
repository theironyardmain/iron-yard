-- The Iron Yard — first-run bootstrap verification (tasks.md 16.7)
--
--   psql -d <scratch-db> -f supabase/tests/bootstrap_test.sql
--
-- Runs in a transaction and rolls back. The important assertion is the last
-- one: relaxing the role guard for the bootstrap must not open a general
-- privilege-escalation hole.

\set ON_ERROR_STOP on

begin;

insert into auth.users (id, email) values
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'owner@gym.test'),
  ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'member@gym.test');

do $$
declare c integer;
begin
  select count(*) into c from public.profiles where role = 'member';
  if c = 2 then
    raise notice 'PASS  sign-up creates a member profile';
  else
    raise exception 'FAIL  expected 2 member profiles, got %', c;
  end if;
end; $$;

-- The owner claims admin on a gym that has none.
set local role authenticated;
set local request.jwt.claim.sub = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
select public.claim_first_admin();
reset role;

do $$
declare r text;
begin
  select role into r from public.profiles
   where id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
  if r = 'admin' then
    raise notice 'PASS  first caller becomes admin';
  else
    raise exception 'FAIL  role is %', r;
  end if;
end; $$;

-- A second caller must be refused: the bootstrap is one-time only.
do $$
begin
  begin
    set local role authenticated;
    set local request.jwt.claim.sub = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
    perform public.claim_first_admin();
    raise exception 'FAIL  a second user claimed admin';
  exception
    when insufficient_privilege then
      raise notice 'PASS  second claim refused';
  end;
end; $$;

reset role;
do $$
declare r text;
begin
  select role into r from public.profiles
   where id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
  if r = 'member' then
    raise notice 'PASS  the refused user is still a member';
  else
    raise exception 'FAIL  role is %', r;
  end if;
end; $$;

do $$
declare c integer;
begin
  select count(*) into c from public.membership_plans where is_deleted = false;
  if c >= 3 then
    raise notice 'PASS  starter plans seeded (%)', c;
  else
    raise exception 'FAIL  only % plans seeded', c;
  end if;
end; $$;

-- The guard relaxation is scoped to the bootstrap function. An ordinary
-- self-promotion must still be refused.
do $$
begin
  begin
    set local role authenticated;
    set local request.jwt.claim.sub = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
    update public.profiles set role = 'admin'
     where id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
    raise exception 'FAIL  a member self-promoted to admin';
  exception
    when insufficient_privilege then
      raise notice 'PASS  the guard still blocks self-promotion';
  end;
end; $$;

rollback;

\echo ''
\echo 'All bootstrap assertions passed.'
