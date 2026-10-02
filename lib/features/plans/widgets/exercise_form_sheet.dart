import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/local/database.dart';
import '../providers/plan_providers.dart';

/// Adds or edits one exercise in a workout plan (brain.md §6.6).
Future<void> showExerciseFormSheet({
  required BuildContext context,
  required WidgetRef ref,
  required String planId,
  WorkoutExercise? exercise,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: _ExerciseForm(planId: planId, exercise: exercise),
    ),
  );
}

class _ExerciseForm extends ConsumerStatefulWidget {
  const _ExerciseForm({required this.planId, this.exercise});

  final String planId;
  final WorkoutExercise? exercise;

  @override
  ConsumerState<_ExerciseForm> createState() => _ExerciseFormState();
}

class _ExerciseFormState extends ConsumerState<_ExerciseForm> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameController;
  late final TextEditingController _setsController;
  late final TextEditingController _repsController;
  late final TextEditingController _weightController;
  late final TextEditingController _bodyweightPercentController;
  late final TextEditingController _restController;
  late final TextEditingController _instructionsController;

  int? _dayOfWeek;
  bool _saving = false;

  static const _days = {
    1: 'Mon',
    2: 'Tue',
    3: 'Wed',
    4: 'Thu',
    5: 'Fri',
    6: 'Sat',
    7: 'Sun',
  };

  @override
  void initState() {
    super.initState();
    final exercise = widget.exercise;

    _nameController = TextEditingController(text: exercise?.name ?? '');
    _setsController = TextEditingController(
      text: exercise?.sets?.toString() ?? '',
    );
    _repsController = TextEditingController(
      text: exercise?.reps?.toString() ?? '',
    );
    _weightController = TextEditingController(text: exercise?.weightNote ?? '');
    _bodyweightPercentController = TextEditingController(
      text: exercise?.bodyweightPercent == null
          ? ''
          : _formatPercent(exercise!.bodyweightPercent!),
    );
    _restController = TextEditingController(
      text: exercise?.restSeconds?.toString() ?? '',
    );
    _instructionsController = TextEditingController(
      text: exercise?.instructions ?? '',
    );
    _dayOfWeek = exercise?.dayOfWeek;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _setsController.dispose();
    _repsController.dispose();
    _weightController.dispose();
    _bodyweightPercentController.dispose();
    _restController.dispose();
    _instructionsController.dispose();
    super.dispose();
  }

  int? _intOrNull(TextEditingController controller) =>
      int.tryParse(controller.text.trim());

  double? _doubleOrNull(TextEditingController controller) =>
      double.tryParse(controller.text.trim());

  String? _textOrNull(TextEditingController controller) {
    final text = controller.text.trim();
    return text.isEmpty ? null : text;
  }

  /// Drops a trailing ".0" so a whole percentage doesn't read "50.0".
  static String _formatPercent(double value) {
    return value % 1 == 0 ? value.toInt().toString() : value.toString();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);

    final dao = ref.read(planDaoProvider);
    final name = _nameController.text.trim();

    if (widget.exercise == null) {
      await dao.addExercise(
        planId: widget.planId,
        name: name,
        sets: _intOrNull(_setsController),
        reps: _intOrNull(_repsController),
        weightNote: _textOrNull(_weightController),
        bodyweightPercent: _doubleOrNull(_bodyweightPercentController),
        restSeconds: _intOrNull(_restController),
        dayOfWeek: _dayOfWeek,
        instructions: _textOrNull(_instructionsController),
      );
    } else {
      await dao.updateExercise(
        id: widget.exercise!.id,
        name: name,
        sets: _intOrNull(_setsController),
        reps: _intOrNull(_repsController),
        weightNote: _textOrNull(_weightController),
        bodyweightPercent: _doubleOrNull(_bodyweightPercentController),
        restSeconds: _intOrNull(_restController),
        dayOfWeek: _dayOfWeek,
        instructions: _textOrNull(_instructionsController),
      );
    }

    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.exercise == null ? 'Add exercise' : 'Edit exercise',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 20),

              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Exercise *',
                  hintText: 'Bench Press, Squat…',
                ),
                textCapitalization: TextCapitalization.words,
                autofocus: widget.exercise == null,
                enabled: !_saving,
                validator: (value) => (value?.trim().isEmpty ?? true)
                    ? 'Enter an exercise name'
                    : null,
              ),
              const SizedBox(height: 16),

              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _setsController,
                      decoration: const InputDecoration(labelText: 'Sets'),
                      keyboardType: TextInputType.number,
                      enabled: !_saving,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _repsController,
                      decoration: const InputDecoration(labelText: 'Reps'),
                      keyboardType: TextInputType.number,
                      enabled: !_saving,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _restController,
                      decoration: const InputDecoration(
                        labelText: 'Rest',
                        suffixText: 's',
                      ),
                      keyboardType: TextInputType.number,
                      enabled: !_saving,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      controller: _weightController,
                      decoration: const InputDecoration(
                        labelText: 'Weight / intensity',
                        hintText: '40kg, bodyweight, RPE 8…',
                      ),
                      enabled: !_saving,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _bodyweightPercentController,
                      decoration: const InputDecoration(
                        labelText: '% bodyweight',
                        hintText: '50',
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      enabled: !_saving,
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return null;
                        }
                        final n = double.tryParse(value.trim());
                        if (n == null || n <= 0 || n > 500) {
                          return 'Invalid';
                        }
                        return null;
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              Text('Day', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                children: [
                  ChoiceChip(
                    label: const Text('Any'),
                    selected: _dayOfWeek == null,
                    onSelected: _saving
                        ? null
                        : (_) => setState(() => _dayOfWeek = null),
                  ),
                  for (final entry in _days.entries)
                    ChoiceChip(
                      label: Text(entry.value),
                      selected: _dayOfWeek == entry.key,
                      onSelected: _saving
                          ? null
                          : (_) => setState(() => _dayOfWeek = entry.key),
                    ),
                ],
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _instructionsController,
                decoration: const InputDecoration(
                  labelText: 'Instructions',
                  hintText: 'Form cues the member should follow',
                ),
                maxLines: 3,
                enabled: !_saving,
              ),

              const SizedBox(height: 24),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Save exercise'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
