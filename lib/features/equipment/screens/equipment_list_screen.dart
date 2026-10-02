import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/local/database.dart';
import '../../../shared/providers/database_provider.dart';
import '../providers/equipment_providers.dart';
import 'equipment_detail_screen.dart';
import 'equipment_form_screen.dart';

/// Gym equipment inventory (brain.md §6.10).
///
/// Admins get add/edit/retire; trainers get a read-only view.
class EquipmentListScreen extends ConsumerWidget {
  const EquipmentListScreen({required this.isAdmin, super.key});

  final bool isAdmin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final equipment = ref.watch(
      isAdmin ? allEquipmentProvider : equipmentListProvider,
    );
    final dueForService = ref.watch(equipmentDueForServiceProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Equipment')),
      body: equipment.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Could not load: $error')),
        data: (list) {
          if (list.isEmpty) return _Empty(isAdmin: isAdmin);

          final dueIds = dueForService.maybeWhen(
            data: (due) => due.map((e) => e.id).toSet(),
            orElse: () => const <String>{},
          );
          final active = list.where((e) => e.status != 'retired').toList();
          final retired = list.where((e) => e.status == 'retired').toList();

          return ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
            children: [
              for (final item in active)
                _EquipmentTile(
                  item: item,
                  isAdmin: isAdmin,
                  dueForService: dueIds.contains(item.id),
                ),
              if (retired.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 24, 4, 8),
                  child: Text(
                    'Retired',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: Theme.of(context).colorScheme.outline,
                    ),
                  ),
                ),
                for (final item in retired)
                  _EquipmentTile(item: item, isAdmin: isAdmin, dueForService: false),
              ],
            ],
          );
        },
      ),
      floatingActionButton: isAdmin
          ? FloatingActionButton.extended(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const EquipmentFormScreen(),
                ),
              ),
              icon: const Icon(Icons.add),
              label: const Text('Add equipment'),
            )
          : null,
    );
  }
}

class _EquipmentTile extends ConsumerWidget {
  const _EquipmentTile({
    required this.item,
    required this.isAdmin,
    required this.dueForService,
  });

  final EquipmentItem item;
  final bool isAdmin;
  final bool dueForService;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isRetired = item.status == 'retired';

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        leading: CircleAvatar(
          backgroundColor: _statusColor(theme, item.status),
          child: Icon(_statusIcon(item.status), size: 20, color: Colors.white),
        ),
        title: Text(
          item.name,
          style: isRetired
              ? TextStyle(color: theme.colorScheme.outline)
              : null,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
              [
                if (item.category?.isNotEmpty == true) item.category!,
                if (item.quantity > 1) 'x${item.quantity}',
                if (item.location?.isNotEmpty == true) item.location!,
              ].join(' · '),
              style: theme.textTheme.bodySmall,
            ),
            if (dueForService && !isRetired) ...[
              const SizedBox(height: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.build_circle_outlined,
                    size: 14,
                    color: theme.colorScheme.error,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Due for service',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
        trailing: isAdmin ? _AdminMenu(item: item) : null,
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => EquipmentDetailScreen(
              equipmentId: item.id,
              isAdmin: isAdmin,
            ),
          ),
        ),
      ),
    );
  }

  static Color _statusColor(ThemeData theme, String status) => switch (status) {
    'working' => Colors.green.shade600,
    'under_repair' => Colors.orange.shade700,
    _ => theme.colorScheme.outline,
  };

  static IconData _statusIcon(String status) => switch (status) {
    'working' => Icons.check_circle_outline,
    'under_repair' => Icons.build_outlined,
    _ => Icons.block_outlined,
  };
}

class _AdminMenu extends ConsumerWidget {
  const _AdminMenu({required this.item});

  final EquipmentItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isRetired = item.status == 'retired';

    return PopupMenuButton<String>(
      onSelected: (value) async {
        switch (value) {
          case 'edit':
            await Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => EquipmentFormScreen(item: item),
              ),
            );
          case 'working':
            await ref.read(equipmentDaoProvider).setStatus(item.id, 'working');
          case 'under_repair':
            await ref
                .read(equipmentDaoProvider)
                .setStatus(item.id, 'under_repair');
          case 'retire':
            await _confirmRetire(context, ref);
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem(value: 'edit', child: Text('Edit')),
        if (!isRetired) ...[
          if (item.status != 'working')
            const PopupMenuItem(value: 'working', child: Text('Mark working')),
          if (item.status != 'under_repair')
            const PopupMenuItem(
              value: 'under_repair',
              child: Text('Mark under repair'),
            ),
          const PopupMenuItem(value: 'retire', child: Text('Retire')),
        ] else
          const PopupMenuItem(value: 'working', child: Text('Restore')),
      ],
    );
  }

  Future<void> _confirmRetire(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Retire this equipment?'),
        content: Text(
          '${item.name} will no longer appear in the active list. Its '
          'service history is kept, and this can be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Retire'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    await ref.read(equipmentDaoProvider).setStatus(item.id, 'retired');
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
              Icons.fitness_center_outlined,
              size: 48,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text('No equipment yet', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              isAdmin
                  ? 'Add your equipment to start tracking it.'
                  : 'Equipment details will appear here.',
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
