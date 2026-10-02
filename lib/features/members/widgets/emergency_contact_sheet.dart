import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/local/database.dart';
import '../providers/member_providers.dart';

/// Edits a member's emergency contact (brain.md §6.2).
///
/// This data is stored on the device only and is never synced to Supabase,
/// which the sheet states plainly — staff should know it will not follow the
/// member to another device.
Future<void> showEmergencyContactSheet({
  required BuildContext context,
  required WidgetRef ref,
  required String memberId,
  EmergencyContact? existing,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: _EmergencyContactForm(memberId: memberId, existing: existing),
    ),
  );
}

class _EmergencyContactForm extends ConsumerStatefulWidget {
  const _EmergencyContactForm({required this.memberId, this.existing});

  final String memberId;
  final EmergencyContact? existing;

  @override
  ConsumerState<_EmergencyContactForm> createState() =>
      _EmergencyContactFormState();
}

class _EmergencyContactFormState
    extends ConsumerState<_EmergencyContactForm> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameController;
  late final TextEditingController _phoneController;
  late final TextEditingController _relationshipController;

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: widget.existing?.name ?? '',
    );
    _phoneController = TextEditingController(
      text: widget.existing?.phone ?? '',
    );
    _relationshipController = TextEditingController(
      text: widget.existing?.relationship ?? '',
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _relationshipController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);

    final relationship = _relationshipController.text.trim();

    await ref.read(memberRepositoryProvider).setEmergencyContact(
      memberId: widget.memberId,
      name: _nameController.text.trim(),
      phone: _phoneController.text.trim(),
      relationship: relationship.isEmpty ? null : relationship,
    );

    ref.invalidate(emergencyContactProvider(widget.memberId));

    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Emergency contact',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'Saved on this device only — it is not uploaded and will not '
              'appear on another device.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
            const SizedBox(height: 20),

            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Name *',
                prefixIcon: Icon(Icons.person_outline),
              ),
              textCapitalization: TextCapitalization.words,
              enabled: !_saving,
              validator: (value) => (value?.trim().isEmpty ?? true)
                  ? 'Enter a contact name'
                  : null,
            ),
            const SizedBox(height: 16),

            TextFormField(
              controller: _phoneController,
              decoration: const InputDecoration(
                labelText: 'Phone *',
                prefixIcon: Icon(Icons.phone_outlined),
              ),
              keyboardType: TextInputType.phone,
              enabled: !_saving,
              validator: (value) {
                final text = value?.trim() ?? '';
                if (text.isEmpty) return 'Enter a contact number';
                final digits = text.replaceAll(RegExp(r'[^0-9]'), '');
                if (digits.length < 7) return 'Phone number is too short';
                return null;
              },
            ),
            const SizedBox(height: 16),

            TextFormField(
              controller: _relationshipController,
              decoration: const InputDecoration(
                labelText: 'Relationship',
                prefixIcon: Icon(Icons.group_outlined),
                hintText: 'Spouse, parent, friend…',
              ),
              textCapitalization: TextCapitalization.sentences,
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
                  : const Text('Save contact'),
            ),
          ],
        ),
      ),
    );
  }
}
