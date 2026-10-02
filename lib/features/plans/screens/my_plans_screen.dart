import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/body_metrics.dart';
import '../../../data/local/database.dart';
import '../../auth/providers/auth_providers.dart';
import '../../members/providers/member_providers.dart';
import '../models/meal_plan.dart';
import '../providers/plan_providers.dart';

/// The member's own plans, fully cached for offline viewing (brain.md §6.6).
class MyPlansScreen extends ConsumerStatefulWidget {
  const MyPlansScreen({this.memberId, super.key});

  /// Defaults to the signed-in member; staff pass an id to preview.
  final String? memberId;

  @override
  ConsumerState<MyPlansScreen> createState() => _MyPlansScreenState();
}

class _MyPlansScreenState extends ConsumerState<MyPlansScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final memberId =
        widget.memberId ?? ref.watch(currentSessionProvider)?.userId;

    if (memberId == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      children: [
        TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'Workout', icon: Icon(Icons.fitness_center)),
            Tab(text: 'Diet', icon: Icon(Icons.restaurant_menu)),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [
              _MyWorkouts(memberId: memberId),
              _MyDiets(memberId: memberId),
            ],
          ),
        ),
      ],
    );
  }
}

class _MyWorkouts extends ConsumerWidget {
  const _MyWorkouts({required this.memberId});

  final String memberId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plans = ref.watch(assignedWorkoutsProvider(memberId));

    return plans.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(child: Text('Could not load: $error')),
      data: (list) => list.isEmpty
          ? const _NoPlan(
              icon: Icons.fitness_center,
              message: 'No workout plan assigned yet.',
            )
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                for (final plan in list)
                  _WorkoutPlanCard(plan: plan, memberId: memberId),
              ],
            ),
    );
  }
}

class _WorkoutPlanCard extends ConsumerWidget {
  const _WorkoutPlanCard({required this.plan, required this.memberId});

  final WorkoutPlan plan;
  final String memberId;

  static const _dayNames = {
    1: 'Monday',
    2: 'Tuesday',
    3: 'Wednesday',
    4: 'Thursday',
    5: 'Friday',
    6: 'Saturday',
    7: 'Sunday',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final exercises = ref.watch(planExercisesProvider(plan.id));
    final completed = ref.watch(completedTodayProvider(memberId));
    final done = completed.valueOrNull ?? const <String>{};

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(plan.name, style: theme.textTheme.titleMedium),
            if (plan.description?.isNotEmpty == true) ...[
              const SizedBox(height: 4),
              Text(plan.description!, style: theme.textTheme.bodySmall),
            ],
            const SizedBox(height: 12),

            exercises.when(
              loading: () => const Center(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: CircularProgressIndicator(),
                ),
              ),
              error: (error, _) => Text('Could not load exercises: $error'),
              data: (list) {
                if (list.isEmpty) {
                  return Text(
                    'No exercises in this plan.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  );
                }

                final byDay = <int?, List<WorkoutExercise>>{};
                for (final exercise in list) {
                  byDay.putIfAbsent(exercise.dayOfWeek, () => []).add(exercise);
                }

                final days = byDay.keys.toList()
                  ..sort((a, b) {
                    if (a == null) return 1;
                    if (b == null) return -1;
                    return a.compareTo(b);
                  });

                final today = DateTime.now().weekday;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final day in days) ...[
                      Padding(
                        padding: const EdgeInsets.only(top: 8, bottom: 4),
                        child: Row(
                          children: [
                            Text(
                              day == null
                                  ? 'Any day'
                                  : _dayNames[day] ?? 'Day $day',
                              style: theme.textTheme.titleSmall?.copyWith(
                                color: theme.colorScheme.primary,
                              ),
                            ),
                            if (day == today) ...[
                              const SizedBox(width: 8),
                              Chip(
                                label: const Text('Today'),
                                labelStyle: theme.textTheme.labelSmall,
                                visualDensity: VisualDensity.compact,
                                padding: EdgeInsets.zero,
                              ),
                            ],
                          ],
                        ),
                      ),
                      for (final exercise in byDay[day]!)
                        _ExerciseRow(
                          exercise: exercise,
                          memberId: memberId,
                          isDone: done.contains(exercise.id),
                        ),
                    ],
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _ExerciseRow extends ConsumerWidget {
  const _ExerciseRow({
    required this.exercise,
    required this.memberId,
    required this.isDone,
  });

  final WorkoutExercise exercise;
  final String memberId;
  final bool isDone;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    // Bodyweight-relative load uses the member's *live current* weight, not
    // the plan's assignment-time snapshot — this field exists specifically to
    // stay correct as the member's weight changes (brain.md §6.11), unlike
    // BMI/calorie targets which intentionally freeze to the snapshot.
    final liveWeightKg = ref
        .watch(memberSummaryProvider(memberId))
        .valueOrNull
        ?.profile
        .weightKg;

    final bodyweightLoad = BodyMetrics.targetLoadKg(
      bodyweightPercent: exercise.bodyweightPercent,
      weightKg: liveWeightKg,
    );

    final detail = [
      if (exercise.sets != null && exercise.reps != null)
        '${exercise.sets} × ${exercise.reps}'
      else if (exercise.sets != null)
        '${exercise.sets} sets',
      if (exercise.weightNote?.isNotEmpty == true) exercise.weightNote!,
      if (exercise.bodyweightPercent != null)
        bodyweightLoad != null
            ? '${bodyweightLoad.toStringAsFixed(1)}kg (${_formatPercent(exercise.bodyweightPercent!)}% BW)'
            : '${_formatPercent(exercise.bodyweightPercent!)}% bodyweight',
      if (exercise.restSeconds != null) '${exercise.restSeconds}s rest',
    ].join(' · ');

    return CheckboxListTile(
      value: isDone,
      // Completion is recorded locally and synced later (brain.md §6.6), so
      // ticking works with no connection.
      onChanged: (_) => ref.read(planDaoProvider).toggleCompletion(
        exerciseId: exercise.id,
        memberId: memberId,
      ),
      dense: true,
      contentPadding: EdgeInsets.zero,
      controlAffinity: ListTileControlAffinity.leading,
      title: Text(
        exercise.name,
        style: isDone
            ? TextStyle(
                decoration: TextDecoration.lineThrough,
                color: theme.colorScheme.outline,
              )
            : null,
      ),
      subtitle: detail.isEmpty && exercise.instructions == null
          ? null
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (detail.isNotEmpty) Text(detail),
                if (exercise.instructions?.isNotEmpty == true)
                  Text(
                    exercise.instructions!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontStyle: FontStyle.italic,
                      color: theme.colorScheme.outline,
                    ),
                  ),
              ],
            ),
    );
  }

  /// Drops a trailing ".0" so a whole percentage doesn't read "50.0".
  static String _formatPercent(double value) {
    return value % 1 == 0 ? value.toInt().toString() : value.toString();
  }
}

class _MyDiets extends ConsumerWidget {
  const _MyDiets({required this.memberId});

  final String memberId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plans = ref.watch(assignedDietsProvider(memberId));

    return plans.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(child: Text('Could not load: $error')),
      data: (list) {
        if (list.isEmpty) {
          return const _NoPlan(
            icon: Icons.restaurant_menu,
            message: 'No diet plan assigned yet.',
          );
        }

        return ListView(
          padding: const EdgeInsets.all(12),
          children: [
            for (final plan in list) _DietPlanCard(plan: plan),
          ],
        );
      },
    );
  }
}

class _DietPlanCard extends ConsumerWidget {
  const _DietPlanCard({required this.plan});

  final DietPlan plan;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final meals = ref.watch(planMealsProvider(plan.id));

    final bmi = BodyMetrics.bmi(
      weightKg: plan.snapshotWeightKg,
      heightCm: plan.snapshotHeightCm,
    );
    final activityLevel = ActivityLevel.fromString(plan.activityLevel);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(plan.name, style: theme.textTheme.titleMedium),
            if (plan.description?.isNotEmpty == true) ...[
              const SizedBox(height: 4),
              Text(plan.description!, style: theme.textTheme.bodySmall),
            ],
            if (bmi != null || activityLevel != null) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 12,
                children: [
                  if (bmi != null)
                    Text(
                      'BMI ${bmi.toStringAsFixed(1)} (${BodyMetrics.bmiCategory(bmi)})',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            meals.when(
              loading: () => const SizedBox.shrink(),
              error: (error, _) => Text('Could not load meals: $error'),
              data: (list) {
                if (list.isNotEmpty) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final meal in list) _MealPreview(meal: meal),
                    ],
                  );
                }
                // Legacy plan predating structured meals.
                final legacy = MealPlan.decode(plan.mealsJson);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final meal in legacy) ...[
                      Text(
                        meal.name,
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: theme.colorScheme.primary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      for (final item in meal.items)
                        Padding(
                          padding: const EdgeInsets.only(left: 8, bottom: 2),
                          child: Text('• $item'),
                        ),
                      const SizedBox(height: 12),
                    ],
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _MealPreview extends ConsumerWidget {
  const _MealPreview({required this.meal});

  final DietMeal meal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final items = ref.watch(mealFoodItemsProvider(meal.id));

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                meal.name,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
              if (meal.time?.isNotEmpty == true) ...[
                const SizedBox(width: 8),
                Text(
                  meal.time!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 4),
          items.when(
            loading: () => const SizedBox.shrink(),
            error: (error, _) => Text('Could not load: $error'),
            data: (list) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final item in list)
                  Padding(
                    padding: const EdgeInsets.only(left: 8, bottom: 2),
                    child: Text(
                      item.quantity?.isNotEmpty == true
                          ? '• ${item.name} (${item.quantity})'
                          : '• ${item.name}',
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NoPlan extends StatelessWidget {
  const _NoPlan({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 48, color: theme.colorScheme.outline),
            const SizedBox(height: 16),
            Text(message, style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Your trainer will assign one.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
