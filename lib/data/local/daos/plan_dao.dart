import 'package:drift/drift.dart';

import '../../../core/utils/body_metrics.dart';
import '../database.dart';
import '../tables/plan_tables.dart';
import 'synced_dao.dart';

part 'plan_dao.g.dart';

/// Workout and diet plans (brain.md §6.6, §6.11).
@DriftAccessor(
  tables: [
    WorkoutPlans,
    WorkoutExercises,
    ExerciseCompletions,
    DietPlans,
    DietMeals,
    DietFoodItems,
  ],
)
class PlanDao extends DatabaseAccessor<AppDatabase>
    with _$PlanDaoMixin, SyncedDaoMixin<AppDatabase, $WorkoutPlansTable, WorkoutPlan> {
  PlanDao(super.db);

  @override
  $WorkoutPlansTable get table => workoutPlans;

  // --- Workout templates ---

  Stream<List<WorkoutPlan>> watchWorkoutTemplates() {
    return (select(workoutPlans)
          ..where((t) => t.isTemplate.equals(true) & t.isDeleted.equals(false))
          ..orderBy([(t) => OrderingTerm.asc(t.name)]))
        .watch();
  }

  Future<WorkoutPlan?> workoutPlanById(String id) {
    return (select(workoutPlans)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
  }

  Future<String> createWorkoutPlan({
    required String name,
    String? description,
    String? createdById,
  }) async {
    final id = Uuid.v4();
    await into(workoutPlans).insert(
      WorkoutPlansCompanion.insert(
        id: id,
        name: name,
        description: Value(description),
        createdById: Value(createdById),
        updatedAt: Value(DateTime.now()),
        isDirty: const Value(true),
      ),
    );
    return id;
  }

  Future<void> updateWorkoutPlan({
    required String id,
    required String name,
    String? description,
  }) async {
    await (update(workoutPlans)..where((t) => t.id.equals(id))).write(
      WorkoutPlansCompanion(
        name: Value(name),
        description: Value(description),
        updatedAt: Value(DateTime.now()),
        isDirty: const Value(true),
      ),
    );
  }

  /// Soft-deletes a plan and its exercises.
  Future<void> deleteWorkoutPlan(String id) async {
    await transaction(() async {
      final now = DateTime.now();

      await (update(workoutExercises)..where((t) => t.planId.equals(id))).write(
        WorkoutExercisesCompanion(
          isDeleted: const Value(true),
          updatedAt: Value(now),
          isDirty: const Value(true),
        ),
      );
      await (update(workoutPlans)..where((t) => t.id.equals(id))).write(
        WorkoutPlansCompanion(
          isDeleted: const Value(true),
          updatedAt: Value(now),
          isDirty: const Value(true),
        ),
      );
    });
  }

  // --- Exercises ---

  Stream<List<WorkoutExercise>> watchExercises(String planId) {
    return (select(workoutExercises)
          ..where((t) => t.planId.equals(planId) & t.isDeleted.equals(false))
          ..orderBy([
            (t) => OrderingTerm.asc(t.dayOfWeek),
            (t) => OrderingTerm.asc(t.position),
          ]))
        .watch();
  }

  Future<List<WorkoutExercise>> exercisesFor(String planId) {
    return (select(workoutExercises)
          ..where((t) => t.planId.equals(planId) & t.isDeleted.equals(false))
          ..orderBy([
            (t) => OrderingTerm.asc(t.dayOfWeek),
            (t) => OrderingTerm.asc(t.position),
          ]))
        .get();
  }

  Future<String> addExercise({
    required String planId,
    required String name,
    String? instructions,
    int? sets,
    int? reps,
    String? weightNote,
    double? bodyweightPercent,
    int? restSeconds,
    int? dayOfWeek,
    int? position,
  }) async {
    final id = Uuid.v4();

    // Append to the end of the day when no position is given.
    final resolvedPosition = position ?? await _nextPosition(planId, dayOfWeek);

    await into(workoutExercises).insert(
      WorkoutExercisesCompanion.insert(
        id: id,
        planId: planId,
        name: name,
        instructions: Value(instructions),
        sets: Value(sets),
        reps: Value(reps),
        weightNote: Value(weightNote),
        bodyweightPercent: Value(bodyweightPercent),
        restSeconds: Value(restSeconds),
        dayOfWeek: Value(dayOfWeek),
        position: Value(resolvedPosition),
        updatedAt: Value(DateTime.now()),
        isDirty: const Value(true),
      ),
    );
    return id;
  }

  Future<int> _nextPosition(String planId, int? dayOfWeek) async {
    final highest = workoutExercises.position.max();
    final query = selectOnly(workoutExercises)
      ..addColumns([highest])
      ..where(
        workoutExercises.planId.equals(planId) &
            workoutExercises.isDeleted.equals(false) &
            (dayOfWeek == null
                ? workoutExercises.dayOfWeek.isNull()
                : workoutExercises.dayOfWeek.equals(dayOfWeek)),
      );

    final current = (await query.getSingle()).read(highest);
    return (current ?? -1) + 1;
  }

  Future<void> updateExercise({
    required String id,
    required String name,
    String? instructions,
    int? sets,
    int? reps,
    String? weightNote,
    double? bodyweightPercent,
    int? restSeconds,
    int? dayOfWeek,
  }) async {
    await (update(workoutExercises)..where((t) => t.id.equals(id))).write(
      WorkoutExercisesCompanion(
        name: Value(name),
        instructions: Value(instructions),
        sets: Value(sets),
        reps: Value(reps),
        weightNote: Value(weightNote),
        bodyweightPercent: Value(bodyweightPercent),
        restSeconds: Value(restSeconds),
        dayOfWeek: Value(dayOfWeek),
        updatedAt: Value(DateTime.now()),
        isDirty: const Value(true),
      ),
    );
  }

  Future<void> deleteExercise(String id) async {
    await (update(workoutExercises)..where((t) => t.id.equals(id))).write(
      WorkoutExercisesCompanion(
        isDeleted: const Value(true),
        updatedAt: Value(DateTime.now()),
        isDirty: const Value(true),
      ),
    );
  }

  /// Persists a reordering within a day.
  Future<void> reorderExercises(List<String> orderedIds) async {
    await transaction(() async {
      final now = DateTime.now();
      for (var i = 0; i < orderedIds.length; i++) {
        await (update(workoutExercises)
              ..where((t) => t.id.equals(orderedIds[i])))
            .write(
              WorkoutExercisesCompanion(
                position: Value(i),
                updatedAt: Value(now),
                isDirty: const Value(true),
              ),
            );
      }
    });
  }

  // --- Assignment ---

  /// Assigns a workout template to a member by **copying** it.
  ///
  /// The copy is deliberate (brain.md §6.6): if the assignment referenced the
  /// template, a later edit would silently rewrite the plan a member is already
  /// following, mid-programme. [templateId] records where the copy came from.
  ///
  /// Also snapshots the member's current height/weight (brain.md §6.11): a
  /// later profile edit must not silently change the numbers already shown on
  /// a plan the member is following.
  Future<String> assignWorkoutPlan({
    required String templateId,
    required String memberId,
    String? assignedById,
  }) async {
    return transaction(() async {
      final template = await workoutPlanById(templateId);
      if (template == null) {
        throw StateError('Workout template $templateId not found');
      }
      final member = await _profileFor(memberId);

      final planId = Uuid.v4();
      final now = DateTime.now();

      await into(workoutPlans).insert(
        WorkoutPlansCompanion.insert(
          id: planId,
          name: template.name,
          description: Value(template.description),
          assignedToId: Value(memberId),
          createdById: Value(assignedById ?? template.createdById),
          templateId: Value(templateId),
          assignedAt: Value(now),
          isTemplate: const Value(false),
          snapshotHeightCm: Value(member?.heightCm),
          snapshotWeightKg: Value(member?.weightKg),
          updatedAt: Value(now),
          isDirty: const Value(true),
        ),
      );

      for (final exercise in await exercisesFor(templateId)) {
        await into(workoutExercises).insert(
          WorkoutExercisesCompanion.insert(
            id: Uuid.v4(),
            planId: planId,
            name: exercise.name,
            instructions: Value(exercise.instructions),
            imageUrl: Value(exercise.imageUrl),
            sets: Value(exercise.sets),
            reps: Value(exercise.reps),
            weightNote: Value(exercise.weightNote),
            bodyweightPercent: Value(exercise.bodyweightPercent),
            restSeconds: Value(exercise.restSeconds),
            dayOfWeek: Value(exercise.dayOfWeek),
            position: Value(exercise.position),
            updatedAt: Value(now),
            isDirty: const Value(true),
          ),
        );
      }

      return planId;
    });
  }

  /// Reads a member's profile row directly (no `ProfileDao` dependency, to
  /// keep DAOs single-table-focused — cross-domain reads like this stay small
  /// enough to inline rather than justifying a cross-DAO wiring).
  Future<Profile?> _profileFor(String memberId) {
    return (db.select(
      db.profiles,
    )..where((t) => t.id.equals(memberId))).getSingleOrNull();
  }

  /// A member's assigned workout plans, newest first.
  Stream<List<WorkoutPlan>> watchAssignedWorkouts(String memberId) {
    return (select(workoutPlans)
          ..where(
            (t) =>
                t.assignedToId.equals(memberId) &
                t.isTemplate.equals(false) &
                t.isDeleted.equals(false),
          )
          ..orderBy([(t) => OrderingTerm.desc(t.assignedAt)]))
        .watch();
  }

  Future<List<WorkoutPlan>> assignedWorkoutsFor(String memberId) {
    return (select(workoutPlans)
          ..where(
            (t) =>
                t.assignedToId.equals(memberId) &
                t.isTemplate.equals(false) &
                t.isDeleted.equals(false),
          )
          ..orderBy([(t) => OrderingTerm.desc(t.assignedAt)]))
        .get();
  }

  // --- Exercise completions ---

  /// Marks an exercise done for a day, or clears it if already marked.
  ///
  /// Returns true when the exercise is now complete.
  Future<bool> toggleCompletion({
    required String exerciseId,
    required String memberId,
    DateTime? on,
    int? setsCompleted,
  }) async {
    final day = DayKey.of(on);

    return transaction(() async {
      final existing = await (select(exerciseCompletions)
            ..where(
              (t) =>
                  t.exerciseId.equals(exerciseId) &
                  t.memberId.equals(memberId) &
                  t.completedOn.equals(day),
            )
            ..limit(1))
          .getSingleOrNull();

      if (existing != null) {
        if (!existing.isDeleted) {
          // Soft-delete rather than removing, so the un-tick syncs to the
          // server instead of silently reappearing on the next pull.
          await (update(exerciseCompletions)
                ..where((t) => t.id.equals(existing.id)))
              .write(
                ExerciseCompletionsCompanion(
                  isDeleted: const Value(true),
                  updatedAt: Value(DateTime.now()),
                  isDirty: const Value(true),
                ),
              );
          return false;
        }

        // Re-ticking a previously cleared entry revives the same row, so the
        // unique index on (exercise, member, day) is not violated.
        await (update(exerciseCompletions)
              ..where((t) => t.id.equals(existing.id)))
            .write(
              ExerciseCompletionsCompanion(
                isDeleted: const Value(false),
                setsCompleted: Value(setsCompleted),
                updatedAt: Value(DateTime.now()),
                isDirty: const Value(true),
              ),
            );
        return true;
      }

      await into(exerciseCompletions).insert(
        ExerciseCompletionsCompanion.insert(
          id: Uuid.v4(),
          exerciseId: exerciseId,
          memberId: memberId,
          completedOn: day,
          setsCompleted: Value(setsCompleted),
          updatedAt: Value(DateTime.now()),
          isDirty: const Value(true),
        ),
      );
      return true;
    });
  }

  /// Exercise ids the member completed on a given day.
  Future<Set<String>> completedOn({
    required String memberId,
    DateTime? day,
  }) async {
    final target = DayKey.of(day);
    final rows =
        await (select(exerciseCompletions)..where(
              (t) =>
                  t.memberId.equals(memberId) &
                  t.completedOn.equals(target) &
                  t.isDeleted.equals(false),
            ))
            .get();

    return rows.map((r) => r.exerciseId).toSet();
  }

  Stream<Set<String>> watchCompletedOn({
    required String memberId,
    DateTime? day,
  }) {
    final target = DayKey.of(day);
    return (select(exerciseCompletions)..where(
          (t) =>
              t.memberId.equals(memberId) &
              t.completedOn.equals(target) &
              t.isDeleted.equals(false),
        ))
        .watch()
        .map((rows) => rows.map((r) => r.exerciseId).toSet());
  }

  // --- Diet plans ---

  Stream<List<DietPlan>> watchDietTemplates() {
    return (select(dietPlans)
          ..where((t) => t.isTemplate.equals(true) & t.isDeleted.equals(false))
          ..orderBy([(t) => OrderingTerm.asc(t.name)]))
        .watch();
  }

  Future<DietPlan?> dietPlanById(String id) {
    return (select(dietPlans)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
  }

  Future<String> createDietPlan({
    required String name,
    String? description,
    String? mealsJson,
    String? createdById,
    ActivityLevel? activityLevel,
  }) async {
    final id = Uuid.v4();
    await into(dietPlans).insert(
      DietPlansCompanion.insert(
        id: id,
        name: name,
        description: Value(description),
        mealsJson: Value(mealsJson),
        createdById: Value(createdById),
        activityLevel: Value(activityLevel?.wireValue),
        updatedAt: Value(DateTime.now()),
        isDirty: const Value(true),
      ),
    );
    return id;
  }

  Future<void> updateDietPlan({
    required String id,
    required String name,
    String? description,
    String? mealsJson,
    ActivityLevel? activityLevel,
  }) async {
    await (update(dietPlans)..where((t) => t.id.equals(id))).write(
      DietPlansCompanion(
        name: Value(name),
        description: Value(description),
        mealsJson: Value(mealsJson),
        activityLevel: Value(activityLevel?.wireValue),
        updatedAt: Value(DateTime.now()),
        isDirty: const Value(true),
      ),
    );
  }

  /// Soft-deletes a diet plan and its meals/food items.
  Future<void> deleteDietPlan(String id) async {
    await transaction(() async {
      final now = DateTime.now();

      for (final meal in await mealsFor(id)) {
        await (update(dietFoodItems)..where((t) => t.mealId.equals(meal.id)))
            .write(
              DietFoodItemsCompanion(
                isDeleted: const Value(true),
                updatedAt: Value(now),
                isDirty: const Value(true),
              ),
            );
      }
      await (update(dietMeals)..where((t) => t.planId.equals(id))).write(
        DietMealsCompanion(
          isDeleted: const Value(true),
          updatedAt: Value(now),
          isDirty: const Value(true),
        ),
      );
      await (update(dietPlans)..where((t) => t.id.equals(id))).write(
        DietPlansCompanion(
          isDeleted: const Value(true),
          updatedAt: Value(now),
          isDirty: const Value(true),
        ),
      );
    });
  }

  /// Assigns a diet template to a member by copying it (plan, meals, and food
  /// items), as with workouts. Also snapshots the member's current height/
  /// weight (brain.md §6.11) — see `assignWorkoutPlan` for the full rationale.
  Future<String> assignDietPlan({
    required String templateId,
    required String memberId,
    String? assignedById,
  }) async {
    return transaction(() async {
      final template = await dietPlanById(templateId);
      if (template == null) {
        throw StateError('Diet template $templateId not found');
      }
      final member = await _profileFor(memberId);

      final planId = Uuid.v4();
      final now = DateTime.now();

      await into(dietPlans).insert(
        DietPlansCompanion.insert(
          id: planId,
          name: template.name,
          description: Value(template.description),
          mealsJson: Value(template.mealsJson),
          assignedToId: Value(memberId),
          createdById: Value(assignedById ?? template.createdById),
          templateId: Value(templateId),
          assignedAt: Value(now),
          isTemplate: const Value(false),
          snapshotHeightCm: Value(member?.heightCm),
          snapshotWeightKg: Value(member?.weightKg),
          activityLevel: Value(template.activityLevel),
          updatedAt: Value(now),
          isDirty: const Value(true),
        ),
      );

      for (final meal in await mealsFor(templateId)) {
        final newMealId = Uuid.v4();
        await into(dietMeals).insert(
          DietMealsCompanion.insert(
            id: newMealId,
            planId: planId,
            name: meal.name,
            time: Value(meal.time),
            position: Value(meal.position),
            updatedAt: Value(now),
            isDirty: const Value(true),
          ),
        );

        for (final item in await foodItemsFor(meal.id)) {
          await into(dietFoodItems).insert(
            DietFoodItemsCompanion.insert(
              id: Uuid.v4(),
              mealId: newMealId,
              name: item.name,
              quantity: Value(item.quantity),
              calories: Value(item.calories),
              proteinG: Value(item.proteinG),
              carbsG: Value(item.carbsG),
              fatG: Value(item.fatG),
              position: Value(item.position),
              updatedAt: Value(now),
              isDirty: const Value(true),
            ),
          );
        }
      }

      return planId;
    });
  }

  // --- Diet meals ---

  Stream<List<DietMeal>> watchMeals(String planId) {
    return (select(dietMeals)
          ..where((t) => t.planId.equals(planId) & t.isDeleted.equals(false))
          ..orderBy([(t) => OrderingTerm.asc(t.position)]))
        .watch();
  }

  Future<List<DietMeal>> mealsFor(String planId) {
    return (select(dietMeals)
          ..where((t) => t.planId.equals(planId) & t.isDeleted.equals(false))
          ..orderBy([(t) => OrderingTerm.asc(t.position)]))
        .get();
  }

  Future<String> addMeal({
    required String planId,
    required String name,
    String? time,
    int? position,
  }) async {
    final id = Uuid.v4();
    final resolvedPosition = position ?? await _nextMealPosition(planId);

    await into(dietMeals).insert(
      DietMealsCompanion.insert(
        id: id,
        planId: planId,
        name: name,
        time: Value(time),
        position: Value(resolvedPosition),
        updatedAt: Value(DateTime.now()),
        isDirty: const Value(true),
      ),
    );
    return id;
  }

  Future<int> _nextMealPosition(String planId) async {
    final highest = dietMeals.position.max();
    final query = selectOnly(dietMeals)
      ..addColumns([highest])
      ..where(
        dietMeals.planId.equals(planId) & dietMeals.isDeleted.equals(false),
      );

    final current = (await query.getSingle()).read(highest);
    return (current ?? -1) + 1;
  }

  Future<void> updateMeal({
    required String id,
    required String name,
    String? time,
  }) async {
    await (update(dietMeals)..where((t) => t.id.equals(id))).write(
      DietMealsCompanion(
        name: Value(name),
        time: Value(time),
        updatedAt: Value(DateTime.now()),
        isDirty: const Value(true),
      ),
    );
  }

  /// Soft-deletes a meal and its food items.
  Future<void> deleteMeal(String id) async {
    await transaction(() async {
      final now = DateTime.now();
      await (update(dietFoodItems)..where((t) => t.mealId.equals(id))).write(
        DietFoodItemsCompanion(
          isDeleted: const Value(true),
          updatedAt: Value(now),
          isDirty: const Value(true),
        ),
      );
      await (update(dietMeals)..where((t) => t.id.equals(id))).write(
        DietMealsCompanion(
          isDeleted: const Value(true),
          updatedAt: Value(now),
          isDirty: const Value(true),
        ),
      );
    });
  }

  Future<void> reorderMeals(List<String> orderedIds) async {
    await transaction(() async {
      final now = DateTime.now();
      for (var i = 0; i < orderedIds.length; i++) {
        await (update(dietMeals)..where((t) => t.id.equals(orderedIds[i])))
            .write(
              DietMealsCompanion(
                position: Value(i),
                updatedAt: Value(now),
                isDirty: const Value(true),
              ),
            );
      }
    });
  }

  // --- Diet food items ---

  Stream<List<DietFoodItem>> watchFoodItems(String mealId) {
    return (select(dietFoodItems)
          ..where((t) => t.mealId.equals(mealId) & t.isDeleted.equals(false))
          ..orderBy([(t) => OrderingTerm.asc(t.position)]))
        .watch();
  }

  Future<List<DietFoodItem>> foodItemsFor(String mealId) {
    return (select(dietFoodItems)
          ..where((t) => t.mealId.equals(mealId) & t.isDeleted.equals(false))
          ..orderBy([(t) => OrderingTerm.asc(t.position)]))
        .get();
  }

  Future<String> addFoodItem({
    required String mealId,
    required String name,
    String? quantity,
    int? calories,
    double? proteinG,
    double? carbsG,
    double? fatG,
    int? position,
  }) async {
    final id = Uuid.v4();
    final resolvedPosition = position ?? await _nextFoodItemPosition(mealId);

    await into(dietFoodItems).insert(
      DietFoodItemsCompanion.insert(
        id: id,
        mealId: mealId,
        name: name,
        quantity: Value(quantity),
        calories: Value(calories),
        proteinG: Value(proteinG),
        carbsG: Value(carbsG),
        fatG: Value(fatG),
        position: Value(resolvedPosition),
        updatedAt: Value(DateTime.now()),
        isDirty: const Value(true),
      ),
    );
    return id;
  }

  Future<int> _nextFoodItemPosition(String mealId) async {
    final highest = dietFoodItems.position.max();
    final query = selectOnly(dietFoodItems)
      ..addColumns([highest])
      ..where(
        dietFoodItems.mealId.equals(mealId) &
            dietFoodItems.isDeleted.equals(false),
      );

    final current = (await query.getSingle()).read(highest);
    return (current ?? -1) + 1;
  }

  Future<void> updateFoodItem({
    required String id,
    required String name,
    String? quantity,
    int? calories,
    double? proteinG,
    double? carbsG,
    double? fatG,
  }) async {
    await (update(dietFoodItems)..where((t) => t.id.equals(id))).write(
      DietFoodItemsCompanion(
        name: Value(name),
        quantity: Value(quantity),
        calories: Value(calories),
        proteinG: Value(proteinG),
        carbsG: Value(carbsG),
        fatG: Value(fatG),
        updatedAt: Value(DateTime.now()),
        isDirty: const Value(true),
      ),
    );
  }

  Future<void> deleteFoodItem(String id) async {
    await (update(dietFoodItems)..where((t) => t.id.equals(id))).write(
      DietFoodItemsCompanion(
        isDeleted: const Value(true),
        updatedAt: Value(DateTime.now()),
        isDirty: const Value(true),
      ),
    );
  }

  Future<void> reorderFoodItems(List<String> orderedIds) async {
    await transaction(() async {
      final now = DateTime.now();
      for (var i = 0; i < orderedIds.length; i++) {
        await (update(dietFoodItems)
              ..where((t) => t.id.equals(orderedIds[i])))
            .write(
              DietFoodItemsCompanion(
                position: Value(i),
                updatedAt: Value(now),
                isDirty: const Value(true),
              ),
            );
      }
    });
  }

  Stream<List<DietPlan>> watchAssignedDiets(String memberId) {
    return (select(dietPlans)
          ..where(
            (t) =>
                t.assignedToId.equals(memberId) &
                t.isTemplate.equals(false) &
                t.isDeleted.equals(false),
          )
          ..orderBy([(t) => OrderingTerm.desc(t.assignedAt)]))
        .watch();
  }

  Future<List<DietPlan>> assignedDietsFor(String memberId) {
    return (select(dietPlans)
          ..where(
            (t) =>
                t.assignedToId.equals(memberId) &
                t.isTemplate.equals(false) &
                t.isDeleted.equals(false),
          )
          ..orderBy([(t) => OrderingTerm.desc(t.assignedAt)]))
        .get();
  }
}
