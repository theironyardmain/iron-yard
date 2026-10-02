import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/utils/money.dart';
import '../../../shared/providers/database_provider.dart';
import '../../auth/providers/auth_providers.dart';
import '../providers/equipment_providers.dart';

/// Logs a service/repair event for a piece of equipment (brain.md §6.10).
class LogServiceScreen extends ConsumerStatefulWidget {
  const LogServiceScreen({required this.equipmentId, required this.name, super.key});

  final String equipmentId;
  final String name;

  @override
  ConsumerState<LogServiceScreen> createState() => _LogServiceScreenState();
}

class _LogServiceScreenState extends ConsumerState<LogServiceScreen> {
  final _formKey = GlobalKey<FormState>();
  final _descriptionController = TextEditingController();
  final _costController = TextEditingController();

  DateTime _servicedAt = DateTime.now();
  bool _saving = false;

  @override
  void dispose() {
    _descriptionController.dispose();
    _costController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _servicedAt,
      firstDate: DateTime(now.year - 5),
      lastDate: now,
      helpText: 'Service date',
    );
    if (picked != null) setState(() => _servicedAt = picked);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);

    final session = ref.read(currentSessionProvider);
    final costText = _costController.text.trim();
    final costMinor = costText.isEmpty ? null : Money.parse(costText);

    await ref.read(equipmentDaoProvider).logService(
      equipmentId: widget.equipmentId,
      description: _descriptionController.text.trim(),
      servicedAt: _servicedAt,
      costMinor: costMinor,
      performedBy: session?.userId,
    );

    ref.invalidate(serviceHistoryProvider(widget.equipmentId));
    ref.invalidate(allEquipmentProvider);
    ref.invalidate(equipmentListProvider);
    ref.invalidate(equipmentDueForServiceProvider);

    if (!mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Service logged')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Log service — ${widget.name}')),
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
                    controller: _descriptionController,
                    decoration: const InputDecoration(
                      labelText: 'What was done *',
                      prefixIcon: Icon(Icons.notes_outlined),
                      hintText: 'Belt replaced, routine inspection…',
                    ),
                    maxLines: 2,
                    enabled: !_saving,
                    validator: (value) => (value?.trim().isEmpty ?? true)
                        ? 'Enter a description'
                        : null,
                  ),
                  const SizedBox(height: 16),

                  InkWell(
                    onTap: _saving ? null : _pickDate,
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Service date',
                        prefixIcon: Icon(Icons.event_outlined),
                      ),
                      child: Text(DateFormat.yMMMd().format(_servicedAt)),
                    ),
                  ),
                  const SizedBox(height: 16),

                  TextFormField(
                    controller: _costController,
                    decoration: const InputDecoration(
                      labelText: 'Cost (optional)',
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

                  const SizedBox(height: 32),
                  FilledButton(
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Log service'),
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
