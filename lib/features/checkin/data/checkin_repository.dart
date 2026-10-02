import 'package:flutter/foundation.dart';

import '../../../core/notifications/notification_service.dart';
import '../../../data/local/daos/attendance_dao.dart';
import '../../../data/local/database.dart';
import '../../notifications/data/notification_payload.dart';
import 'checkin_settings.dart';

/// The daily self-reported check-in (brain.md §6.7).
///
/// A fallback source, not a replacement for QR: staff-verified scans remain the
/// trusted record for admin reporting (**owner decision, 2026-09-21** — self
/// reports stay member-facing and are shown separately). Records go into the
/// same `attendance` table tagged `self_reported`, and ride the existing
/// batched sync, so this costs nothing extra to run.
class CheckInRepository {
  CheckInRepository({
    required AppDatabase db,
    required CheckInSettingsStore settings,
  }) : _db = db,
       _settings = settings;

  final AppDatabase _db;
  final CheckInSettingsStore _settings;

  /// A stable id, so rescheduling replaces the existing reminder.
  static int get _reminderId =>
      NotificationKind.dailyCheckIn.idFor('daily-check-in');

  CheckInSettings readSettings() => _settings.read();

  /// Saves the preference and reschedules the reminder to match.
  Future<void> updateSettings(CheckInSettings settings) async {
    await _settings.write(settings);
    await applyReminder(settings);
  }

  /// Schedules or cancels the daily prompt to match [settings].
  Future<void> applyReminder([CheckInSettings? settings]) async {
    if (!Notifications.isSupported) return;

    final current = settings ?? readSettings();

    try {
      // Always cancel first: changing the time must not leave the old one
      // queued alongside the new.
      await Notifications.cancel(_reminderId);

      if (!current.enabled) return;

      await Notifications.scheduleDaily(
        id: _reminderId,
        title: 'Did you go to the gym today?',
        body: 'Tap to log your session.',
        hour: current.hour,
        minute: current.minute,
        payload: const NotificationPayload(
          type: NotificationTarget.checkIn,
          id: 'today',
        ).encode(),
        kind: NotificationKind.dailyCheckIn,
      );
    } catch (error, stack) {
      // A reminder is a convenience; failing to schedule it must not break
      // whatever triggered this.
      debugPrint('Could not apply check-in reminder: $error\n$stack');
    }
  }

  /// Records a self-reported session.
  ///
  /// Refuses a duplicate for the day, and never overwrites a staff scan — a
  /// member must not be able to downgrade a verified record.
  Future<CheckInResult> logSession({
    required String memberId,
    required DateTime startedAt,
    DateTime? endedAt,
  }) {
    return _db.attendanceDao.recordSelfReported(
      memberId: memberId,
      startedAt: startedAt,
      endedAt: endedAt,
    );
  }

  /// Whether the member already has attendance for [day], from either source.
  Future<bool> hasLoggedToday(String memberId, {DateTime? day}) =>
      _db.attendanceDao.hasCheckedIn(memberId, day);

  /// Today's record, if any — so the UI can show what is already logged.
  Future<AttendanceData?> todaysRecord(String memberId) async {
    final history = await _db.attendanceDao.historyFor(memberId, limit: 1);
    if (history.isEmpty) return null;

    final today = DateTime.now();
    final record = history.first;
    final date = record.attendanceDate;

    final isToday =
        date.year == today.year &&
        date.month == today.month &&
        date.day == today.day;

    return isToday ? record : null;
  }
}
