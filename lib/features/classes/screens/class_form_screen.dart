import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../data/local/database.dart';
import '../providers/class_providers.dart';

/// Create or edit a class (brain.md §6.8).
class ClassFormScreen extends ConsumerStatefulWidget {
  const ClassFormScreen({this.gymClass, super.key});

  final ClassesData? gymClass;

  bool get isEditing => gymClass != null;

  @override
  ConsumerState<ClassFormScreen> createState() => _ClassFormScreenState();
}

class _ClassFormScreenState extends ConsumerState<ClassFormScreen> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _locationController;
  late final TextEditingController _capacityController;

  late DateTime _startsAt;
  late Duration _duration;
  bool _saving = false;

  static const _durations = <int, String>{
    30: '30 min',
    45: '45 min',
    60: '1 hour',
    90: '1½ hours',
  };

  @override
  void initState() {
    super.initState();
    final gymClass = widget.gymClass;

    _nameController = TextEditingController(text: gymClass?.name ?? '');
    _descriptionController = TextEditingController(
      text: gymClass?.description ?? '',
    );
    _locationController = TextEditingController(text: gymClass?.location ?? '');
    _capacityController = TextEditingController(
      text: gymClass?.capacity.toString() ?? '12',
    );

    if (gymClass != null) {
      _startsAt = gymClass.startsAt;
      _duration = gymClass.endsAt.difference(gymClass.startsAt);
    } else {
      // Default to tomorrow morning, which is the common case for a new class.
      final tomorrow = DateTime.now().add(const Duration(days: 1));
      _startsAt = DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 7);
      _duration = const Duration(hours: 1);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _locationController.dispose();
    _capacityController.dispose();
    super.dispose();
  }

  Future<void> _pickDateTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _startsAt,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_startsAt),
    );
    if (time == null) return;

    setState(() {
      _startsAt = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);

    final dao = ref.read(classDaoProvider);
    final name = _nameController.text.trim();
    final capacity = int.parse(_capacityController.text.trim());
    final description = _descriptionController.text.trim();
    final location = _locationController.text.trim();
    final endsAt = _startsAt.add(_duration);

    if (widget.isEditing) {
      await dao.updateClass(
        id: widget.gymClass!.id,
        name: name,
        startsAt: _startsAt,
        endsAt: endsAt,
        capacity: capacity,
        description: description.isEmpty ? null : description,
        location: location.isEmpty ? null : location,
      );
    } else {
      await dao.createClass(
        name: name,
        startsAt: _startsAt,
        endsAt: endsAt,
        capacity: capacity,
        description: description.isEmpty ? null : description,
        location: location.isEmpty ? null : location,
      );
    }

    ref.invalidate(weekScheduleProvider);

    if (!mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(widget.isEditing ? 'Class updated' : '$name added')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isEditing ? 'Edit class' : 'New class'),
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
                      labelText: 'Class name *',
                      prefixIcon: Icon(Icons.event),
                      hintText: 'Yoga, Spin, HIIT…',
                    ),
                    textCapitalization: TextCapitalization.words,
                    enabled: !_saving,
                    validator: (value) => (value?.trim().isEmpty ?? true)
                        ? 'Enter a class name'
                        : null,
                  ),
                  const SizedBox(height: 16),

                  InkWell(
                    onTap: _saving ? null : _pickDateTime,
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Starts *',
                        prefixIcon: Icon(Icons.schedule),
                      ),
                      child: Text(
                        DateFormat.yMMMEd().add_jm().format(_startsAt),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  Text('Duration', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final entry in _durations.entries)
                        ChoiceChip(
                          label: Text(entry.value),
                          selected: _duration.inMinutes == entry.key,
                          onSelected: _saving
                              ? null
                              : (_) => setState(
                                  () => _duration = Duration(
                                    minutes: entry.key,
                                  ),
                                ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Ends ${DateFormat.jm().format(_startsAt.add(_duration))}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                  const SizedBox(height: 20),

                  TextFormField(
                    controller: _capacityController,
                    decoration: const InputDecoration(
                      labelText: 'Capacity *',
                      prefixIcon: Icon(Icons.people_outline),
                    ),
                    keyboardType: TextInputType.number,
                    enabled: !_saving,
                    validator: (value) {
                      final capacity = int.tryParse(value?.trim() ?? '');
                      if (capacity == null) return 'Enter a number';
                      if (capacity < 1) return 'Capacity must be at least 1';
                      if (capacity > 500) return 'That seems too high';
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  TextFormField(
                    controller: _locationController,
                    decoration: const InputDecoration(
                      labelText: 'Location',
                      prefixIcon: Icon(Icons.place_outlined),
                      hintText: 'Studio 1, Main floor…',
                    ),
                    enabled: !_saving,
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
                                // Reducing capacity below the booked count is
                                // allowed but does not evict anyone; say so.
                                'Existing bookings are kept. Lowering capacity '
                                'below the number already booked will not '
                                'remove anyone.',
                                style: theme.textTheme.bodySmall,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],

                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(widget.isEditing ? 'Save changes' : 'Add class'),
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
