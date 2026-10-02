import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/utils/money.dart';
import '../../../data/local/database.dart';
import '../../../shared/providers/database_provider.dart';
import '../providers/equipment_providers.dart';

/// Create or edit a piece of equipment (brain.md §6.10).
class EquipmentFormScreen extends ConsumerStatefulWidget {
  const EquipmentFormScreen({this.item, super.key});

  final EquipmentItem? item;

  bool get isEditing => item != null;

  @override
  ConsumerState<EquipmentFormScreen> createState() =>
      _EquipmentFormScreenState();
}

class _EquipmentFormScreenState extends ConsumerState<EquipmentFormScreen> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameController;
  late final TextEditingController _categoryController;
  late final TextEditingController _quantityController;
  late final TextEditingController _locationController;
  late final TextEditingController _costController;
  late final TextEditingController _serviceIntervalController;
  late final TextEditingController _notesController;

  DateTime? _purchaseDate;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final item = widget.item;

    _nameController = TextEditingController(text: item?.name ?? '');
    _categoryController = TextEditingController(text: item?.category ?? '');
    _quantityController = TextEditingController(
      text: (item?.quantity ?? 1).toString(),
    );
    _locationController = TextEditingController(text: item?.location ?? '');
    _costController = TextEditingController(
      text: item?.costMinor == null ? '' : Money.toInput(item!.costMinor!),
    );
    _serviceIntervalController = TextEditingController(
      text: item?.serviceIntervalDays?.toString() ?? '',
    );
    _notesController = TextEditingController(text: item?.notes ?? '');
    _purchaseDate = item?.purchaseDate;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _categoryController.dispose();
    _quantityController.dispose();
    _locationController.dispose();
    _costController.dispose();
    _serviceIntervalController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _pickPurchaseDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _purchaseDate ?? now,
      firstDate: DateTime(now.year - 30),
      lastDate: now,
      helpText: 'Purchase date',
    );
    if (picked != null) setState(() => _purchaseDate = picked);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final quantity = int.tryParse(_quantityController.text.trim()) ?? 1;
    final costText = _costController.text.trim();
    final costMinor = costText.isEmpty ? null : Money.parse(costText);
    final intervalText = _serviceIntervalController.text.trim();
    final serviceIntervalDays = intervalText.isEmpty
        ? null
        : int.tryParse(intervalText);

    setState(() => _saving = true);

    final dao = ref.read(equipmentDaoProvider);
    final name = _nameController.text.trim();
    final category = _categoryController.text.trim();
    final location = _locationController.text.trim();
    final notes = _notesController.text.trim();

    if (widget.isEditing) {
      await dao.updateItem(
        id: widget.item!.id,
        name: name,
        category: category.isEmpty ? null : category,
        quantity: quantity,
        location: location.isEmpty ? null : location,
        purchaseDate: _purchaseDate,
        costMinor: costMinor,
        serviceIntervalDays: serviceIntervalDays,
        notes: notes.isEmpty ? null : notes,
      );
    } else {
      await dao.create(
        name: name,
        category: category.isEmpty ? null : category,
        quantity: quantity,
        location: location.isEmpty ? null : location,
        purchaseDate: _purchaseDate,
        costMinor: costMinor,
        serviceIntervalDays: serviceIntervalDays,
        notes: notes.isEmpty ? null : notes,
      );
    }

    ref.invalidate(allEquipmentProvider);
    ref.invalidate(equipmentListProvider);
    ref.invalidate(equipmentDueForServiceProvider);

    if (!mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(widget.isEditing ? 'Equipment updated' : '$name added'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isEditing ? 'Edit equipment' : 'Add equipment'),
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
                      labelText: 'Name *',
                      prefixIcon: Icon(Icons.fitness_center_outlined),
                      hintText: 'Treadmill, Bench press…',
                    ),
                    textCapitalization: TextCapitalization.words,
                    enabled: !_saving,
                    validator: (value) => (value?.trim().isEmpty ?? true)
                        ? 'Enter a name'
                        : null,
                  ),
                  const SizedBox(height: 16),

                  TextFormField(
                    controller: _categoryController,
                    decoration: const InputDecoration(
                      labelText: 'Category',
                      prefixIcon: Icon(Icons.category_outlined),
                      hintText: 'Cardio, Strength, Free weights…',
                    ),
                    textCapitalization: TextCapitalization.words,
                    enabled: !_saving,
                  ),
                  const SizedBox(height: 16),

                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _quantityController,
                          decoration: const InputDecoration(
                            labelText: 'Quantity',
                            prefixIcon: Icon(Icons.numbers_outlined),
                          ),
                          keyboardType: TextInputType.number,
                          enabled: !_saving,
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return null;
                            }
                            final n = int.tryParse(value.trim());
                            if (n == null || n < 1) return 'Enter at least 1';
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: _locationController,
                          decoration: const InputDecoration(
                            labelText: 'Location',
                            prefixIcon: Icon(Icons.place_outlined),
                          ),
                          enabled: !_saving,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  InkWell(
                    onTap: _saving ? null : _pickPurchaseDate,
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Purchase date',
                        prefixIcon: Icon(Icons.event_outlined),
                      ),
                      child: Text(
                        _purchaseDate == null
                            ? 'Not set'
                            : DateFormat.yMMMd().format(_purchaseDate!),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  TextFormField(
                    controller: _costController,
                    decoration: const InputDecoration(
                      labelText: 'Cost',
                      prefixIcon: Icon(Icons.currency_rupee),
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    enabled: !_saving,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) return null;
                      return Money.parse(value) == null
                          ? 'Enter a valid amount'
                          : null;
                    },
                  ),
                  const SizedBox(height: 16),

                  TextFormField(
                    controller: _serviceIntervalController,
                    decoration: const InputDecoration(
                      labelText: 'Service interval (days)',
                      prefixIcon: Icon(Icons.build_circle_outlined),
                      hintText: 'e.g. 90 — leave blank if not scheduled',
                    ),
                    keyboardType: TextInputType.number,
                    enabled: !_saving,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) return null;
                      final n = int.tryParse(value.trim());
                      if (n == null || n <= 0) return 'Enter a positive number';
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  TextFormField(
                    controller: _notesController,
                    decoration: const InputDecoration(
                      labelText: 'Notes',
                      prefixIcon: Icon(Icons.notes_outlined),
                    ),
                    maxLines: 2,
                    enabled: !_saving,
                  ),

                  const SizedBox(height: 32),
                  FilledButton(
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(widget.isEditing ? 'Save changes' : 'Add equipment'),
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
