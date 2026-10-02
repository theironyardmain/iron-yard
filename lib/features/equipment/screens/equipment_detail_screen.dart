import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/utils/money.dart';
import '../providers/equipment_providers.dart';
import 'log_service_screen.dart';

/// One piece of equipment: details plus its service history (brain.md §6.10).
class EquipmentDetailScreen extends ConsumerWidget {
  const EquipmentDetailScreen({
    required this.equipmentId,
    required this.isAdmin,
    super.key,
  });

  final String equipmentId;
  final bool isAdmin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final equipment = ref.watch(allEquipmentProvider);
    final history = ref.watch(serviceHistoryProvider(equipmentId));
    final theme = Theme.of(context);

    final item = equipment.maybeWhen(
      data: (list) => list.where((e) => e.id == equipmentId).firstOrNull,
      orElse: () => null,
    );

    return Scaffold(
      appBar: AppBar(title: Text(item?.name ?? 'Equipment')),
      body: item == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _Row(
                          icon: Icons.category_outlined,
                          label: 'Category',
                          value: item.category ?? '—',
                        ),
                        _Row(
                          icon: Icons.numbers_outlined,
                          label: 'Quantity',
                          value: item.quantity.toString(),
                        ),
                        _Row(
                          icon: Icons.place_outlined,
                          label: 'Location',
                          value: item.location ?? '—',
                        ),
                        _Row(
                          icon: Icons.event_outlined,
                          label: 'Purchased',
                          value: item.purchaseDate == null
                              ? '—'
                              : DateFormat.yMMMd().format(item.purchaseDate!),
                        ),
                        _Row(
                          icon: Icons.currency_rupee,
                          label: 'Cost',
                          value: item.costMinor == null
                              ? '—'
                              : Money.format(item.costMinor!),
                        ),
                        _Row(
                          icon: Icons.build_circle_outlined,
                          label: 'Service every',
                          value: item.serviceIntervalDays == null
                              ? 'Not scheduled'
                              : '${item.serviceIntervalDays} days',
                        ),
                        _Row(
                          icon: Icons.history_outlined,
                          label: 'Last serviced',
                          value: item.lastServicedAt == null
                              ? 'Never'
                              : DateFormat.yMMMd().format(item.lastServicedAt!),
                        ),
                        if (item.notes?.isNotEmpty == true) ...[
                          const SizedBox(height: 8),
                          Text(item.notes!, style: theme.textTheme.bodyMedium),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text('Service history', style: theme.textTheme.titleSmall),
                const SizedBox(height: 8),
                history.when(
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (error, _) => Text('Could not load: $error'),
                  data: (logs) {
                    if (logs.isEmpty) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: Text(
                          'No service events logged yet.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.outline,
                          ),
                        ),
                      );
                    }
                    return Column(
                      children: [
                        for (final log in logs)
                          Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              leading: const Icon(Icons.build_outlined),
                              title: Text(log.description),
                              subtitle: Text(
                                DateFormat.yMMMd().format(log.servicedAt),
                              ),
                              trailing: log.costMinor == null
                                  ? null
                                  : Text(Money.format(log.costMinor!)),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ],
            ),
      floatingActionButton: isAdmin && item != null
          ? FloatingActionButton.extended(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      LogServiceScreen(equipmentId: item.id, name: item.name),
                ),
              ),
              icon: const Icon(Icons.build_outlined),
              label: const Text('Log service'),
            )
          : null,
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.outline),
          const SizedBox(width: 12),
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ),
          Expanded(child: Text(value, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}
