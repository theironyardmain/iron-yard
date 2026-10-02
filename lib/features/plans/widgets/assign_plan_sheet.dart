import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/providers/auth_providers.dart';
import '../providers/plan_providers.dart';

/// Which kind of template is being assigned.
enum PlanKind {
  workout,
  diet;

  String get label => switch (this) {
    PlanKind.workout => 'workout',
    PlanKind.diet => 'diet',
  };
}

/// Assigns a template to a member by copying it (brain.md §6.6).
Future<void> showAssignTemplateSheet({
  required BuildContext context,
  required String memberId,
  required String memberName,
  required PlanKind kind,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => _AssignTemplateForm(
      memberId: memberId,
      memberName: memberName,
      kind: kind,
    ),
  );
}

class _AssignTemplateForm extends ConsumerStatefulWidget {
  const _AssignTemplateForm({
    required this.memberId,
    required this.memberName,
    required this.kind,
  });

  final String memberId;
  final String memberName;
  final PlanKind kind;

  @override
  ConsumerState<_AssignTemplateForm> createState() =>
      _AssignTemplateFormState();
}

class _AssignTemplateFormState extends ConsumerState<_AssignTemplateForm> {
  String? _selectedId;
  bool _saving = false;

  Future<void> _assign() async {
    final templateId = _selectedId;
    if (templateId == null) return;

    setState(() => _saving = true);

    final dao = ref.read(planDaoProvider);
    final session = ref.read(currentSessionProvider);

    if (widget.kind == PlanKind.workout) {
      await dao.assignWorkoutPlan(
        templateId: templateId,
        memberId: widget.memberId,
        assignedById: session?.userId,
      );
    } else {
      await dao.assignDietPlan(
        templateId: templateId,
        memberId: widget.memberId,
        assignedById: session?.userId,
      );
    }

    if (!mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Plan assigned to ${widget.memberName}'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isWorkout = widget.kind == PlanKind.workout;

    final templates = isWorkout
        ? ref
              .watch(workoutTemplatesProvider)
              .whenData(
                (list) => [
                  for (final p in list) (id: p.id, name: p.name),
                ],
              )
        : ref
              .watch(dietTemplatesProvider)
              .whenData(
                (list) => [
                  for (final p in list) (id: p.id, name: p.name),
                ],
              );

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Assign a ${widget.kind.label} plan',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            widget.memberName,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            // The copy is the point: say so, so trainers know later template
            // edits will not reach this member.
            'A copy is made, so later edits to the template will not change '
            'this member\'s plan.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
          const SizedBox(height: 16),

          templates.when(
            loading: () => const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(),
              ),
            ),
            error: (error, _) => Text('Could not load templates: $error'),
            data: (list) {
              if (list.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    'No ${widget.kind.label} templates yet. Create one under '
                    'Plans first.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                );
              }

              return RadioGroup<String>(
                groupValue: _selectedId,
                onChanged: (value) {
                  if (_saving) return;
                  setState(() => _selectedId = value);
                },
                child: Column(
                  children: [
                    for (final template in list)
                      RadioListTile<String>(
                        value: template.id,
                        enabled: !_saving,
                        title: Text(template.name),
                      ),
                  ],
                ),
              );
            },
          ),

          const SizedBox(height: 16),
          FilledButton(
            onPressed: (_saving || _selectedId == null) ? null : _assign,
            child: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Assign'),
          ),
        ],
      ),
    );
  }
}
