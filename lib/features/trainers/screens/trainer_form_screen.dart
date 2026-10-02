import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/providers/database_provider.dart';
import '../providers/trainer_providers.dart';

/// Add or edit a trainer (brain.md §6.3).
class TrainerFormScreen extends ConsumerStatefulWidget {
  const TrainerFormScreen({this.record, super.key});

  final TrainerRecord? record;

  bool get isEditing => record != null;

  @override
  ConsumerState<TrainerFormScreen> createState() => _TrainerFormScreenState();
}

class _TrainerFormScreenState extends ConsumerState<TrainerFormScreen> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameController;
  late final TextEditingController _phoneController;
  late final TextEditingController _emailController;
  late final TextEditingController _specializationController;
  late final TextEditingController _bioController;
  late final TextEditingController _certificationsController;

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final record = widget.record;

    _nameController = TextEditingController(
      text: record?.profile.fullName ?? '',
    );
    _phoneController = TextEditingController(text: record?.profile.phone ?? '');
    _emailController = TextEditingController(text: record?.profile.email ?? '');
    _specializationController = TextEditingController(
      text: record?.trainer.specialization ?? '',
    );
    _bioController = TextEditingController(text: record?.trainer.bio ?? '');
    _certificationsController = TextEditingController(
      text: record?.trainer.certifications ?? '',
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _specializationController.dispose();
    _bioController.dispose();
    _certificationsController.dispose();
    super.dispose();
  }

  String? _textOrNull(TextEditingController controller) {
    final text = controller.text.trim();
    return text.isEmpty ? null : text;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);

    final dao = ref.read(profileDaoProvider);
    final name = _nameController.text.trim();

    if (widget.isEditing) {
      await dao.updateTrainer(
        trainerId: widget.record!.trainer.id,
        profileId: widget.record!.profile.id,
        fullName: name,
        email: _textOrNull(_emailController),
        phone: _textOrNull(_phoneController),
        specialization: _textOrNull(_specializationController),
        bio: _textOrNull(_bioController),
        certifications: _textOrNull(_certificationsController),
      );
    } else {
      await dao.createTrainer(
        fullName: name,
        email: _textOrNull(_emailController),
        phone: _textOrNull(_phoneController),
        specialization: _textOrNull(_specializationController),
        bio: _textOrNull(_bioController),
        certifications: _textOrNull(_certificationsController),
      );
    }

    if (!mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(widget.isEditing ? 'Trainer updated' : '$name added'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isEditing ? 'Edit trainer' : 'Add trainer'),
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
                    validator: (value) => (value?.trim().isEmpty ?? true)
                        ? 'Enter the trainer name'
                        : null,
                  ),
                  const SizedBox(height: 16),

                  TextFormField(
                    controller: _specializationController,
                    decoration: const InputDecoration(
                      labelText: 'Specialisation',
                      prefixIcon: Icon(Icons.fitness_center),
                      hintText: 'Strength, Yoga, Rehab…',
                    ),
                    enabled: !_saving,
                  ),
                  const SizedBox(height: 16),

                  TextFormField(
                    controller: _phoneController,
                    decoration: const InputDecoration(
                      labelText: 'Phone',
                      prefixIcon: Icon(Icons.phone_outlined),
                      helperText: 'Staff only — not shown to members',
                    ),
                    keyboardType: TextInputType.phone,
                    enabled: !_saving,
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

                  TextFormField(
                    controller: _bioController,
                    decoration: const InputDecoration(
                      labelText: 'Bio',
                      prefixIcon: Icon(Icons.notes_outlined),
                      helperText: 'Shown to members',
                    ),
                    maxLines: 3,
                    enabled: !_saving,
                  ),
                  const SizedBox(height: 16),

                  TextFormField(
                    controller: _certificationsController,
                    decoration: const InputDecoration(
                      labelText: 'Certifications',
                      prefixIcon: Icon(Icons.workspace_premium_outlined),
                    ),
                    maxLines: 2,
                    enabled: !_saving,
                  ),

                  if (!widget.isEditing) ...[
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
                                // Be clear this does not create a login: a
                                // trainer account needs a Supabase Auth user,
                                // which is set up separately.
                                'This creates a trainer record for scheduling. '
                                'Sign-in access is set up separately.',
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
                        : Text(
                            widget.isEditing ? 'Save changes' : 'Add trainer',
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
