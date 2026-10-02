import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:iron_yard/core/utils/body_metrics.dart';
import 'package:iron_yard/data/local/database.dart';
import 'package:iron_yard/features/plans/models/meal_plan.dart';

void main() {
  late AppDatabase db;
  late String trainerId;
  late String memberId;

  setUp(() async {
    db = AppDatabase.memory();
    trainerId = await db.profileDao.createMember(fullName: 'Trainer');
    memberId = await db.profileDao.createMember(fullName: 'Member');
  });

  tearDown(() async => db.close());

  Future<String> buildTemplate({String name = 'Push Pull Legs'}) async {
    final planId = await db.planDao.createWorkoutPlan(
      name: name,
      description: 'Three day split',
      createdById: trainerId,
    );

    await db.planDao.addExercise(
      planId: planId,
      name: 'Bench Press',
      sets: 4,
      reps: 8,
      dayOfWeek: 1,
      instructions: 'Keep shoulders retracted',
    );
    await db.planDao.addExercise(
      planId: planId,
      name: 'Incline Press',
      sets: 3,
      reps: 10,
      dayOfWeek: 1,
    );
    await db.planDao.addExercise(
      planId: planId,
      name: 'Squat',
      sets: 5,
      reps: 5,
      dayOfWeek: 3,
    );

    return planId;
  }

  group('templates', () {
    test('a new plan is a template', () async {
      final id = await db.planDao.createWorkoutPlan(name: 'Beginner');

      final plan = await db.planDao.workoutPlanById(id);
      expect(plan!.isTemplate, isTrue);
      expect(plan.assignedToId, isNull);
      expect(plan.isDirty, isTrue, reason: 'must sync');
    });

    test('templates are listed, assigned plans are not', () async {
      final templateId = await buildTemplate();
      await db.planDao.assignWorkoutPlan(
        templateId: templateId,
        memberId: memberId,
      );

      final templates = await db.planDao.watchWorkoutTemplates().first;
      expect(templates, hasLength(1));
      expect(templates.single.id, templateId);
    });

    test('deleting a plan also removes its exercises', () async {
      final planId = await buildTemplate();
      await db.planDao.deleteWorkoutPlan(planId);

      expect(await db.planDao.watchWorkoutTemplates().first, isEmpty);
      expect(await db.planDao.exercisesFor(planId), isEmpty);
    });
  });

  group('exercises', () {
    test('are ordered by day, then position', () async {
      final planId = await buildTemplate();

      final exercises = await db.planDao.exercisesFor(planId);

      expect(
        exercises.map((e) => e.name),
        ['Bench Press', 'Incline Press', 'Squat'],
      );
      expect(exercises[0].position, 0);
      expect(exercises[1].position, 1);
      expect(exercises[2].position, 0, reason: 'a new day restarts positions');
    });

    test('appending assigns the next position within its day', () async {
      final planId = await db.planDao.createWorkoutPlan(name: 'P');

      for (var i = 0; i < 3; i++) {
        await db.planDao.addExercise(
          planId: planId,
          name: 'Ex$i',
          dayOfWeek: 2,
        );
      }

      final exercises = await db.planDao.exercisesFor(planId);
      expect(exercises.map((e) => e.position), [0, 1, 2]);
    });

    test('positions are tracked per day, not per plan', () async {
      final planId = await db.planDao.createWorkoutPlan(name: 'P');
      await db.planDao.addExercise(planId: planId, name: 'A', dayOfWeek: 1);
      await db.planDao.addExercise(planId: planId, name: 'B', dayOfWeek: 2);

      final exercises = await db.planDao.exercisesFor(planId);
      expect(exercises.every((e) => e.position == 0), isTrue);
    });

    test('unscheduled exercises get their own position sequence', () async {
      final planId = await db.planDao.createWorkoutPlan(name: 'P');
      await db.planDao.addExercise(planId: planId, name: 'A');
      await db.planDao.addExercise(planId: planId, name: 'B');

      final exercises = await db.planDao.exercisesFor(planId);
      expect(exercises.map((e) => e.position), [0, 1]);
    });

    test('reordering persists', () async {
      final planId = await db.planDao.createWorkoutPlan(name: 'P');
      final a = await db.planDao.addExercise(planId: planId, name: 'A', dayOfWeek: 1);
      final b = await db.planDao.addExercise(planId: planId, name: 'B', dayOfWeek: 1);
      final c = await db.planDao.addExercise(planId: planId, name: 'C', dayOfWeek: 1);

      await db.planDao.reorderExercises([c, a, b]);

      final exercises = await db.planDao.exercisesFor(planId);
      expect(exercises.map((e) => e.name), ['C', 'A', 'B']);
    });

    test('a deleted exercise disappears from the plan', () async {
      final planId = await buildTemplate();
      final exercises = await db.planDao.exercisesFor(planId);

      await db.planDao.deleteExercise(exercises.first.id);

      final remaining = await db.planDao.exercisesFor(planId);
      expect(remaining, hasLength(2));
      expect(remaining.map((e) => e.name), isNot(contains('Bench Press')));
    });

    test('stores an optional bodyweight percentage, additive to weightNote',
        () async {
      final planId = await db.planDao.createWorkoutPlan(name: 'P');
      final id = await db.planDao.addExercise(
        planId: planId,
        name: 'Pull-up',
        weightNote: 'Add band if needed',
        bodyweightPercent: 100,
      );

      final exercise = (await db.planDao.exercisesFor(planId)).firstWhere(
        (e) => e.id == id,
      );
      expect(exercise.weightNote, 'Add band if needed');
      expect(exercise.bodyweightPercent, 100);
    });

    test('updateExercise changes the bodyweight percentage', () async {
      final planId = await db.planDao.createWorkoutPlan(name: 'P');
      final id = await db.planDao.addExercise(planId: planId, name: 'Dip');

      await db.planDao.updateExercise(
        id: id,
        name: 'Dip',
        bodyweightPercent: 75,
      );

      final exercise = (await db.planDao.exercisesFor(planId)).single;
      expect(exercise.bodyweightPercent, 75);
    });
  });

  group('assignment copies the template (brain.md §6.6)', () {
    test('creates a separate plan, not a reference', () async {
      final templateId = await buildTemplate();

      final assignedId = await db.planDao.assignWorkoutPlan(
        templateId: templateId,
        memberId: memberId,
      );

      expect(assignedId, isNot(templateId));

      final assigned = await db.planDao.workoutPlanById(assignedId);
      expect(assigned!.isTemplate, isFalse);
      expect(assigned.assignedToId, memberId);
      expect(assigned.templateId, templateId, reason: 'provenance is kept');
      expect(assigned.assignedAt, isNotNull);
    });

    test('copies every exercise with its details', () async {
      final templateId = await buildTemplate();
      final assignedId = await db.planDao.assignWorkoutPlan(
        templateId: templateId,
        memberId: memberId,
      );

      final copied = await db.planDao.exercisesFor(assignedId);

      expect(copied, hasLength(3));
      expect(copied.first.name, 'Bench Press');
      expect(copied.first.sets, 4);
      expect(copied.first.reps, 8);
      expect(copied.first.instructions, 'Keep shoulders retracted');
      expect(copied.first.dayOfWeek, 1);
    });

    test('copied exercises are distinct rows', () async {
      final templateId = await buildTemplate();
      final assignedId = await db.planDao.assignWorkoutPlan(
        templateId: templateId,
        memberId: memberId,
      );

      final templateIds =
          (await db.planDao.exercisesFor(templateId)).map((e) => e.id).toSet();
      final assignedIds =
          (await db.planDao.exercisesFor(assignedId)).map((e) => e.id).toSet();

      expect(templateIds.intersection(assignedIds), isEmpty);
    });

    test('editing the template does not change an assigned plan', () async {
      // The whole reason for copying: a member mid-programme must not have
      // their plan rewritten under them.
      final templateId = await buildTemplate();
      final assignedId = await db.planDao.assignWorkoutPlan(
        templateId: templateId,
        memberId: memberId,
      );

      await db.planDao.updateWorkoutPlan(
        id: templateId,
        name: 'Renamed Template',
        description: 'Changed',
      );
      final templateExercises = await db.planDao.exercisesFor(templateId);
      await db.planDao.updateExercise(
        id: templateExercises.first.id,
        name: 'Different Exercise',
        sets: 99,
      );

      final assigned = await db.planDao.workoutPlanById(assignedId);
      expect(assigned!.name, 'Push Pull Legs');

      final assignedExercises = await db.planDao.exercisesFor(assignedId);
      expect(assignedExercises.first.name, 'Bench Press');
      expect(assignedExercises.first.sets, 4);
    });

    test('deleting the template does not remove an assigned plan', () async {
      final templateId = await buildTemplate();
      final assignedId = await db.planDao.assignWorkoutPlan(
        templateId: templateId,
        memberId: memberId,
      );

      await db.planDao.deleteWorkoutPlan(templateId);

      final assigned = await db.planDao.workoutPlanById(assignedId);
      expect(assigned!.isDeleted, isFalse);
      expect(await db.planDao.exercisesFor(assignedId), hasLength(3));
    });

    test('assigning an unknown template fails loudly', () async {
      await expectLater(
        db.planDao.assignWorkoutPlan(
          templateId: 'does-not-exist',
          memberId: memberId,
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('copies bodyweight-relative loads onto the assigned copy', () async {
      final planId = await db.planDao.createWorkoutPlan(name: 'P');
      await db.planDao.addExercise(
        planId: planId,
        name: 'Pull-up',
        bodyweightPercent: 100,
      );

      final assignedId = await db.planDao.assignWorkoutPlan(
        templateId: planId,
        memberId: memberId,
      );

      final copied = (await db.planDao.exercisesFor(assignedId)).single;
      expect(copied.bodyweightPercent, 100);
    });

    test('a member can hold several assigned plans', () async {
      final push = await buildTemplate(name: 'Push');
      final pull = await buildTemplate(name: 'Pull');

      await db.planDao.assignWorkoutPlan(
        templateId: push,
        memberId: memberId,
      );
      await db.planDao.assignWorkoutPlan(
        templateId: pull,
        memberId: memberId,
      );

      expect(await db.planDao.assignedWorkoutsFor(memberId), hasLength(2));
    });

    test('assigned plans are scoped to their member', () async {
      final templateId = await buildTemplate();
      final other = await db.profileDao.createMember(fullName: 'Other');

      await db.planDao.assignWorkoutPlan(
        templateId: templateId,
        memberId: memberId,
      );

      expect(await db.planDao.assignedWorkoutsFor(other), isEmpty);
    });
  });

  group('assignment snapshots (brain.md §6.11)', () {
    test('assigning a workout plan snapshots the member\'s height/weight',
        () async {
      await db.profileDao.updateProfile(
        memberId,
        const ProfilesCompanion(
          heightCm: Value(180),
          weightKg: Value(82.5),
        ),
      );
      final templateId = await buildTemplate();

      final assignedId = await db.planDao.assignWorkoutPlan(
        templateId: templateId,
        memberId: memberId,
      );

      final assigned = await db.planDao.workoutPlanById(assignedId);
      expect(assigned!.snapshotHeightCm, 180);
      expect(assigned.snapshotWeightKg, 82.5);
    });

    test('assigning to a member with no metrics leaves the snapshot null',
        () async {
      final templateId = await buildTemplate();

      final assignedId = await db.planDao.assignWorkoutPlan(
        templateId: templateId,
        memberId: memberId,
      );

      final assigned = await db.planDao.workoutPlanById(assignedId);
      expect(assigned!.snapshotHeightCm, isNull);
      expect(assigned.snapshotWeightKg, isNull);
    });

    test('a later profile edit does not change an already-assigned plan\'s '
        'snapshot', () async {
      await db.profileDao.updateProfile(
        memberId,
        const ProfilesCompanion(heightCm: Value(180), weightKg: Value(80)),
      );
      final templateId = await buildTemplate();
      final assignedId = await db.planDao.assignWorkoutPlan(
        templateId: templateId,
        memberId: memberId,
      );

      // The member gains weight after the plan was assigned.
      await db.profileDao.updateProfile(
        memberId,
        const ProfilesCompanion(weightKg: Value(90)),
      );

      final assigned = await db.planDao.workoutPlanById(assignedId);
      expect(
        assigned!.snapshotWeightKg,
        80,
        reason:
            'the snapshot must not silently change under a plan the member '
            'is already following',
      );
    });

    test('assigning a diet plan also snapshots height/weight', () async {
      await db.profileDao.updateProfile(
        memberId,
        const ProfilesCompanion(heightCm: Value(165), weightKg: Value(60)),
      );
      final templateId = await db.planDao.createDietPlan(name: 'Cutting');

      final assignedId = await db.planDao.assignDietPlan(
        templateId: templateId,
        memberId: memberId,
      );

      final assigned = await db.planDao.dietPlanById(assignedId);
      expect(assigned!.snapshotHeightCm, 165);
      expect(assigned.snapshotWeightKg, 60);
    });
  });

  group('exercise completions', () {
    late String exerciseId;

    setUp(() async {
      final planId = await buildTemplate();
      final assignedId = await db.planDao.assignWorkoutPlan(
        templateId: planId,
        memberId: memberId,
      );
      exerciseId = (await db.planDao.exercisesFor(assignedId)).first.id;
    });

    test('toggling on then off', () async {
      expect(
        await db.planDao.toggleCompletion(
          exerciseId: exerciseId,
          memberId: memberId,
        ),
        isTrue,
      );
      expect(
        await db.planDao.completedOn(memberId: memberId),
        contains(exerciseId),
      );

      expect(
        await db.planDao.toggleCompletion(
          exerciseId: exerciseId,
          memberId: memberId,
        ),
        isFalse,
      );
      expect(await db.planDao.completedOn(memberId: memberId), isEmpty);
    });

    test('re-ticking revives the same row rather than inserting', () async {
      // A second insert would violate the unique (exercise, member, day) index.
      await db.planDao.toggleCompletion(
        exerciseId: exerciseId,
        memberId: memberId,
      );
      await db.planDao.toggleCompletion(
        exerciseId: exerciseId,
        memberId: memberId,
      );
      await db.planDao.toggleCompletion(
        exerciseId: exerciseId,
        memberId: memberId,
      );

      expect(
        await db.planDao.completedOn(memberId: memberId),
        contains(exerciseId),
      );

      final raw = await db.select(db.exerciseCompletions).get();
      expect(raw, hasLength(1), reason: 'one row per exercise per day');
    });

    test('un-ticking is soft-deleted so it syncs', () async {
      await db.planDao.toggleCompletion(
        exerciseId: exerciseId,
        memberId: memberId,
      );
      await db.planDao.toggleCompletion(
        exerciseId: exerciseId,
        memberId: memberId,
      );

      final raw = await db.select(db.exerciseCompletions).get();
      expect(raw.single.isDeleted, isTrue);
      expect(
        raw.single.isDirty,
        isTrue,
        reason: 'a hard delete would reappear on the next pull',
      );
    });

    test('completions are per day', () async {
      final yesterday = DateTime.now().subtract(const Duration(days: 1));

      await db.planDao.toggleCompletion(
        exerciseId: exerciseId,
        memberId: memberId,
        on: yesterday,
      );

      expect(
        await db.planDao.completedOn(memberId: memberId, day: yesterday),
        contains(exerciseId),
      );
      expect(
        await db.planDao.completedOn(memberId: memberId),
        isEmpty,
        reason: 'today starts fresh',
      );
    });

    test('completions are per member', () async {
      final other = await db.profileDao.createMember(fullName: 'Other');

      await db.planDao.toggleCompletion(
        exerciseId: exerciseId,
        memberId: memberId,
      );

      expect(await db.planDao.completedOn(memberId: other), isEmpty);
    });

    test('records sets completed', () async {
      await db.planDao.toggleCompletion(
        exerciseId: exerciseId,
        memberId: memberId,
        setsCompleted: 3,
      );

      final raw = await db.select(db.exerciseCompletions).get();
      expect(raw.single.setsCompleted, 3);
    });
  });

  group('diet plans', () {
    test('assignment copies the template', () async {
      final templateId = await db.planDao.createDietPlan(
        name: 'Cutting',
        mealsJson: '[{"meal":"Breakfast","items":["Oats"]}]',
        createdById: trainerId,
      );

      final assignedId = await db.planDao.assignDietPlan(
        templateId: templateId,
        memberId: memberId,
      );

      final assigned = await db.planDao.dietPlanById(assignedId);
      expect(assigned!.isTemplate, isFalse);
      expect(assigned.assignedToId, memberId);
      expect(assigned.templateId, templateId);
      expect(assigned.mealsJson, contains('Oats'));
    });

    test('editing the template does not change an assigned diet', () async {
      final templateId = await db.planDao.createDietPlan(
        name: 'Cutting',
        mealsJson: '["original"]',
      );
      final assignedId = await db.planDao.assignDietPlan(
        templateId: templateId,
        memberId: memberId,
      );

      await db.planDao.updateDietPlan(
        id: templateId,
        name: 'Bulking',
        mealsJson: '["changed"]',
      );

      final assigned = await db.planDao.dietPlanById(assignedId);
      expect(assigned!.name, 'Cutting');
      expect(assigned.mealsJson, '["original"]');
    });

    test('assigning an unknown diet template fails loudly', () async {
      await expectLater(
        db.planDao.assignDietPlan(
          templateId: 'nope',
          memberId: memberId,
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('stores and reads back an activity level', () async {
      final id = await db.planDao.createDietPlan(
        name: 'Cutting',
        activityLevel: ActivityLevel.moderate,
      );

      final plan = await db.planDao.dietPlanById(id);
      expect(plan!.activityLevel, 'moderate');
    });

    test('assigning copies the activity level onto the new plan', () async {
      final templateId = await db.planDao.createDietPlan(
        name: 'Cutting',
        activityLevel: ActivityLevel.active,
      );

      final assignedId = await db.planDao.assignDietPlan(
        templateId: templateId,
        memberId: memberId,
      );

      final assigned = await db.planDao.dietPlanById(assignedId);
      expect(assigned!.activityLevel, 'active');
    });
  });

  group('diet meals and food items (brain.md §6.11)', () {
    late String planId;

    setUp(() async {
      planId = await db.planDao.createDietPlan(name: 'Cutting');
    });

    test('adding a meal appends at the end', () async {
      final a = await db.planDao.addMeal(planId: planId, name: 'Breakfast');
      final b = await db.planDao.addMeal(planId: planId, name: 'Lunch');

      final meals = await db.planDao.mealsFor(planId);
      expect(meals.map((m) => m.id), [a, b]);
      expect(meals.map((m) => m.position), [0, 1]);
    });

    test('updateMeal changes name and time', () async {
      final id = await db.planDao.addMeal(
        planId: planId,
        name: 'Breakfast',
        time: '7 AM',
      );

      await db.planDao.updateMeal(id: id, name: 'Brunch', time: '10 AM');

      final meal = (await db.planDao.mealsFor(planId)).single;
      expect(meal.name, 'Brunch');
      expect(meal.time, '10 AM');
    });

    test('deleteMeal soft-deletes the meal and its food items', () async {
      final mealId = await db.planDao.addMeal(planId: planId, name: 'Lunch');
      await db.planDao.addFoodItem(mealId: mealId, name: 'Rice');

      await db.planDao.deleteMeal(mealId);

      expect(await db.planDao.mealsFor(planId), isEmpty);
      expect(await db.planDao.foodItemsFor(mealId), isEmpty);

      final rawItems = await db.select(db.dietFoodItems).get();
      expect(rawItems.single.isDeleted, isTrue);
    });

    test('reorderMeals persists the new order', () async {
      final a = await db.planDao.addMeal(planId: planId, name: 'A');
      final b = await db.planDao.addMeal(planId: planId, name: 'B');
      final c = await db.planDao.addMeal(planId: planId, name: 'C');

      await db.planDao.reorderMeals([c, a, b]);

      final meals = await db.planDao.mealsFor(planId);
      expect(meals.map((m) => m.name), ['C', 'A', 'B']);
    });

    test('addFoodItem stores quantity and macros', () async {
      final mealId = await db.planDao.addMeal(planId: planId, name: 'Lunch');

      await db.planDao.addFoodItem(
        mealId: mealId,
        name: 'Chicken breast',
        quantity: '150g',
        calories: 250,
        proteinG: 45,
        carbsG: 0,
        fatG: 6,
      );

      final item = (await db.planDao.foodItemsFor(mealId)).single;
      expect(item.name, 'Chicken breast');
      expect(item.quantity, '150g');
      expect(item.calories, 250);
      expect(item.proteinG, 45);
      expect(item.carbsG, 0);
      expect(item.fatG, 6);
    });

    test('updateFoodItem changes fields', () async {
      final mealId = await db.planDao.addMeal(planId: planId, name: 'Lunch');
      final itemId = await db.planDao.addFoodItem(
        mealId: mealId,
        name: 'Rice',
        calories: 200,
      );

      await db.planDao.updateFoodItem(
        id: itemId,
        name: 'Brown rice',
        calories: 180,
      );

      final item = (await db.planDao.foodItemsFor(mealId)).single;
      expect(item.name, 'Brown rice');
      expect(item.calories, 180);
    });

    test('deleteFoodItem removes just that item', () async {
      final mealId = await db.planDao.addMeal(planId: planId, name: 'Lunch');
      final a = await db.planDao.addFoodItem(mealId: mealId, name: 'Rice');
      await db.planDao.addFoodItem(mealId: mealId, name: 'Dal');

      await db.planDao.deleteFoodItem(a);

      final items = await db.planDao.foodItemsFor(mealId);
      expect(items, hasLength(1));
      expect(items.single.name, 'Dal');
    });

    test('reorderFoodItems persists the new order', () async {
      final mealId = await db.planDao.addMeal(planId: planId, name: 'Lunch');
      final a = await db.planDao.addFoodItem(mealId: mealId, name: 'A');
      final b = await db.planDao.addFoodItem(mealId: mealId, name: 'B');

      await db.planDao.reorderFoodItems([b, a]);

      final items = await db.planDao.foodItemsFor(mealId);
      expect(items.map((i) => i.name), ['B', 'A']);
    });

    test('assigning a diet plan copies its meals and food items', () async {
      final mealId = await db.planDao.addMeal(
        planId: planId,
        name: 'Breakfast',
        time: '7 AM',
      );
      await db.planDao.addFoodItem(
        mealId: mealId,
        name: 'Oats',
        quantity: '50g',
        calories: 190,
      );

      final assignedId = await db.planDao.assignDietPlan(
        templateId: planId,
        memberId: memberId,
      );

      final copiedMeals = await db.planDao.mealsFor(assignedId);
      expect(copiedMeals, hasLength(1));
      expect(copiedMeals.single.id, isNot(mealId));
      expect(copiedMeals.single.name, 'Breakfast');

      final copiedItems = await db.planDao.foodItemsFor(copiedMeals.single.id);
      expect(copiedItems, hasLength(1));
      expect(copiedItems.single.name, 'Oats');
      expect(copiedItems.single.calories, 190);
    });

    test('editing the template\'s meals does not change an assigned plan',
        () async {
      final mealId = await db.planDao.addMeal(planId: planId, name: 'Lunch');
      await db.planDao.addFoodItem(mealId: mealId, name: 'Rice');

      final assignedId = await db.planDao.assignDietPlan(
        templateId: planId,
        memberId: memberId,
      );

      await db.planDao.addMeal(planId: planId, name: 'Added later');

      final assignedMeals = await db.planDao.mealsFor(assignedId);
      expect(assignedMeals, hasLength(1));
      expect(assignedMeals.single.name, 'Lunch');
    });

    test('deleteDietPlan cascades to meals and food items', () async {
      final mealId = await db.planDao.addMeal(planId: planId, name: 'Lunch');
      await db.planDao.addFoodItem(mealId: mealId, name: 'Rice');

      await db.planDao.deleteDietPlan(planId);

      expect(await db.planDao.mealsFor(planId), isEmpty);
      expect(await db.planDao.foodItemsFor(mealId), isEmpty);
    });
  });

  group('MealPlan', () {
    test('round-trips meals', () {
      const meals = [
        Meal(name: 'Breakfast', items: ['Oats', 'Eggs']),
        Meal(name: 'Lunch', items: ['Rice', 'Dal']),
      ];

      final decoded = MealPlan.decode(MealPlan.encode(meals));

      expect(decoded, hasLength(2));
      expect(decoded.first.name, 'Breakfast');
      expect(decoded.first.items, ['Oats', 'Eggs']);
    });

    test('encodes an empty list as null rather than "[]"', () {
      expect(MealPlan.encode(const []), isNull);
    });

    test('a meal with no items survives', () {
      final decoded = MealPlan.decode(
        MealPlan.encode(const [Meal(name: 'Snack', items: [])]),
      );
      expect(decoded.single.items, isEmpty);
    });

    group('tolerates bad stored content', () {
      // A plan written by an older version, or corrupted in transit, must show
      // as empty rather than crashing the member's plan screen.
      final cases = <String, String?>{
        'null': null,
        'empty string': '',
        'malformed JSON': '[{"meal":',
        'a JSON object': '{"meal":"Breakfast"}',
        'a JSON scalar': '42',
        'a list of scalars': '[1,2,3]',
      };

      cases.forEach((label, json) {
        test(label, () => expect(MealPlan.decode(json), isEmpty));
      });
    });

    test('skips malformed entries but keeps valid ones', () {
      final decoded = MealPlan.decode(
        '[{"meal":"Good","items":["A"]},{"no_meal":true},'
        '{"meal":"","items":[]},{"meal":"Also Good","items":[]}]',
      );

      expect(decoded.map((m) => m.name), ['Good', 'Also Good']);
    });

    test('drops non-string items', () {
      final decoded = MealPlan.decode('[{"meal":"Mixed","items":["A",1,null]}]');
      expect(decoded.single.items, ['A']);
    });

    test('tolerates a missing items field', () {
      final decoded = MealPlan.decode('[{"meal":"Just a name"}]');
      expect(decoded.single.name, 'Just a name');
      expect(decoded.single.items, isEmpty);
    });
  });
}
