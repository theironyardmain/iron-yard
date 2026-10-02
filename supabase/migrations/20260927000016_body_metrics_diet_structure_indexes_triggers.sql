-- The Iron Yard — diet meals/food-items indexes and updated_at triggers

drop trigger if exists set_updated_at on public.diet_meals;
create trigger set_updated_at before insert or update on public.diet_meals
  for each row execute function public.set_updated_at();

drop trigger if exists set_updated_at on public.diet_food_items;
create trigger set_updated_at before insert or update on public.diet_food_items
  for each row execute function public.set_updated_at();

create index if not exists idx_diet_meals_updated_at
  on public.diet_meals (updated_at);
create index if not exists idx_diet_meals_plan
  on public.diet_meals (plan_id, position);

create index if not exists idx_diet_food_items_updated_at
  on public.diet_food_items (updated_at);
create index if not exists idx_diet_food_items_meal
  on public.diet_food_items (meal_id, position);
