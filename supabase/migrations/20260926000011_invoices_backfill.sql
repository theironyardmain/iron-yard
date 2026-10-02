-- The Iron Yard — one-time backfill of invoices for pre-invoicing history
--
-- Payments and memberships recorded before invoicing existed have no invoice
-- to settle. This creates one `backfill`-kind invoice per such membership
-- (priced at its plan's price_minor) and links every payment that already
-- references that membership to it, so historical members and revenue are
-- represented consistently rather than starting from a blank slate. Payments
-- with no membership_id (a truly ad-hoc historical charge) each get their own
-- backfill invoice, so no existing payment is left unlinked.
--
-- This is the only backfill: the client's local Drift migration deliberately
-- does not attempt the same thing (see lib/data/local/database.dart), so
-- there is exactly one source of truth for this one-time transformation and
-- no risk of two devices independently synthesizing divergent invoice rows
-- for the same history. A client only ever sees these rows by pulling them
-- down through the normal sync.
--
-- Idempotent via `where not exists`, so re-running this file is a no-op.

-- ---------------------------------------------------------------------------
-- One invoice per membership that has none yet.
-- ---------------------------------------------------------------------------
insert into public.invoices (
  id, member_id, membership_id, kind, description,
  subtotal_minor, total_minor, amount_paid_minor, status,
  created_at, updated_at
)
select
  gen_random_uuid(),
  m.member_id,
  m.id,
  'backfill',
  coalesce(mp.name, 'Membership') || ' (backfilled)',
  coalesce(mp.price_minor, paid.total, 0),
  coalesce(mp.price_minor, paid.total, 0),
  least(coalesce(paid.total, 0), coalesce(mp.price_minor, paid.total, 0)),
  case
    when coalesce(paid.total, 0) <= 0 then 'unpaid'
    when coalesce(paid.total, 0) >= coalesce(mp.price_minor, paid.total, 0)
      then 'paid'
    else 'partial'
  end,
  m.created_at,
  m.updated_at
from public.memberships m
left join public.membership_plans mp on mp.id = m.plan_id
left join lateral (
  select sum(p.amount_minor) as total
    from public.payments p
   where p.membership_id = m.id
     and p.status = 'paid'
     and p.is_deleted = false
) paid on true
where m.is_deleted = false
  and not exists (
    select 1 from public.invoices i where i.membership_id = m.id
  );

-- Link every paid-or-pending payment that references one of these
-- memberships to the invoice just created for it.
update public.payments p
   set invoice_id = i.id
  from public.invoices i
 where i.membership_id = p.membership_id
   and i.kind = 'backfill'
   and p.invoice_id is null
   and p.membership_id is not null;

-- ---------------------------------------------------------------------------
-- One standalone invoice per ad-hoc historical payment (no membership_id).
-- ---------------------------------------------------------------------------
-- Generates the new invoice's id in Postgres (not gen_random_uuid() inside
-- the insert) so the same id can both be inserted and written back onto the
-- payment in one statement — matching back by (member, amount, created_at)
-- would be ambiguous for two identical payments made in the same instant.
with new_invoice as (
  select
    gen_random_uuid() as id,
    p.id as payment_id,
    p.member_id,
    p.amount_minor,
    p.status,
    p.created_at,
    p.updated_at
  from public.payments p
  where p.membership_id is null
    and p.invoice_id is null
    and p.is_deleted = false
),
inserted as (
  insert into public.invoices (
    id, member_id, membership_id, kind, description,
    subtotal_minor, total_minor, amount_paid_minor, status,
    created_at, updated_at
  )
  select
    ni.id,
    ni.member_id,
    null,
    'backfill',
    'Backfilled payment',
    ni.amount_minor,
    ni.amount_minor,
    case when ni.status = 'paid' then ni.amount_minor else 0 end,
    case when ni.status = 'paid' then 'paid' else 'unpaid' end,
    ni.created_at,
    ni.updated_at
  from new_invoice ni
  returning id
)
update public.payments p
   set invoice_id = ni.id
  from new_invoice ni
 where p.id = ni.payment_id;
