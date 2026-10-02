import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/providers/database_provider.dart';
import '../data/notification_router.dart';
import '../data/reminder_scheduler.dart';

final reminderSchedulerProvider = Provider<ReminderScheduler>(
  (ref) => ReminderScheduler(ref.watch(databaseProvider)),
);

/// Holds a tapped notification until a screen can act on it.
///
/// App-wide and long-lived: a cold-start payload is recorded before any screen
/// exists and must survive until one does.
final notificationRouterProvider = Provider<NotificationRouter>((ref) {
  final router = NotificationRouter();
  ref.onDispose(router.dispose);
  return router;
});
