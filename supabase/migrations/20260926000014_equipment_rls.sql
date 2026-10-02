-- The Iron Yard — equipment Row Level Security (brain.md §6.10)
--
-- Admins manage equipment (create/edit/retire/log service); trainers can
-- view it; members have no access — equipment is a staff concern, not
-- something members browse.

alter table public.equipment_items enable row level security;
alter table public.equipment_items force row level security;

alter table public.equipment_service_logs enable row level security;
alter table public.equipment_service_logs force row level security;

drop policy if exists equipment_items_select on public.equipment_items;
create policy equipment_items_select on public.equipment_items
  for select using (public.is_staff());

drop policy if exists equipment_items_write on public.equipment_items;
create policy equipment_items_write on public.equipment_items
  for all using (public.is_admin()) with check (public.is_admin());

drop policy if exists equipment_service_logs_select on public.equipment_service_logs;
create policy equipment_service_logs_select on public.equipment_service_logs
  for select using (public.is_staff());

drop policy if exists equipment_service_logs_write on public.equipment_service_logs;
create policy equipment_service_logs_write on public.equipment_service_logs
  for all using (public.is_admin()) with check (public.is_admin());

grant select, insert, update, delete on public.equipment_items to authenticated;
grant select, insert, update, delete on public.equipment_service_logs to authenticated;
