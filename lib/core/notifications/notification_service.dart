import 'notification_kind.dart';
import 'notification_service_stub.dart'
    if (dart.library.io) 'notification_service_io.dart' as impl;

export 'notification_kind.dart';

/// Local notifications (brain.md §6.9).
///
/// All reminders in v1 are local — no push service, no server infrastructure,
/// no running cost. Resolved by conditional import because
/// `flutter_local_notifications` has no web implementation at all: the browser
/// preview silently does nothing rather than failing.
abstract final class Notifications {
  /// Whether this platform can show notifications.
  static bool get isSupported => impl.isSupported;

  /// Prepares the plugin and requests permission. Safe to call more than once.
  ///
  /// [onTap] receives the payload when a notification is tapped while the app
  /// is running. For a tap that *launched* the app, see [launchPayload].
  static Future<void> init({void Function(String payload)? onTap}) =>
      impl.init(onTap: onTap);

  /// The payload of a notification that launched the app, or null.
  ///
  /// Read once at startup: a cold start does not fire the tap callback, so
  /// without this a reminder tapped from a closed app would just open the
  /// home screen.
  static Future<String?> launchPayload() => impl.launchPayload();

  /// Shows a notification immediately.
  static Future<void> show({
    required int id,
    required String title,
    required String body,
    String? payload,
    bool urgent = false,
  }) => impl.show(
    id: id,
    title: title,
    body: body,
    payload: payload,
    urgent: urgent,
  );

  /// Schedules a notification for [at].
  ///
  /// Silently skipped when [at] is in the past — a reminder for a membership
  /// that already expired is noise, not help.
  static Future<void> schedule({
    required int id,
    required String title,
    required String body,
    required DateTime at,
    String? payload,
    NotificationKind kind = NotificationKind.reminder,
  }) => impl.schedule(
    id: id,
    title: title,
    body: body,
    at: at,
    payload: payload,
    kind: kind,
  );

  /// Schedules a notification that repeats at the same time every day.
  static Future<void> scheduleDaily({
    required int id,
    required String title,
    required String body,
    required int hour,
    required int minute,
    String? payload,
    NotificationKind kind = NotificationKind.reminder,
  }) => impl.scheduleDaily(
    id: id,
    title: title,
    body: body,
    hour: hour,
    minute: minute,
    payload: payload,
    kind: kind,
  );

  /// Cancels a scheduled or shown notification.
  static Future<void> cancel(int id) => impl.cancel(id);

  /// Cancels every notification in [kind]'s id range.
  ///
  /// Used before rescheduling a whole category, so a membership that was
  /// renewed does not leave its old expiry reminder queued.
  static Future<void> cancelKind(NotificationKind kind) =>
      impl.cancelKind(kind);

  /// Ids scheduled on this device, for diagnostics and tests.
  static Future<List<int>> pendingIds() => impl.pendingIds();

  /// Stable notification id for an announcement.
  ///
  /// Prefer [NotificationKind.idFor] for anything with a category.
  ///
  /// Derived from the id so re-delivery replaces the existing notification
  /// instead of stacking duplicates.
  static int idForAnnouncement(String announcementId) =>
      announcementId.hashCode.toUnsigned(30);
}
