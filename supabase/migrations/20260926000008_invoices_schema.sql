-- The Iron Yard — invoices (brain.md §6.5)
--
-- A charge against a member — a plan renewal, or an ad-hoc fee (registration,
-- PT add-on, manual late fee) — settled by one or more `payments` rows. There
-- is still no payment gateway: this is a ledger for money owed, not a
-- checkout.
--
-- amount_paid_minor/status are denormalized rather than derived live from
-- payments (see lib/data/local/tables/invoice_tables.dart for the full
-- rationale) and are kept correct by the client's `InvoiceDao.applyPayment`,
-- which updates both rows together.

create table if not exists public.invoices (
  id                uuid primary key,
  member_id         uuid not null references public.profiles (id) on delete cascade,
  membership_id     uuid references public.memberships (id) on delete set null,
  kind              text not null check (kind in ('plan_charge', 'ad_hoc', 'backfill')),
  description       text,
  -- Paise, before discount.
  subtotal_minor    integer not null check (subtotal_minor >= 0),
  discount_kind     text check (discount_kind in ('flat', 'percent')),
  discount_value    integer,
  discount_minor    integer not null default 0 check (discount_minor >= 0),
  -- subtotal_minor - discount_minor.
  total_minor       integer not null check (total_minor >= 0),
  amount_paid_minor integer not null default 0 check (amount_paid_minor >= 0),
  status            text not null default 'unpaid'
                      check (status in ('unpaid', 'partial', 'paid', 'void')),
  due_date          timestamptz,
  created_by        uuid references public.profiles (id) on delete set null,
  notes             text,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  is_deleted        boolean not null default false,
  constraint invoices_paid_not_over_total check (amount_paid_minor <= total_minor)
);

comment on column public.invoices.kind is
  'plan_charge/ad_hoc are created by the app. backfill is reserved for rows '
  'this migration''s companion backfill creates from history predating '
  'invoicing — see 20260926000011_invoices_backfill.sql.';

alter table public.payments
  add column if not exists invoice_id uuid references public.invoices (id) on delete set null;

comment on column public.payments.invoice_id is
  'The invoice this payment settles. Null for a payment recorded before '
  'invoicing existed, or through the legacy free-floating record path.';
