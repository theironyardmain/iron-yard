-- The Iron Yard — class capacity enforcement (brain.md §6.8)
--
-- Bookings are made offline and uploaded in a batch on reconnect, so two
-- devices can both believe they took the last slot. The client checks capacity
-- locally for a fast answer; this is the check that actually decides.

create or replace function public.enforce_class_capacity()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  class_capacity integer;
  class_status   text;
  booked_count   integer;
begin
  -- Only an active booking consumes a slot.
  if new.status <> 'booked' or new.is_deleted then
    return new;
  end if;

  -- On UPDATE, skip when the row was already counted as booked.
  if tg_op = 'UPDATE'
     and old.status = 'booked'
     and old.is_deleted = false then
    return new;
  end if;

  -- FOR UPDATE serialises concurrent bookings for the same class: the second
  -- transaction waits here and then sees the first one's row. Without the lock
  -- both could read the same count and both insert.
  select capacity, status
    into class_capacity, class_status
    from public.classes
   where id = new.class_id
     for update;

  if not found then
    raise exception 'Class % does not exist', new.class_id
      using errcode = 'foreign_key_violation';
  end if;

  if class_status = 'cancelled' then
    raise exception 'Class is cancelled'
      using errcode = 'check_violation',
            hint = 'class_cancelled';
  end if;

  select count(*)
    into booked_count
    from public.class_bookings
   where class_id = new.class_id
     and status = 'booked'
     and is_deleted = false
     and id <> new.id;

  if booked_count >= class_capacity then
    raise exception 'Class is full (% of % booked)',
      booked_count, class_capacity
      using errcode = 'check_violation',
            hint = 'class_full';
  end if;

  return new;
end;
$$;

drop trigger if exists enforce_capacity on public.class_bookings;
create trigger enforce_capacity
  before insert or update on public.class_bookings
  for each row execute function public.enforce_class_capacity();

comment on function public.enforce_class_capacity is
  'Rejects a booking that would exceed class capacity. Raises with hint '
  'class_full or class_cancelled so the sync engine can mark the queued '
  'entry rejected and tell the member (brain.md §10.6).';

-- ---------------------------------------------------------------------------
-- Membership expiry
-- ---------------------------------------------------------------------------
-- Status is derived from dates on the client for display, but a stored status
-- left at 'active' forever would make the expiring-soon index useless. This
-- reconciles it; call from a scheduled job (pg_cron) or on demand.
create or replace function public.expire_memberships()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  affected integer;
begin
  update public.memberships
     set status = 'expired'
   where status = 'active'
     and is_deleted = false
     and end_date < current_date;

  get diagnostics affected = row_count;
  return affected;
end;
$$;

comment on function public.expire_memberships is
  'Flips lapsed active memberships to expired. Safe to run repeatedly. '
  'Does not touch cancelled rows.';
