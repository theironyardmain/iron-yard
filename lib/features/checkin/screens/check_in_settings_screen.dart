import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/notifications/notification_service.dart';
import '../providers/checkin_providers.dart';

/// Daily check-in reminder settings (brain.md §6.7).
class CheckInSettingsScreen extends ConsumerWidget {
  const CheckInSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final settings = ref.watch(checkInSettingsProvider);
    final controller = ref.read(checkInSettingsProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('Daily check-in')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'A daily reminder to log your session if you were not scanned in '
            'at the desk.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 20),

          if (!Notifications.isSupported)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Icon(
                      Icons.notifications_off_outlined,
                      size: 20,
                      color: theme.colorScheme.outline,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Reminders need the Android app.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.outline,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
          else ...[
            Card(
              child: SwitchListTile(
                value: settings.enabled,
                onChanged: (value) =>
                    controller.setEnabled(enabled: value),
                title: const Text('Daily reminder'),
                subtitle: Text(
                  settings.enabled
                      ? 'Asks at ${settings.formattedTime}'
                      : 'Off',
                ),
                secondary: const Icon(Icons.alarm),
              ),
            ),
            if (settings.enabled)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.schedule),
                  title: const Text('Reminder time'),
                  subtitle: Text(settings.formattedTime),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    final picked = await showTimePicker(
                      context: context,
                      initialTime: TimeOfDay(
                        hour: settings.hour,
                        minute: settings.minute,
                      ),
                      helpText: 'Remind me at',
                    );

                    if (picked == null) return;
                    await controller.setTime(
                      hour: picked.hour,
                      minute: picked.minute,
                    );
                  },
                ),
              ),
          ],

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
                      // Owner decision, 2026-09-21: self-reports stay
                      // member-facing. Say so, rather than letting a member
                      // assume these count toward gym records.
                      'Sessions you log are your own record. The gym counts '
                      'staff scans at the desk as official attendance.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
