import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/providers/database_provider.dart';
import '../providers/trainer_providers.dart';
import 'trainer_form_screen.dart';

/// Trainers (brain.md §6.2 for members, §6.3 for admin).
///
/// The same screen serves both: members see the roster, admins additionally
/// get add, edit and retire.
class TrainerListScreen extends ConsumerWidget {
  const TrainerListScreen({required this.isAdmin, super.key});

  final bool isAdmin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trainers = ref.watch(
      isAdmin ? allTrainersProvider : activeTrainersProvider,
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Trainers')),
      body: trainers.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Could not load: $error')),
        data: (list) => list.isEmpty
            ? _Empty(isAdmin: isAdmin)
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
                itemCount: list.length,
                itemBuilder: (context, index) =>
                    _TrainerCard(record: list[index], isAdmin: isAdmin),
              ),
      ),
      floatingActionButton: isAdmin
          ? FloatingActionButton.extended(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const TrainerFormScreen(),
                ),
              ),
              icon: const Icon(Icons.person_add_outlined),
              label: const Text('Add trainer'),
            )
          : null,
    );
  }
}

class _TrainerCard extends ConsumerWidget {
  const _TrainerCard({required this.record, required this.isAdmin});

  final TrainerRecord record;
  final bool isAdmin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final profile = record.profile;
    final trainer = record.trainer;
    final isRetired = !trainer.isActive;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(child: Text(_initials(profile.fullName))),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        profile.fullName,
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: isRetired ? theme.colorScheme.outline : null,
                        ),
                      ),
                      if (trainer.specialization?.isNotEmpty == true)
                        Text(
                          trainer.specialization!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.primary,
                          ),
                        ),
                    ],
                  ),
                ),
                if (isRetired)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Chip(
                      label: const Text('Retired'),
                      labelStyle: theme.textTheme.labelSmall,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                if (isAdmin) _AdminMenu(record: record),
              ],
            ),

            if (trainer.bio?.isNotEmpty == true) ...[
              const SizedBox(height: 10),
              Text(trainer.bio!, style: theme.textTheme.bodyMedium),
            ],

            if (trainer.certifications?.isNotEmpty == true) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    Icons.workspace_premium_outlined,
                    size: 16,
                    color: theme.colorScheme.outline,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      trainer.certifications!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  ),
                ],
              ),
            ],

            // Contact details are shown to admins only: a member should reach
            // a trainer through the gym, not their personal number.
            if (isAdmin && profile.phone?.isNotEmpty == true) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    Icons.phone_outlined,
                    size: 16,
                    color: theme.colorScheme.outline,
                  ),
                  const SizedBox(width: 6),
                  Text(profile.phone!, style: theme.textTheme.bodySmall),
                ],
              ),
            ],
          ],
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
}

class _AdminMenu extends ConsumerWidget {
  const _AdminMenu({required this.record});

  final TrainerRecord record;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isActive = record.trainer.isActive;

    return PopupMenuButton<String>(
      onSelected: (value) async {
        switch (value) {
          case 'edit':
            await Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => TrainerFormScreen(record: record),
              ),
            );
          case 'toggle':
            await _confirmToggle(context, ref);
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem(value: 'edit', child: Text('Edit')),
        PopupMenuItem(
          value: 'toggle',
          child: Text(isActive ? 'Retire' : 'Reinstate'),
        ),
      ],
    );
  }

  Future<void> _confirmToggle(BuildContext context, WidgetRef ref) async {
    final retiring = record.trainer.isActive;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(retiring ? 'Retire trainer?' : 'Reinstate trainer?'),
        content: Text(
          retiring
              // Say what does not happen: staff would otherwise fear retiring
              // a trainer erases the classes they taught.
              ? '${record.profile.fullName} will no longer appear to members '
                    'or be assignable to classes. Past classes keep their '
                    'trainer, and this can be undone.'
              : '${record.profile.fullName} will appear to members again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(retiring ? 'Retire' : 'Reinstate'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    await ref
        .read(profileDaoProvider)
        .setTrainerActive(record.trainer.id, isActive: !retiring);
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.isAdmin});

  final bool isAdmin;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.sports_outlined,
              size: 48,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text('No trainers yet', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              isAdmin
                  ? 'Add your trainers so they can be assigned to classes.'
                  : 'Trainer details will appear here.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
