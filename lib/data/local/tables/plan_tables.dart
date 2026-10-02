import 'package:drift/drift.dart';

import 'profile_tables.dart';
import 'sync_columns.dart';

/// A reusable workout template, optionally assigned to a member (brain.md §6.6).
///
/// A row with a null [assignedToId] is a template; assigning it copies the
/// template and its exercises, so later edits to the template do not silently
/// rewrite a plan a member is already following. Assigning also snapshots the
/// member's [Profiles.heightCm]/[Profiles.weightKg] at that moment (brain.md
/// §6.11) — a later profile edit must not silently change numbers already
/// shown on a plan the member is following.
class WorkoutPlans extends Table with SyncColumns {
  TextColumn get name => text()();
  TextColumn get description => text().nullable()();

  @ReferenceName('workoutPlansAsAssignee')
  TextColumn get assignedToId =>
      text().nullable().references(Profiles, #id)();
  @ReferenceName('workoutPlansAsCreator')
  TextColumn get createdById => text().nullable().references(Profiles, #id)();

  /// Set when this plan was copied from a template, for provenance.
  TextColumn get templateId => text().nullable()();

  DateTimeColumn get assignedAt => dateTime().nullable()();
  BoolColumn get isTemplate => boolean().withDefault(const Constant(true))();

  /// The member's height/weight at the moment this plan was assigned. Null
  /// for a template (never assigned) or if the member had no metrics
  /// recorded at assignment time.
  IntColumn get snapshotHeightCm => integer().nullable()();
  RealColumn get snapshotWeightKg => real().nullable()();
}

/// One exercise within a workout plan.
class WorkoutExercises extends Table with SyncColumns {
  TextColumn get planId => text().references(WorkoutPlans, #id)();

  TextColumn get name => text()();
  TextColumn get instructions => text().nullable()();
  TextColumn get imageUrl => text().nullable()();

  IntColumn get sets => integer().nullable()();
  IntColumn get reps => integer().nullable()();
  TextColumn get weightNote => text().nullable()();

  /// Optional load expressed as a percentage of the member's bodyweight (e.g.
  /// 50.0 for "50% bodyweight"), additive to [weightNote] — not a replacement
  /// (brain.md §6.11). Displayed as a computed kg figure using the member's
  /// *live current* weight, not the plan's assignment-time snapshot: this
  /// field's whole purpose is "the correct working weight today," which
  /// should track the member's weight as it changes, unlike BMI/calorie
  /// targets which intentionally freeze to the snapshot.
  RealColumn get bodyweightPercent => real().nullable()();

  IntColumn get restSeconds => integer().nullable()();

  /// Day within the plan's week (1–7), or null for an unscheduled exercise.
  IntColumn get dayOfWeek => integer().nullable()();

  /// Display order within the day.
  IntColumn get position => integer().withDefault(const Constant(0))();
}

/// A member ticking off an exercise on a given day (brain.md §6.6).
///
/// Local-first: recorded offline and synced later.
class ExerciseCompletions extends Table with SyncColumns {
  TextColumn get exerciseId => text().references(WorkoutExercises, #id)();
  TextColumn get memberId => text().references(Profiles, #id)();

  /// Date-only, so one completion per exercise per day.
  DateTimeColumn get completedOn => dateTime()();

  IntColumn get setsCompleted => integer().nullable()();
  TextColumn get notes => text().nullable()();
}

/// A diet plan template or assigned plan. Mirrors [WorkoutPlans].
class DietPlans extends Table with SyncColumns {
  TextColumn get name => text()();
  TextColumn get description => text().nullable()();

  /// Legacy: meals as a JSON array, from before [DietMeals]/[DietFoodItems]
  /// existed (brain.md §6.11). Kept, nullable, unused by new plans — every
  /// plan created going forward stores its meals in the structured tables
  /// instead. Old plans are deliberately not migrated (see brain.md §6.11):
  /// their free-text meal lines have no quantity/calorie/macro fields to
  /// migrate into, so a screen reading this plan falls back to decoding this
  /// column only when it has no rows in [DietMeals].
  TextColumn get mealsJson => text().nullable()();

  @ReferenceName('dietPlansAsAssignee')
  TextColumn get assignedToId =>
      text().nullable().references(Profiles, #id)();
  @ReferenceName('dietPlansAsCreator')
  TextColumn get createdById => text().nullable().references(Profiles, #id)();
  TextColumn get templateId => text().nullable()();

  DateTimeColumn get assignedAt => dateTime().nullable()();
  BoolColumn get isTemplate => boolean().withDefault(const Constant(true))();

  /// The member's height/weight at the moment this plan was assigned — see
  /// the matching fields on [WorkoutPlans] for the full rationale.
  IntColumn get snapshotHeightCm => integer().nullable()();
  RealColumn get snapshotWeightKg => real().nullable()();

  /// `sedentary` | `light` | `moderate` | `active` — see `ActivityLevel`.
  /// Staff-selected per plan, used with the snapshot weight/height to compute
  /// a suggested daily calorie target (Mifflin-St Jeor, brain.md §6.11).
  TextColumn get activityLevel => text().nullable()();
}

/// A meal within a diet plan (brain.md §6.11) — replaces [DietPlans.mealsJson]
/// for every plan created going forward.
class DietMeals extends Table with SyncColumns {
  TextColumn get planId => text().references(DietPlans, #id)();
  TextColumn get name => text()();

  /// Free-text ("7:30 AM"), same precedent as `WorkoutExercises.weightNote`:
  /// not worth a dedicated time type for a display-only field.
  TextColumn get time => text().nullable()();

  /// Display order within the plan.
  IntColumn get position => integer().withDefault(const Constant(0))();
}

/// One food item within a [DietMeals] entry.
class DietFoodItems extends Table with SyncColumns {
  TextColumn get mealId => text().references(DietMeals, #id)();
  TextColumn get name => text()();

  /// Free-text serving description ("150g", "1 cup").
  TextColumn get quantity => text().nullable()();

  IntColumn get calories => integer().nullable()();
  RealColumn get proteinG => real().nullable()();
  RealColumn get carbsG => real().nullable()();
  RealColumn get fatG => real().nullable()();

  /// Display order within the meal.
  IntColumn get position => integer().withDefault(const Constant(0))();
}
