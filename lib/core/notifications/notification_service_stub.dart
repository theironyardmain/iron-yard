import 'notification_kind.dart';

const bool isSupported = false;

Future<void> init({void Function(String payload)? onTap}) async {
  // No local notifications on web; reminders are an Android feature.
}

Future<String?> launchPayload() async => null;

Future<void> show({
  required int id,
  required String title,
  required String body,
  String? payload,
  bool urgent = false,
}) async {}

Future<void> schedule({
  required int id,
  required String title,
  required String body,
  required DateTime at,
  String? payload,
  NotificationKind kind = NotificationKind.reminder,
}) async {}

Future<void> scheduleDaily({
  required int id,
  required String title,
  required String body,
  required int hour,
  required int minute,
  String? payload,
  NotificationKind kind = NotificationKind.reminder,
}) async {}

Future<void> cancel(int id) async {}

Future<void> cancelKind(NotificationKind kind) async {}

Future<List<int>> pendingIds() async => const [];
