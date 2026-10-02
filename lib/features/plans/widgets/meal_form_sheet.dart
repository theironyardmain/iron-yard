import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/local/database.dart';
import '../providers/plan_providers.dart';

/// Adds or edits one meal in a diet plan (brain.md §6.11).
Future<void> showMealFormSheet({
  required BuildContext context,
  required WidgetRef ref,
  required String planId,
  DietMeal? meal,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: _MealForm(planId: planId, meal: meal),
    ),
  );
}

class _MealForm extends ConsumerStatefulWidget {
  const _MealForm({required this.planId, this.meal});

  final String planId;
  final DietMeal? meal;

  @override
  ConsumerState<_MealForm> createState() => _MealFormState();
}

class _MealFormState extends ConsumerState<_MealForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _timeController;

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.meal?.name ?? '');
    _timeController = TextEditingController(text: widget.meal?.time ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _timeController.dispose();
    super.dispose();
  }

  String? _textOrNull(TextEditingController controller) {
    final text = controller.text.trim();
    return text.isEmpty ? null : text;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);

    final dao = ref.read(planDaoProvider);
    final name = _nameController.text.trim();
    final time = _textOrNull(_timeController);

    if (widget.meal == null) {
      await dao.addMeal(planId: widget.planId, name: name, time: time);
    } else {
      await dao.updateMeal(id: widget.meal!.id, name: name, time: time);
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
                widget.meal == null ? 'Add meal' : 'Edit meal',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 20),

              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Meal *',
                  hintText: 'Breakfast, Post-workout…',
                ),
                textCapitalization: TextCapitalization.words,
                autofocus: widget.meal == null,
                enabled: !_saving,
                validator: (value) => (value?.trim().isEmpty ?? true)
                    ? 'Enter a meal name'
                    : null,
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _timeController,
                decoration: const InputDecoration(
                  labelText: 'Time',
                  hintText: '7:30 AM',
                ),
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
                    : const Text('Save meal'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
