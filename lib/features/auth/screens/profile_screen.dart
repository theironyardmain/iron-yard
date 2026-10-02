import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../data/local/database.dart';
import '../../../shared/providers/database_provider.dart';
import '../providers/auth_providers.dart';
import '../widgets/sign_out_action.dart';

/// View and edit the signed-in user's own profile (brain.md §6.1).
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();

  bool _loaded = false;
  bool _saving = false;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _load(String userId) async {
    final profile = await ref.read(profileDaoProvider).byId(userId);
    if (!mounted) return;

    setState(() {
      _nameController.text = profile?.fullName ?? '';
      _phoneController.text = profile?.phone ?? '';
      _loaded = true;
    });
  }

  Future<void> _save(String userId) async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);

    await ref.read(profileDaoProvider).updateProfile(
      userId,
      ProfilesCompanion(
        fullName: Value(_nameController.text.trim()),
        phone: Value(_phoneController.text.trim()),
      ),
    );

    if (!mounted) return;
    setState(() => _saving = false);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Profile saved')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(currentSessionProvider);

    if (session == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (!_loaded) {
      _load(session.userId);
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('My profile'),
        actions: const [SignOutAction()],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: CircleAvatar(
                      radius: 40,
                      child: Text(
                        _initials(session.fullName),
                        style: theme.textTheme.headlineSmall,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Center(
                    child: Chip(
                      label: Text(_roleLabel(session.role)),
                      avatar: Icon(_roleIcon(session.role), size: 18),
                    ),
                  ),
                  const SizedBox(height: 32),

                  TextFormField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: 'Full name',
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                    enabled: !_saving,
                    validator: (value) =>
                        (value == null || value.trim().isEmpty)
                        ? 'Enter your name'
                        : null,
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
                  ),
                  const SizedBox(height: 16),

                  // Email comes from the auth account, not the profile row, so
                  // it is shown but not editable here.
                  TextFormField(
                    initialValue: session.email ?? '—',
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      prefixIcon: Icon(Icons.mail_outline),
                      helperText: 'Contact the gym to change your email',
                    ),
                    enabled: false,
                  ),

                  const SizedBox(height: 32),
                  FilledButton(
                    onPressed: _saving ? null : () => _save(session.userId),
                    child: _saving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Save changes'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  static String _roleLabel(UserRole role) => switch (role) {
    UserRole.admin => 'Admin',
    UserRole.trainer => 'Trainer',
    UserRole.member => 'Member',
  };

  static IconData _roleIcon(UserRole role) => switch (role) {
    UserRole.admin => Icons.admin_panel_settings_outlined,
    UserRole.trainer => Icons.sports_outlined,
    UserRole.member => Icons.person_outline,
  };
}
