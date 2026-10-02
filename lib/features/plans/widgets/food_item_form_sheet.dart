import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/local/database.dart';
import '../providers/plan_providers.dart';

/// Adds or edits one food item within a meal (brain.md §6.11).
Future<void> showFoodItemFormSheet({
  required BuildContext context,
  required WidgetRef ref,
  required String mealId,
  DietFoodItem? item,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: _FoodItemForm(mealId: mealId, item: item),
    ),
  );
}

class _FoodItemForm extends ConsumerStatefulWidget {
  const _FoodItemForm({required this.mealId, this.item});

  final String mealId;
  final DietFoodItem? item;

  @override
  ConsumerState<_FoodItemForm> createState() => _FoodItemFormState();
}

class _FoodItemFormState extends ConsumerState<_FoodItemForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _quantityController;
  late final TextEditingController _caloriesController;
  late final TextEditingController _proteinController;
  late final TextEditingController _carbsController;
  late final TextEditingController _fatController;

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final item = widget.item;
    _nameController = TextEditingController(text: item?.name ?? '');
    _quantityController = TextEditingController(text: item?.quantity ?? '');
    _caloriesController = TextEditingController(
      text: item?.calories?.toString() ?? '',
    );
    _proteinController = TextEditingController(
      text: item?.proteinG?.toString() ?? '',
    );
    _carbsController = TextEditingController(
      text: item?.carbsG?.toString() ?? '',
    );
    _fatController = TextEditingController(
      text: item?.fatG?.toString() ?? '',
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _quantityController.dispose();
    _caloriesController.dispose();
    _proteinController.dispose();
    _carbsController.dispose();
    _fatController.dispose();
    super.dispose();
  }

  String? _textOrNull(TextEditingController controller) {
    final text = controller.text.trim();
    return text.isEmpty ? null : text;
  }

  int? _intOrNull(TextEditingController controller) =>
      int.tryParse(controller.text.trim());

  double? _doubleOrNull(TextEditingController controller) =>
      double.tryParse(controller.text.trim());

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);

    final dao = ref.read(planDaoProvider);
    final name = _nameController.text.trim();

    if (widget.item == null) {
      await dao.addFoodItem(
        mealId: widget.mealId,
        name: name,
        quantity: _textOrNull(_quantityController),
        calories: _intOrNull(_caloriesController),
        proteinG: _doubleOrNull(_proteinController),
        carbsG: _doubleOrNull(_carbsController),
        fatG: _doubleOrNull(_fatController),
      );
    } else {
      await dao.updateFoodItem(
        id: widget.item!.id,
        name: name,
        quantity: _textOrNull(_quantityController),
        calories: _intOrNull(_caloriesController),
        proteinG: _doubleOrNull(_proteinController),
        carbsG: _doubleOrNull(_carbsController),
        fatG: _doubleOrNull(_fatController),
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
                widget.item == null ? 'Add food item' : 'Edit food item',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 20),

              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Food *',
                  hintText: 'Chicken breast, Rice…',
                ),
                textCapitalization: TextCapitalization.words,
                autofocus: widget.item == null,
                enabled: !_saving,
                validator: (value) => (value?.trim().isEmpty ?? true)
                    ? 'Enter a food name'
                    : null,
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _quantityController,
                decoration: const InputDecoration(
                  labelText: 'Quantity',
                  hintText: '150g, 1 cup…',
                ),
                enabled: !_saving,
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _caloriesController,
                decoration: const InputDecoration(
                  labelText: 'Calories',
                  suffixText: 'kcal',
                ),
                keyboardType: TextInputType.number,
                enabled: !_saving,
              ),
              const SizedBox(height: 16),

              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _proteinController,
                      decoration: const InputDecoration(
                        labelText: 'Protein',
                        suffixText: 'g',
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      enabled: !_saving,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _carbsController,
                      decoration: const InputDecoration(
                        labelText: 'Carbs',
                        suffixText: 'g',
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      enabled: !_saving,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _fatController,
                      decoration: const InputDecoration(
                        labelText: 'Fat',
                        suffixText: 'g',
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      enabled: !_saving,
                    ),
                  ),
                ],
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
                    : const Text('Save food item'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
