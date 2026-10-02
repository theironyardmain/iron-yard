import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/body_metrics.dart';
import '../../../data/local/database.dart';
import '../../auth/providers/auth_providers.dart';
import '../models/meal_plan.dart';
import '../providers/plan_providers.dart';
import '../widgets/food_item_form_sheet.dart';
import '../widgets/meal_form_sheet.dart';

/// Builds a diet template: the plan, then structured meals and food items
/// (brain.md §6.6, §6.11).
///
/// A newly assigned (not-yet-saved) plan is created immediately on first meal
/// add, mirroring `WorkoutPlanEditorScreen` — a half-built template survives
/// the app being closed mid-edit.
class DietPlanEditorScreen extends ConsumerStatefulWidget {
  const DietPlanEditorScreen({this.plan, super.key});

  final DietPlan? plan;

  bool get isEditing => plan != null;

  @override
  ConsumerState<DietPlanEditorScreen> createState() =>
      _DietPlanEditorScreenState();
}

class _DietPlanEditorScreenState extends ConsumerState<DietPlanEditorScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;

  /// Set once the plan exists, so meals have something to attach to.
  String? _planId;
  ActivityLevel? _activityLevel;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.plan?.name ?? '');
    _descriptionController = TextEditingController(
      text: widget.plan?.description ?? '',
    );
    _planId = widget.plan?.id;
    _activityLevel = ActivityLevel.fromString(widget.plan?.activityLevel);
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

  /// Creates the plan if needed, so meals can be attached.
  Future<String?> _ensureSaved() async {
    if (!_formKey.currentState!.validate()) return null;

    final dao = ref.read(planDaoProvider);
    final name = _nameController.text.trim();

    if (_planId == null) {
      final session = ref.read(currentSessionProvider);
      final id = await dao.createDietPlan(
        name: name,
        description: _trimmedDescription(),
        createdById: session?.userId,
        activityLevel: _activityLevel,
      );
      if (mounted) setState(() => _planId = id);
      return id;
    }

    await dao.updateDietPlan(
      id: _planId!,
      name: name,
      description: _trimmedDescription(),
      activityLevel: _activityLevel,
    );
    return _planId;
  }

  Future<void> _addMeal() async {
    final planId = await _ensureSaved();
    if (planId == null || !mounted) return;

    await showMealFormSheet(context: context, ref: ref, planId: planId);
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
          // Stated plainly: staff would otherwise fear deleting a template
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

    await ref.read(planDaoProvider).deleteDietPlan(_planId!);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final planId = _planId;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isEditing ? 'Edit diet plan' : 'New diet plan'),
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
                      labelText: 'Plan name *',
                      prefixIcon: Icon(Icons.restaurant_menu),
                      hintText: 'Cutting, Bulking, Maintenance…',
                    ),
                    textCapitalization: TextCapitalization.words,
                    enabled: !_saving,
                    validator: (value) => (value?.trim().isEmpty ?? true)
                        ? 'Enter a plan name'
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
                  const SizedBox(height: 16),

                  DropdownButtonFormField<ActivityLevel>(
                    initialValue: _activityLevel,
                    decoration: const InputDecoration(
                      labelText: 'Activity level',
                      prefixIcon: Icon(Icons.directions_run_outlined),
                      helperText:
                          'Used with the member\'s weight to suggest a '
                          'daily calorie target',
                    ),
                    items: [
                      const DropdownMenuItem(child: Text('Not set')),
                      for (final level in ActivityLevel.values)
                        DropdownMenuItem(value: level, child: Text(level.label)),
                    ],
                    onChanged: _saving
                        ? null
                        : (value) => setState(() => _activityLevel = value),
                  ),
                ],
              ),
            ),

            if (widget.plan != null) _CalculatedTargets(plan: widget.plan!),

            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Meals', style: theme.textTheme.titleMedium),
                TextButton.icon(
                  onPressed: _saving ? null : _addMeal,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add'),
                ),
              ],
            ),

            if (planId == null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  'Name the plan, then add meals.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              )
            else
              _MealList(planId: planId),

            // Legacy plans predate structured meals — decode and show their
            // mealsJson read-only rather than silently hiding their content
            // (brain.md §6.11: old plans are not migrated).
            if (widget.plan?.mealsJson != null)
              _LegacyMeals(mealsJson: widget.plan!.mealsJson!),

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

/// BMI and the Mifflin-St Jeor calorie target, from the plan's assignment-time
/// snapshot (brain.md §6.11) — shown only for an assigned plan; a template has
/// no member to compute against.
class _CalculatedTargets extends StatelessWidget {
  const _CalculatedTargets({required this.plan});

  final DietPlan plan;

  @override
  Widget build(BuildContext context) {
    if (plan.snapshotHeightCm == null && plan.snapshotWeightKg == null) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final bmi = BodyMetrics.bmi(
      weightKg: plan.snapshotWeightKg,
      heightCm: plan.snapshotHeightCm,
    );
    final activityLevel = ActivityLevel.fromString(plan.activityLevel);

    if (bmi == null && activityLevel == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.colorScheme.secondaryContainer,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'At assignment',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSecondaryContainer,
              ),
            ),
            const SizedBox(height: 4),
            if (bmi != null)
              Text(
                'BMI ${bmi.toStringAsFixed(1)} (${BodyMetrics.bmiCategory(bmi)})',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSecondaryContainer,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _MealList extends ConsumerWidget {
  const _MealList({required this.planId});

  final String planId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final meals = ref.watch(planMealsProvider(planId));
    final theme = Theme.of(context);

    return meals.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => Text('Could not load meals: $error'),
      data: (list) {
        if (list.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(
              'No meals yet.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          );
        }

        return Column(
          children: [for (final meal in list) _MealCard(meal: meal)],
        );
      },
    );
  }
}

class _MealCard extends ConsumerWidget {
  const _MealCard({required this.meal});

  final DietMeal meal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(mealFoodItemsProvider(meal.id));
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(meal.name, style: theme.textTheme.titleSmall),
                      if (meal.time?.isNotEmpty == true)
                        Text(
                          meal.time!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.outline,
                          ),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 20),
                  onPressed: () => showMealFormSheet(
                    context: context,
                    ref: ref,
                    planId: meal.planId,
                    meal: meal,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 20),
                  onPressed: () =>
                      ref.read(planDaoProvider).deleteMeal(meal.id),
                ),
              ],
            ),
            items.when(
              loading: () => const SizedBox.shrink(),
              error: (error, _) => Text('Could not load: $error'),
              data: (list) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final item in list) _FoodItemRow(item: item),
                  TextButton.icon(
                    onPressed: () => showFoodItemFormSheet(
                      context: context,
                      ref: ref,
                      mealId: meal.id,
                    ),
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Add food'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FoodItemRow extends ConsumerWidget {
  const _FoodItemRow({required this.item});

  final DietFoodItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = [
      if (item.quantity?.isNotEmpty == true) item.quantity!,
      if (item.calories != null) '${item.calories} kcal',
      if (item.proteinG != null) 'P ${item.proteinG}g',
      if (item.carbsG != null) 'C ${item.carbsG}g',
      if (item.fatG != null) 'F ${item.fatG}g',
    ].join(' · ');

    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.only(left: 8),
      title: Text(item.name),
      subtitle: detail.isEmpty ? null : Text(detail),
      trailing: PopupMenuButton<String>(
        onSelected: (value) async {
          if (value == 'edit') {
            await showFoodItemFormSheet(
              context: context,
              ref: ref,
              mealId: item.mealId,
              item: item,
            );
          } else if (value == 'delete') {
            await ref.read(planDaoProvider).deleteFoodItem(item.id);
          }
        },
        itemBuilder: (context) => const [
          PopupMenuItem(value: 'edit', child: Text('Edit')),
          PopupMenuItem(value: 'delete', child: Text('Remove')),
        ],
      ),
    );
  }
}

/// Read-only display of a pre-structured-meals plan's `mealsJson` (brain.md
/// §6.11) — old plans are not migrated, so this is the only place their
/// content is still visible.
class _LegacyMeals extends StatelessWidget {
  const _LegacyMeals({required this.mealsJson});

  final String mealsJson;

  @override
  Widget build(BuildContext context) {
    final meals = MealPlan.decode(mealsJson);
    if (meals.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.history, size: 16, color: theme.colorScheme.outline),
              const SizedBox(width: 6),
              Text(
                'From before structured meals — read-only',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final meal in meals) ...[
            Text(meal.name, style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            for (final item in meal.items)
              Padding(
                padding: const EdgeInsets.only(left: 8, bottom: 2),
                child: Text('• $item'),
              ),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}
