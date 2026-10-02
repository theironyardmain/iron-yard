// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'plan_dao.dart';

// ignore_for_file: type=lint
mixin _$PlanDaoMixin on DatabaseAccessor<AppDatabase> {
  $ProfilesTable get profiles => attachedDatabase.profiles;
  $WorkoutPlansTable get workoutPlans => attachedDatabase.workoutPlans;
  $WorkoutExercisesTable get workoutExercises =>
      attachedDatabase.workoutExercises;
  $ExerciseCompletionsTable get exerciseCompletions =>
      attachedDatabase.exerciseCompletions;
  $DietPlansTable get dietPlans => attachedDatabase.dietPlans;
  $DietMealsTable get dietMeals => attachedDatabase.dietMeals;
  $DietFoodItemsTable get dietFoodItems => attachedDatabase.dietFoodItems;
  PlanDaoManager get managers => PlanDaoManager(this);
}

class PlanDaoManager {
  final _$PlanDaoMixin _db;
  PlanDaoManager(this._db);
  $$ProfilesTableTableManager get profiles =>
      $$ProfilesTableTableManager(_db.attachedDatabase, _db.profiles);
  $$WorkoutPlansTableTableManager get workoutPlans =>
      $$WorkoutPlansTableTableManager(_db.attachedDatabase, _db.workoutPlans);
  $$WorkoutExercisesTableTableManager get workoutExercises =>
      $$WorkoutExercisesTableTableManager(
        _db.attachedDatabase,
        _db.workoutExercises,
      );
  $$ExerciseCompletionsTableTableManager get exerciseCompletions =>
      $$ExerciseCompletionsTableTableManager(
        _db.attachedDatabase,
        _db.exerciseCompletions,
      );
  $$DietPlansTableTableManager get dietPlans =>
      $$DietPlansTableTableManager(_db.attachedDatabase, _db.dietPlans);
  $$DietMealsTableTableManager get dietMeals =>
      $$DietMealsTableTableManager(_db.attachedDatabase, _db.dietMeals);
  $$DietFoodItemsTableTableManager get dietFoodItems =>
      $$DietFoodItemsTableTableManager(_db.attachedDatabase, _db.dietFoodItems);
}
