-- The Iron Yard — equipment indexes and updated_at triggers

drop trigger if exists set_updated_at on public.equipment_items;
create trigger set_updated_at before insert or update on public.equipment_items
  for each row execute function public.set_updated_at();

drop trigger if exists set_updated_at on public.equipment_service_logs;
create trigger set_updated_at before insert or update on public.equipment_service_logs
  for each row execute function public.set_updated_at();

create index if not exists idx_equipment_items_updated_at
  on public.equipment_items (updated_at);

create index if not exists idx_equipment_service_logs_updated_at
  on public.equipment_service_logs (updated_at);

create index if not exists idx_equipment_items_status
  on public.equipment_items (status)
  where is_deleted = false;

-- Equipment due for service: scheduled items not yet retired.
create index if not exists idx_equipment_items_service_due
  on public.equipment_items (last_serviced_at)
  where is_deleted = false
    and status <> 'retired'
    and service_interval_days is not null;

create index if not exists idx_equipment_service_logs_equipment
  on public.equipment_service_logs (equipment_id, serviced_at desc);
