import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import 'notification_kind.dart';

const bool isSupported = true;

final FlutterLocalNotificationsPlugin _plugin =
    FlutterLocalNotificationsPlugin();

bool _initialised = false;

/// Channels are declared per purpose so a member can silence reminders without
/// losing urgent gym notices.
const AndroidNotificationChannel _remindersChannel = AndroidNotificationChannel(
  'reminders',
  'Reminders',
  description: 'Membership expiry, payments, classes and daily check-in',
  importance: Importance.defaultImportance,
);

const AndroidNotificationChannel _announcementsChannel =
    AndroidNotificationChannel(
      'announcements',
      'Gym announcements',
      description: 'News and notices from the gym',
      importance: Importance.defaultImportance,
    );

const AndroidNotificationChannel _urgentChannel = AndroidNotificationChannel(
  'announcements_urgent',
  'Urgent notices',
  description: 'Closures and other time-critical messages',
  importance: Importance.high,
);

const Map<String, AndroidNotificationChannel> _channels = {
  'reminders': _remindersChannel,
  'announcements': _announcementsChannel,
  'announcements_urgent': _urgentChannel,
};

Future<void> init({void Function(String payload)? onTap}) async {
  if (_initialised) return;

  const settings = InitializationSettings(
    android: AndroidInitializationSettings('@mipmap/ic_launcher'),
  );

  try {
    // Scheduling needs a timezone database: a reminder set for 09:00 must fire
    // at 09:00 local, including across a DST change.
    tz_data.initializeTimeZones();

    await _plugin.initialize(
      settings: settings,
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        if (payload != null && payload.isNotEmpty) onTap?.call(payload);
      },
    );

    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();

    for (final channel in _channels.values) {
      await android?.createNotificationChannel(channel);
    }

    // Android 13+ requires an explicit grant. A refusal is not an error: the
    // app works without notifications, it just cannot remind anyone.
    await android?.requestNotificationsPermission();

    _initialised = true;
  } catch (error, stack) {
    debugPrint('Notifications unavailable: $error\n$stack');
  }
}

NotificationDetails _detailsFor(NotificationKind kind, String body) {
  final channel = _channels[kind.channel] ?? _remindersChannel;

  return NotificationDetails(
    android: AndroidNotificationDetails(
      channel.id,
      channel.name,
      channelDescription: channel.description,
      importance: channel.importance,
      priority: kind.isUrgent ? Priority.high : Priority.defaultPriority,
      // Bodies are longer than one line.
      styleInformation: BigTextStyleInformation(body),
    ),
  );
}

Future<void> show({
  required int id,
  required String title,
  required String body,
  String? payload,
  bool urgent = false,
}) async {
  if (!_initialised) await init();

  final kind = urgent
      ? NotificationKind.urgent
      : NotificationKind.announcement;

  try {
    await _plugin.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: _detailsFor(kind, body),
      payload: payload,
    );
  } catch (error) {
    // A failed notification must never break the flow that triggered it.
    debugPrint('Failed to show notification: $error');
  }
}

Future<void> schedule({
  required int id,
  required String title,
  required String body,
  required DateTime at,
  String? payload,
  NotificationKind kind = NotificationKind.reminder,
}) async {
  if (!_initialised) await init();

  // A reminder for something that already happened is noise.
  if (at.isBefore(DateTime.now())) return;

  try {
    await _plugin.zonedSchedule(
      id: id,
      title: title,
      body: body,
      scheduledDate: tz.TZDateTime.from(at, tz.local),
      notificationDetails: _detailsFor(kind, body),
      // inexact so no exact-alarm permission is needed. A reminder arriving a
      // few minutes late is fine; being refused install-time permission is not.
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      payload: payload,
    );
  } catch (error) {
    debugPrint('Failed to schedule notification $id: $error');
  }
}

Future<void> scheduleDaily({
  required int id,
  required String title,
  required String body,
  required int hour,
  required int minute,
  String? payload,
  NotificationKind kind = NotificationKind.reminder,
}) async {
  if (!_initialised) await init();

  try {
    await _plugin.zonedSchedule(
      id: id,
      title: title,
      body: body,
      scheduledDate: _nextInstanceOf(hour, minute),
      notificationDetails: _detailsFor(kind, body),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      // Repeats daily at the same wall-clock time.
      matchDateTimeComponents: DateTimeComponents.time,
      payload: payload,
    );
  } catch (error) {
    debugPrint('Failed to schedule daily notification $id: $error');
  }
}

/// The next occurrence of [hour]:[minute], today or tomorrow.
tz.TZDateTime _nextInstanceOf(int hour, int minute) {
  final now = tz.TZDateTime.now(tz.local);
  var next = tz.TZDateTime(
    tz.local,
    now.year,
    now.month,
    now.day,
    hour,
    minute,
  );

  if (!next.isAfter(now)) {
    next = next.add(const Duration(days: 1));
  }
  return next;
}

Future<void> cancel(int id) async {
  try {
    await _plugin.cancel(id: id);
  } catch (error) {
    debugPrint('Failed to cancel notification: $error');
  }
}

Future<void> cancelKind(NotificationKind kind) async {
  try {
    final pending = await _plugin.pendingNotificationRequests();
    for (final request in pending) {
      if (kind.owns(request.id)) {
        await _plugin.cancel(id: request.id);
      }
    }
  } catch (error) {
    debugPrint('Failed to cancel ${kind.name} notifications: $error');
  }
}

/// The payload of a notification that launched the app.
///
/// A cold start never fires the tap callback, so this is the only way to know
/// the app was opened from a reminder.
Future<String?> launchPayload() async {
  try {
    final details = await _plugin.getNotificationAppLaunchDetails();
    if (details?.didNotificationLaunchApp != true) return null;
    return details?.notificationResponse?.payload;
  } catch (error) {
    debugPrint('Could not read launch details: $error');
    return null;
  }
}

Future<List<int>> pendingIds() async {
  try {
    final pending = await _plugin.pendingNotificationRequests();
    return pending.map((r) => r.id).toList();
  } catch (error) {
    debugPrint('Could not read pending notifications: $error');
    return const [];
  }
}
