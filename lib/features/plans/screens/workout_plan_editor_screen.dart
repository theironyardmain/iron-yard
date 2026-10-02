import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/local/database.dart';
import '../../auth/providers/auth_providers.dart';
import '../providers/plan_providers.dart';
import '../widgets/exercise_form_sheet.dart';

/// Builds a workout template: the plan, then its exercises by day
/// (brain.md §6.6).
class WorkoutPlanEditorScreen extends ConsumerStatefulWidget {
  const WorkoutPlanEditorScreen({this.plan, super.key});

  final WorkoutPlan? plan;

  bool get isEditing => plan != null;

  @override
  ConsumerState<WorkoutPlanEditorScreen> createState() =>
      _WorkoutPlanEditorScreenState();
}

class _WorkoutPlanEditorScreenState
    extends ConsumerState<WorkoutPlanEditorScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;

  /// Set once the plan exists, so exercises have something to attach to.
  String? _planId;
  bool _saving = false;

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
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.plan?.name ?? '');
    _descriptionController = TextEditingController(
      text: widget.plan?.description ?? '',
    );
    _planId = widget.plan?.id;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  String? _trimmedDescription() {
    final text = _descriptionController.text.trim();
    return text.isEmpty ? null : text;
  }

  /// Creates the plan if needed, so exercises can be attached.
  ///
  /// Saving the header first means a half-built template survives the app
  /// being closed mid-edit.
  Future<String?> _ensureSaved() async {
    if (!_formKey.currentState!.validate()) return null;

    final dao = ref.read(planDaoProvider);
    final name = _nameController.text.trim();

    if (_planId == null) {
      final session = ref.read(currentSessionProvider);
      final id = await dao.createWorkoutPlan(
        name: name,
        description: _trimmedDescription(),
        createdById: session?.userId,
      );
      if (mounted) setState(() => _planId = id);
      return id;
    }

    await dao.updateWorkoutPlan(
      id: _planId!,
      name: name,
      description: _trimmedDescription(),
    );
    return _planId;
  }

  Future<void> _addExercise() async {
    final planId = await _ensureSaved();
    if (planId == null || !mounted) return;

    await showExerciseFormSheet(context: context, ref: ref, planId: planId);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final id = await _ensureSaved();
    if (!mounted) return;
    setState(() => _saving = false);

    if (id == null) return;
    Navigator.of(context).pop();
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete template?'),
        content: const Text(
          // Say this plainly: staff would otherwise fear deleting a template
          // strips the plan from members following it.
          'This removes the template only. Members already assigned a copy '
          'of it keep their plan.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true || _planId == null || !mounted) return;

    await ref.read(planDaoProvider).deleteWorkoutPlan(_planId!);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final planId = _planId;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isEditing ? 'Edit template' : 'New template'),
        actions: [
          if (planId != null)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Delete template',
              onPressed: _confirmDelete,
            ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextFormField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: 'Template name *',
                      prefixIcon: Icon(Icons.fitness_center),
                      hintText: 'Push Pull Legs, Beginner Full Body…',
                    ),
                    textCapitalization: TextCapitalization.words,
                    enabled: !_saving,
                    validator: (value) => (value?.trim().isEmpty ?? true)
                        ? 'Enter a template name'
                        : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _descriptionController,
                    decoration: const InputDecoration(
                      labelText: 'Description',
                      prefixIcon: Icon(Icons.notes_outlined),
                    ),
                    maxLines: 2,
                    enabled: !_saving,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Exercises', style: theme.textTheme.titleMedium),
                TextButton.icon(
                  onPressed: _saving ? null : _addExercise,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add'),
                ),
              ],
            ),

            if (planId == null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  'Name the template, then add exercises.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              )
            else
              _ExerciseList(planId: planId, dayNames: _dayNames),

            const SizedBox(height: 32),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Done'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExerciseList extends ConsumerWidget {
  const _ExerciseList({required this.planId, required this.dayNames});

  final String planId;
  final Map<int, String> dayNames;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final exercises = ref.watch(planExercisesProvider(planId));
    final theme = Theme.of(context);

    return exercises.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => Text('Could not load exercises: $error'),
      data: (list) {
        if (list.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(
              'No exercises yet.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          );
        }

        // Group by day; unscheduled exercises come last under their own head.
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

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final day in days) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 16, 4, 4),
                child: Text(
                  day == null ? 'Unscheduled' : dayNames[day] ?? 'Day $day',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
              for (final exercise in byDay[day]!)
                _ExerciseTile(exercise: exercise, planId: planId),
            ],
          ],
        );
      },
    );
  }
}

class _ExerciseTile extends ConsumerWidget {
  const _ExerciseTile({required this.exercise, required this.planId});

  final WorkoutExercise exercise;
  final String planId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = [
      if (exercise.sets != null && exercise.reps != null)
        '${exercise.sets} × ${exercise.reps}'
      else if (exercise.sets != null)
        '${exercise.sets} sets',
      if (exercise.weightNote?.isNotEmpty == true) exercise.weightNote!,
      // No assigned member here to compute an actual kg figure against
      // (this screen builds templates), so just show the raw percentage.
      if (exercise.bodyweightPercent != null)
        '${_formatPercent(exercise.bodyweightPercent!)}% bodyweight',
      if (exercise.restSeconds != null) '${exercise.restSeconds}s rest',
    ].join(' · ');

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        dense: true,
        title: Text(exercise.name),
        subtitle: detail.isEmpty ? null : Text(detail),
        trailing: PopupMenuButton<String>(
          onSelected: (value) async {
            if (value == 'edit') {
              await showExerciseFormSheet(
                context: context,
                ref: ref,
                planId: planId,
                exercise: exercise,
              );
            } else if (value == 'delete') {
              await ref.read(planDaoProvider).deleteExercise(exercise.id);
            }
          },
          itemBuilder: (context) => const [
            PopupMenuItem(value: 'edit', child: Text('Edit')),
            PopupMenuItem(value: 'delete', child: Text('Remove')),
          ],
        ),
      ),
    );
  }

  /// Drops a trailing ".0" so a whole percentage doesn't read "50.0".
  static String _formatPercent(double value) {
    return value % 1 == 0 ? value.toInt().toString() : value.toString();
  }
}
