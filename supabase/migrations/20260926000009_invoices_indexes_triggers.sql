-- The Iron Yard — invoices indexes and updated_at trigger

drop trigger if exists set_updated_at on public.invoices;
create trigger set_updated_at before insert or update on public.invoices
  for each row execute function public.set_updated_at();

-- Sync pulls filter on updated_at, same as every other synced table.
create index if not exists idx_invoices_updated_at
  on public.invoices (updated_at);

create index if not exists idx_invoices_member
  on public.invoices (member_id, status);

create index if not exists idx_invoices_membership
  on public.invoices (membership_id);

-- The dues/outstanding-balances report: open invoices, soonest due first.
create index if not exists idx_invoices_outstanding
  on public.invoices (due_date)
  where is_deleted = false and status in ('unpaid', 'partial');

create index if not exists idx_payments_invoice
  on public.payments (invoice_id);
