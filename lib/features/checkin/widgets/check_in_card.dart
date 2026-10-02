import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_constants.dart';
import '../../../data/local/database.dart';
import '../providers/checkin_providers.dart';
import '../screens/check_in_settings_screen.dart';
import 'check_in_sheet.dart';

/// Today's check-in state on the member home (brain.md §6.7).
class CheckInCard extends ConsumerWidget {
  const CheckInCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final today = ref.watch(todaysCheckInProvider);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: today.when(
          loading: () => const SizedBox(
            height: 56,
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (error, _) => Text('Could not load today: $error'),
          data: (record) {
            if (record == null) return const _NotLoggedYet();

            final isVerified =
                record.source == AttendanceSource.qrScan.wireValue;

            return Row(
              children: [
                CircleAvatar(
                  backgroundColor: theme.colorScheme.primaryContainer,
                  child: Icon(
                    isVerified ? Icons.qr_code_2 : Icons.check,
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isVerified ? 'Checked in today' : 'Session logged',
                        style: theme.textTheme.titleSmall,
                      ),
                      Text(
                        _describe(record),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.outline,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.more_horiz),
                  tooltip: 'Check-in settings',
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const CheckInSettingsScreen(),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  static String _describe(AttendanceData record) {
    final start = record.checkInAt;
    final end = record.checkOutAt;

    if (start == null) return 'Recorded today';
    final startText = DateFormat.jm().format(start);
    return end == null
        ? startText
        : '$startText – ${DateFormat.jm().format(end)}';
  }
}

class _NotLoggedYet extends ConsumerWidget {
  const _NotLoggedYet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return Row(
      children: [
        CircleAvatar(
          backgroundColor: theme.colorScheme.surfaceContainerHighest,
          child: Icon(
            Icons.fitness_center,
            color: theme.colorScheme.outline,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Trained today?', style: theme.textTheme.titleSmall),
              Text(
                'Log it yourself if you were not scanned in.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        FilledButton.tonal(
          onPressed: () async {
            final logged = await showCheckInSheet(context);
            if (logged && context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Session logged')),
              );
            }
          },
          child: const Text('Log'),
        ),
      ],
    );
  }
}
