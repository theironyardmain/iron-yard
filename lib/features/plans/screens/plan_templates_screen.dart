import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/local/database.dart';
import '../providers/plan_providers.dart';
import 'diet_plan_editor_screen.dart';
import 'workout_plan_editor_screen.dart';

/// Workout and diet templates, built once and assigned to many
/// (brain.md §6.6).
class PlanTemplatesScreen extends ConsumerStatefulWidget {
  const PlanTemplatesScreen({super.key});

  @override
  ConsumerState<PlanTemplatesScreen> createState() =>
      _PlanTemplatesScreenState();
}

class _PlanTemplatesScreenState extends ConsumerState<PlanTemplatesScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  void _createForCurrentTab() {
    final isWorkout = _tabs.index == 0;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => isWorkout
            ? const WorkoutPlanEditorScreen()
            : const DietPlanEditorScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          TabBar(
            controller: _tabs,
            tabs: const [
              Tab(text: 'Workouts', icon: Icon(Icons.fitness_center)),
              Tab(text: 'Diet', icon: Icon(Icons.restaurant_menu)),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: const [_WorkoutTemplates(), _DietTemplates()],
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createForCurrentTab,
        icon: const Icon(Icons.add),
        label: const Text('New template'),
      ),
    );
  }
}

class _WorkoutTemplates extends ConsumerWidget {
  const _WorkoutTemplates();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final templates = ref.watch(workoutTemplatesProvider);

    return templates.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(child: Text('Could not load: $error')),
      data: (list) => list.isEmpty
          ? const _Empty(
              icon: Icons.fitness_center,
              title: 'No workout templates',
              subtitle: 'Build one, then assign it to any member.',
            )
          : ListView.builder(
              padding: const EdgeInsets.only(bottom: 88),
              itemCount: list.length,
              itemBuilder: (context, index) =>
                  _WorkoutTemplateTile(plan: list[index]),
            ),
    );
  }
}

class _WorkoutTemplateTile extends ConsumerWidget {
  const _WorkoutTemplateTile({required this.plan});

  final WorkoutPlan plan;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final exercises = ref.watch(planExercisesProvider(plan.id));

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      child: ListTile(
        leading: const CircleAvatar(child: Icon(Icons.fitness_center)),
        title: Text(plan.name),
        subtitle: Text(
          exercises.maybeWhen(
            data: (list) => list.isEmpty
                ? 'No exercises yet'
                : list.length == 1
                ? '1 exercise'
                : '${list.length} exercises',
            orElse: () => '…',
          ),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => WorkoutPlanEditorScreen(plan: plan),
          ),
        ),
      ),
    );
  }
}

class _DietTemplates extends ConsumerWidget {
  const _DietTemplates();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final templates = ref.watch(dietTemplatesProvider);

    return templates.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(child: Text('Could not load: $error')),
      data: (list) => list.isEmpty
          ? const _Empty(
              icon: Icons.restaurant_menu,
              title: 'No diet templates',
              subtitle: 'Build one, then assign it to any member.',
            )
          : ListView.builder(
              padding: const EdgeInsets.only(bottom: 88),
              itemCount: list.length,
              itemBuilder: (context, index) {
                final plan = list[index];
                return Card(
                  margin: const EdgeInsets.fromLTRB(12, 6, 12, 6),
                  child: ListTile(
                    leading: const CircleAvatar(
                      child: Icon(Icons.restaurant_menu),
                    ),
                    title: Text(plan.name),
                    subtitle: Text(plan.description ?? 'No description'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => DietPlanEditorScreen(plan: plan),
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

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
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              subtitle,
              textAlign: TextAlign.center,
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
