import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/money.dart';
import '../../../data/local/database.dart';
import '../../../shared/providers/database_provider.dart';
import '../providers/membership_providers.dart';

/// Create or edit a membership plan (brain.md §6.3).
class PlanFormScreen extends ConsumerStatefulWidget {
  const PlanFormScreen({this.plan, super.key});

  final MembershipPlan? plan;

  bool get isEditing => plan != null;

  @override
  ConsumerState<PlanFormScreen> createState() => _PlanFormScreenState();
}

class _PlanFormScreenState extends ConsumerState<PlanFormScreen> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameController;
  late final TextEditingController _priceController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _customDaysController;

  /// Preset durations, in days. Null means "custom".
  int? _durationDays;
  bool _saving = false;

  static const _presets = <int, String>{
    30: '1 month',
    90: '3 months',
    180: '6 months',
    365: '1 year',
  };

  @override
  void initState() {
    super.initState();
    final plan = widget.plan;

    _nameController = TextEditingController(text: plan?.name ?? '');
    _priceController = TextEditingController(
      text: plan == null ? '' : Money.toInput(plan.priceMinor),
    );
    _descriptionController = TextEditingController(
      text: plan?.description ?? '',
    );

    final days = plan?.durationDays;
    if (days != null && _presets.containsKey(days)) {
      _durationDays = days;
      _customDaysController = TextEditingController();
    } else {
      _durationDays = null;
      _customDaysController = TextEditingController(
        text: days?.toString() ?? '',
      );
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    _descriptionController.dispose();
    _customDaysController.dispose();
    super.dispose();
  }

  int? get _resolvedDays {
    if (_durationDays != null) return _durationDays;
    return int.tryParse(_customDaysController.text.trim());
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final days = _resolvedDays;
    final priceMinor = Money.parse(_priceController.text);
    if (days == null || priceMinor == null) return;

    setState(() => _saving = true);

    final dao = ref.read(membershipDaoProvider);
    final name = _nameController.text.trim();
    final description = _descriptionController.text.trim();

    if (widget.isEditing) {
      await dao.updatePlan(
        id: widget.plan!.id,
        name: name,
        durationDays: days,
        priceMinor: priceMinor,
        description: description.isEmpty ? null : description,
      );
    } else {
      await dao.createPlan(
        name: name,
        durationDays: days,
        priceMinor: priceMinor,
        description: description.isEmpty ? null : description,
      );
    }

    ref.invalidate(allPlansProvider);

    if (!mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(widget.isEditing ? 'Plan updated' : '$name created')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isEditing ? 'Edit plan' : 'New plan'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextFormField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: 'Plan name *',
                      prefixIcon: Icon(Icons.card_membership_outlined),
                      hintText: 'Monthly, Quarterly, Annual…',
                    ),
                    textCapitalization: TextCapitalization.words,
                    enabled: !_saving,
                    validator: (value) => (value?.trim().isEmpty ?? true)
                        ? 'Enter a plan name'
                        : null,
                  ),
                  const SizedBox(height: 16),

                  TextFormField(
                    controller: _priceController,
                    decoration: const InputDecoration(
                      labelText: 'Price *',
                      prefixIcon: Icon(Icons.currency_rupee),
                      hintText: '1500',
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    enabled: !_saving,
                    validator: (value) {
                      final parsed = Money.parse(value ?? '');
                      if (parsed == null) return 'Enter a valid price';
                      if (parsed == 0) return 'Price must be more than zero';
                      return null;
                    },
                  ),
                  const SizedBox(height: 24),

                  Text('Duration', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final entry in _presets.entries)
                        ChoiceChip(
                          label: Text(entry.value),
                          selected: _durationDays == entry.key,
                          onSelected: _saving
                              ? null
                              : (_) =>
                                    setState(() => _durationDays = entry.key),
                        ),
                      ChoiceChip(
                        label: const Text('Custom'),
                        selected: _durationDays == null,
                        onSelected: _saving
                            ? null
                            : (_) => setState(() => _durationDays = null),
                      ),
                    ],
                  ),

                  if (_durationDays == null) ...[
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _customDaysController,
                      decoration: const InputDecoration(
                        labelText: 'Duration in days *',
                        prefixIcon: Icon(Icons.calendar_today_outlined),
                      ),
                      keyboardType: TextInputType.number,
                      enabled: !_saving,
                      validator: (value) {
                        if (_durationDays != null) return null;
                        final days = int.tryParse(value?.trim() ?? '');
                        if (days == null) return 'Enter a number of days';
                        if (days <= 0) return 'Duration must be at least 1 day';
                        if (days > 3650) return 'That is over 10 years';
                        return null;
                      },
                    ),
                  ],

                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _descriptionController,
                    decoration: const InputDecoration(
                      labelText: 'Description',
                      prefixIcon: Icon(Icons.notes_outlined),
                      hintText: 'What the plan includes',
                    ),
                    maxLines: 2,
                    enabled: !_saving,
                  ),

                  if (widget.isEditing) ...[
                    const SizedBox(height: 16),
                    Card(
                      color: theme.colorScheme.surfaceContainerHighest,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            Icon(
                              Icons.info_outline,
                              size: 20,
                              color: theme.colorScheme.outline,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                // Editing a plan must not silently rewrite
                                // memberships already sold on it.
                                'Changes apply to new memberships only. '
                                'Members already on this plan keep their '
                                'current price and expiry date.',
                                style: theme.textTheme.bodySmall,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],

                  const SizedBox(height: 32),
                  FilledButton(
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(widget.isEditing ? 'Save changes' : 'Create plan'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
