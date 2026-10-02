import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/local/daos/plan_dao.dart';
import '../../../data/local/database.dart';
import '../../../shared/providers/database_provider.dart';

final planDaoProvider = Provider<PlanDao>(
  (ref) => ref.watch(databaseProvider).planDao,
);

/// Reusable workout templates (brain.md §6.6).
final workoutTemplatesProvider = StreamProvider<List<WorkoutPlan>>(
  (ref) => ref.watch(planDaoProvider).watchWorkoutTemplates(),
);

/// Reusable diet templates.
final dietTemplatesProvider = StreamProvider<List<DietPlan>>(
  (ref) => ref.watch(planDaoProvider).watchDietTemplates(),
);

/// Exercises in a plan, ordered by day then position.
final planExercisesProvider =
    StreamProvider.family<List<WorkoutExercise>, String>(
      (ref, planId) => ref.watch(planDaoProvider).watchExercises(planId),
    );

/// A member's assigned workout plans.
final assignedWorkoutsProvider =
    StreamProvider.family<List<WorkoutPlan>, String>(
      (ref, memberId) =>
          ref.watch(planDaoProvider).watchAssignedWorkouts(memberId),
    );

/// A member's assigned diet plans.
final assignedDietsProvider = StreamProvider.family<List<DietPlan>, String>(
  (ref, memberId) => ref.watch(planDaoProvider).watchAssignedDiets(memberId),
);

/// Exercise ids the member has ticked off today.
final completedTodayProvider = StreamProvider.family<Set<String>, String>(
  (ref, memberId) =>
      ref.watch(planDaoProvider).watchCompletedOn(memberId: memberId),
);

/// Meals in a diet plan, ordered by position (brain.md §6.11).
final planMealsProvider = StreamProvider.family<List<DietMeal>, String>(
  (ref, planId) => ref.watch(planDaoProvider).watchMeals(planId),
);

/// Food items in a meal, ordered by position.
final mealFoodItemsProvider = StreamProvider.family<List<DietFoodItem>, String>(
  (ref, mealId) => ref.watch(planDaoProvider).watchFoodItems(mealId),
);
