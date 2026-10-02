-- The Iron Yard — body metrics, plan snapshots, and structured diet plans
-- (brain.md §6.11)

alter table public.profiles add column if not exists height_cm integer;
alter table public.profiles add column if not exists weight_kg numeric(5,1);

alter table public.workout_plans add column if not exists snapshot_height_cm integer;
alter table public.workout_plans add column if not exists snapshot_weight_kg numeric(5,1);

alter table public.diet_plans add column if not exists snapshot_height_cm integer;
alter table public.diet_plans add column if not exists snapshot_weight_kg numeric(5,1);
alter table public.diet_plans add column if not exists activity_level text
  check (activity_level in ('sedentary', 'light', 'moderate', 'active'));

alter table public.workout_exercises add column if not exists bodyweight_percent numeric(5,1);

comment on column public.workout_exercises.bodyweight_percent is
  'Optional load as a percentage of the member''s bodyweight, additive to '
  'weight_note — never a replacement (brain.md §6.11).';

comment on column public.diet_plans.meals_json is
  'Legacy: meals as a JSON array, from before diet_meals/diet_food_items '
  'existed. Kept, nullable, unused by new plans — old plans are '
  'deliberately not migrated (brain.md §6.11).';

create table if not exists public.diet_meals (
  id         uuid primary key,
  plan_id    uuid not null references public.diet_plans (id) on delete cascade,
  name       text not null,
  time       text,
  position   integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  is_deleted boolean not null default false
);

create table if not exists public.diet_food_items (
  id         uuid primary key,
  meal_id    uuid not null references public.diet_meals (id) on delete cascade,
  name       text not null,
  quantity   text,
  calories   integer check (calories >= 0),
  protein_g  numeric(6,1) check (protein_g >= 0),
  carbs_g    numeric(6,1) check (carbs_g >= 0),
  fat_g      numeric(6,1) check (fat_g >= 0),
  position   integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  is_deleted boolean not null default false
);
