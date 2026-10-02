-- The Iron Yard — RLS for diet_meals/diet_food_items (brain.md §6.11)
--
-- Same shape as workout_exercises: a member reads meals/items on a diet plan
-- assigned to them; staff read and write everything.

alter table public.diet_meals enable row level security;
alter table public.diet_meals force row level security;

drop policy if exists diet_meals_select on public.diet_meals;
create policy diet_meals_select on public.diet_meals
  for select using (
    public.is_staff()
    or exists (
      select 1 from public.diet_plans p
       where p.id = plan_id and p.assigned_to_id = auth.uid()
    )
  );

drop policy if exists diet_meals_write on public.diet_meals;
create policy diet_meals_write on public.diet_meals
  for all using (public.is_staff()) with check (public.is_staff());

alter table public.diet_food_items enable row level security;
alter table public.diet_food_items force row level security;

drop policy if exists diet_food_items_select on public.diet_food_items;
create policy diet_food_items_select on public.diet_food_items
  for select using (
    public.is_staff()
    or exists (
      select 1
        from public.diet_meals m
        join public.diet_plans p on p.id = m.plan_id
       where m.id = meal_id and p.assigned_to_id = auth.uid()
    )
  );

drop policy if exists diet_food_items_write on public.diet_food_items;
create policy diet_food_items_write on public.diet_food_items
  for all using (public.is_staff()) with check (public.is_staff());

grant select, insert, update, delete on public.diet_meals to authenticated;
grant select, insert, update, delete on public.diet_food_items to authenticated;
