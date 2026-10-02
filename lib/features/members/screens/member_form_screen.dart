import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../data/local/database.dart';
import '../providers/member_providers.dart';

/// Add or edit a member (brain.md §6.3).
///
/// Passing [member] switches the screen to edit mode.
class MemberFormScreen extends ConsumerStatefulWidget {
  const MemberFormScreen({this.member, super.key});

  final Profile? member;

  bool get isEditing => member != null;

  @override
  ConsumerState<MemberFormScreen> createState() => _MemberFormScreenState();
}

class _MemberFormScreenState extends ConsumerState<MemberFormScreen> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameController;
  late final TextEditingController _phoneController;
  late final TextEditingController _emailController;
  late final TextEditingController _addressController;
  late final TextEditingController _heightController;
  late final TextEditingController _weightController;
  late final TextEditingController _notesController;

  DateTime? _dateOfBirth;
  String? _gender;
  bool _saving = false;

  static const _genders = ['Male', 'Female', 'Other'];

  @override
  void initState() {
    super.initState();
    final member = widget.member;

    _nameController = TextEditingController(text: member?.fullName ?? '');
    _phoneController = TextEditingController(text: member?.phone ?? '');
    _emailController = TextEditingController(text: member?.email ?? '');
    _addressController = TextEditingController(text: member?.address ?? '');
    _heightController = TextEditingController(
      text: member?.heightCm?.toString() ?? '',
    );
    _weightController = TextEditingController(
      text: member?.weightKg == null
          ? ''
          : _formatWeight(member!.weightKg!),
    );
    _notesController = TextEditingController(text: member?.notes ?? '');
    _dateOfBirth = member?.dateOfBirth;
    _gender = member?.gender;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _addressController.dispose();
    _heightController.dispose();
    _weightController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  String? _emptyToNull(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  /// Drops a trailing ".0" so a whole-kilogram weight doesn't read "70.0".
  static String _formatWeight(double kg) {
    return kg % 1 == 0 ? kg.toInt().toString() : kg.toString();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);

    final repository = ref.read(memberRepositoryProvider);
    final name = _nameController.text.trim();
    final heightCm = int.tryParse(_heightController.text.trim());
    final weightKg = double.tryParse(_weightController.text.trim());

    if (widget.isEditing) {
      await repository.update(
        id: widget.member!.id,
        fullName: name,
        email: _emptyToNull(_emailController.text),
        phone: _emptyToNull(_phoneController.text),
        dateOfBirth: _dateOfBirth,
        gender: _gender,
        address: _emptyToNull(_addressController.text),
        heightCm: heightCm,
        weightKg: weightKg,
        notes: _emptyToNull(_notesController.text),
      );
    } else {
      await repository.create(
        fullName: name,
        email: _emptyToNull(_emailController.text),
        phone: _emptyToNull(_phoneController.text),
        dateOfBirth: _dateOfBirth,
        gender: _gender,
        address: _emptyToNull(_addressController.text),
        heightCm: heightCm,
        weightKg: weightKg,
        notes: _emptyToNull(_notesController.text),
      );
    }

    if (!mounted) return;

    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          widget.isEditing ? 'Member updated' : '$name added',
        ),
      ),
    );
  }

  Future<void> _pickDateOfBirth() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dateOfBirth ?? DateTime(now.year - 25),
      firstDate: DateTime(now.year - 100),
      lastDate: now,
      helpText: 'Date of birth',
    );

    if (picked != null) setState(() => _dateOfBirth = picked);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isEditing ? 'Edit member' : 'Add member'),
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
                      labelText: 'Full name *',
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                    textCapitalization: TextCapitalization.words,
                    enabled: !_saving,
                    validator: (value) {
                      final text = value?.trim() ?? '';
                      if (text.isEmpty) return 'Enter the member name';
                      if (text.length < 2) return 'Name is too short';
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  TextFormField(
                    controller: _phoneController,
                    decoration: const InputDecoration(
                      labelText: 'Phone',
                      prefixIcon: Icon(Icons.phone_outlined),
                    ),
                    keyboardType: TextInputType.phone,
                    enabled: !_saving,
                    validator: (value) {
                      final text = value?.trim() ?? '';
                      if (text.isEmpty) return null;
                      final digits = text.replaceAll(RegExp(r'[^0-9]'), '');
                      if (digits.length < 7) return 'Phone number is too short';
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  TextFormField(
                    controller: _emailController,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      prefixIcon: Icon(Icons.mail_outline),
                    ),
                    keyboardType: TextInputType.emailAddress,
                    enabled: !_saving,
                    validator: (value) {
                      final text = value?.trim() ?? '';
                      if (text.isEmpty) return null;
                      if (!text.contains('@') || !text.contains('.')) {
                        return 'Enter a valid email';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  InkWell(
                    onTap: _saving ? null : _pickDateOfBirth,
                    child: InputDecorator(
                      decoration: InputDecoration(
                        labelText: 'Date of birth',
                        prefixIcon: const Icon(Icons.cake_outlined),
                        suffixIcon: _dateOfBirth == null
                            ? null
                            : IconButton(
                                icon: const Icon(Icons.clear),
                                tooltip: 'Clear date',
                                onPressed: () =>
                                    setState(() => _dateOfBirth = null),
                              ),
                      ),
                      child: Text(
                        _dateOfBirth == null
                            ? 'Not set'
                            : DateFormat.yMMMd().format(_dateOfBirth!),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  DropdownButtonFormField<String>(
                    initialValue: _gender,
                    decoration: const InputDecoration(
                      labelText: 'Gender',
                      prefixIcon: Icon(Icons.wc_outlined),
                    ),
                    items: [
                      const DropdownMenuItem(child: Text('Not set')),
                      for (final gender in _genders)
                        DropdownMenuItem(value: gender, child: Text(gender)),
                    ],
                    onChanged: _saving
                        ? null
                        : (value) => setState(() => _gender = value),
                  ),
                  const SizedBox(height: 16),

                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _heightController,
                          decoration: const InputDecoration(
                            labelText: 'Height (cm)',
                            prefixIcon: Icon(Icons.height_outlined),
                          ),
                          keyboardType: TextInputType.number,
                          enabled: !_saving,
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return null;
                            }
                            final n = int.tryParse(value.trim());
                            if (n == null || n <= 0 || n > 300) {
                              return 'Enter a valid height';
                            }
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: _weightController,
                          decoration: const InputDecoration(
                            labelText: 'Weight (kg)',
                            prefixIcon: Icon(Icons.monitor_weight_outlined),
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
                              return 'Enter a valid weight';
                            }
                            return null;
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  TextFormField(
                    controller: _addressController,
                    decoration: const InputDecoration(
                      labelText: 'Address',
                      prefixIcon: Icon(Icons.home_outlined),
                    ),
                    maxLines: 2,
                    enabled: !_saving,
                  ),
                  const SizedBox(height: 16),

                  TextFormField(
                    controller: _notesController,
                    decoration: const InputDecoration(
                      labelText: 'Notes',
                      prefixIcon: Icon(Icons.notes_outlined),
                      helperText: 'Staff only — not shown to the member',
                    ),
                    maxLines: 3,
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
                        : Text(
                            widget.isEditing ? 'Save changes' : 'Add member',
                          ),
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
