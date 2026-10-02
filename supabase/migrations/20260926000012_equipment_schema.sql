-- The Iron Yard — equipment inventory and service history (brain.md §6.10)

create table if not exists public.equipment_items (
  id                     uuid primary key,
  name                   text not null,
  category               text,
  quantity               integer not null default 1 check (quantity >= 1),
  location               text,
  purchase_date          timestamptz,
  -- Smallest currency unit (paise). Integer, not numeric/float.
  cost_minor             integer check (cost_minor >= 0),
  status                 text not null default 'working'
                           check (status in ('working', 'under_repair', 'retired')),
  service_interval_days  integer check (service_interval_days > 0),
  last_serviced_at       timestamptz,
  notes                  text,
  created_at             timestamptz not null default now(),
  updated_at             timestamptz not null default now(),
  is_deleted             boolean not null default false
);

create table if not exists public.equipment_service_logs (
  id           uuid primary key,
  equipment_id uuid not null references public.equipment_items (id) on delete cascade,
  serviced_at  timestamptz not null,
  description  text not null,
  cost_minor   integer check (cost_minor >= 0),
  performed_by uuid references public.profiles (id) on delete set null,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  is_deleted   boolean not null default false
);
