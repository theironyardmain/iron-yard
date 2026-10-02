-- The Iron Yard — invoices Row Level Security
--
-- Same shape as payments (20260920000004_rls.sql): a member reads their own
-- invoices but never writes one — invoices are created by staff, either
-- automatically (plan assign/renew) or as an ad-hoc charge.

alter table public.invoices enable row level security;
alter table public.invoices force row level security;

drop policy if exists invoices_select on public.invoices;
create policy invoices_select on public.invoices
  for select using (member_id = auth.uid() or public.is_admin());

drop policy if exists invoices_write on public.invoices;
create policy invoices_write on public.invoices
  for all using (public.is_admin()) with check (public.is_admin());

grant select, insert, update, delete on public.invoices to authenticated;
