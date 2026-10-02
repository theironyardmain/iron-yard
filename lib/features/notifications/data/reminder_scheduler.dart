import 'package:flutter/foundation.dart';

import '../../../core/notifications/notification_service.dart';
import '../../../core/utils/money.dart';
import '../../../data/local/database.dart';
import 'notification_payload.dart';

/// When reminders fire, in days before the event.
class ReminderTiming {
  const ReminderTiming._();

  /// Membership expiry: a week out to allow a renewal conversation, then the
  /// day before as a last call.
  static const List<int> membershipExpiryDays = [7, 1];

  /// Class reminders, in hours before the class starts.
  static const int classReminderHours = 2;

  /// Hour of day reminders fire. Late morning: a notification at 07:00 is
  /// likely to be missed or resented.
  static const int reminderHour = 10;
}

/// Schedules the local reminders in brain.md §6.9.
///
/// Everything is local — no push service, no server, no running cost. The whole
/// set is rebuilt on each run rather than diffed: a membership that was renewed
/// or a class that was cancelled must not leave a stale reminder queued, and
/// rebuilding is simpler to get right than reconciling.
class ReminderScheduler {
  ReminderScheduler(this._db);

  final AppDatabase _db;

  /// Rebuilds every reminder for [memberId].
  ///
  /// Returns how many were scheduled. Safe to call repeatedly; call it after a
  /// sync, a renewal or a booking change.
  Future<int> rescheduleFor(String memberId, {DateTime? asOf}) async {
    if (!Notifications.isSupported) return 0;

    final now = asOf ?? DateTime.now();
    var scheduled = 0;

    try {
      await Notifications.cancelKind(NotificationKind.membershipExpiry);
      await Notifications.cancelKind(NotificationKind.paymentDue);
      await Notifications.cancelKind(NotificationKind.classReminder);

      scheduled += await _scheduleMembershipExpiry(memberId, now);
      scheduled += await _schedulePaymentDue(memberId, now);
      scheduled += await _scheduleClassReminders(memberId, now);
    } catch (error, stack) {
      // Reminders are a convenience; failing to schedule one must not break
      // the sync or screen that triggered this.
      debugPrint('Could not reschedule reminders: $error\n$stack');
    }

    return scheduled;
  }

  /// Membership expiry reminders (brain.md §6.9).
  Future<int> _scheduleMembershipExpiry(String memberId, DateTime now) async {
    final membership = await _db.membershipDao.currentFor(memberId);
    if (membership == null || membership.status == 'cancelled') return 0;

    final end = membership.endDate;
    var scheduled = 0;

    for (final daysBefore in ReminderTiming.membershipExpiryDays) {
      final fireOn = DateTime(
        end.year,
        end.month,
        end.day - daysBefore,
        ReminderTiming.reminderHour,
      );

      if (!fireOn.isAfter(now)) continue;

      await Notifications.schedule(
        id: NotificationKind.membershipExpiry.idFor(
          '${membership.id}-$daysBefore',
        ),
        title: 'Membership expiring',
        body: daysBefore == 1
            ? 'Your membership ends tomorrow. Renew at the desk to keep '
                  'training.'
            : 'Your membership ends in $daysBefore days.',
        at: fireOn,
        payload: NotificationPayload(
          type: NotificationTarget.membership,
          id: membership.id,
        ).encode(),
        kind: NotificationKind.membershipExpiry,
      );
      scheduled++;
    }

    return scheduled;
  }

  /// Payment due reminders (brain.md §6.9).
  ///
  /// A payment recorded as pending is money the gym is still owed.
  Future<int> _schedulePaymentDue(String memberId, DateTime now) async {
    final pending = await _db.paymentDao.pendingPayments();
    var scheduled = 0;

    for (final payment in pending.where((p) => p.memberId == memberId)) {
      // A week after it was recorded, so staff are not nagging immediately.
      final fireOn = DateTime(
        payment.paidAt.year,
        payment.paidAt.month,
        payment.paidAt.day + 7,
        ReminderTiming.reminderHour,
      );

      if (!fireOn.isAfter(now)) continue;

      await Notifications.schedule(
        id: NotificationKind.paymentDue.idFor(payment.id),
        title: 'Payment outstanding',
        body: '${Money.format(payment.amountMinor)} is still marked as '
            'pending.',
        at: fireOn,
        payload: NotificationPayload(
          type: NotificationTarget.payment,
          id: payment.id,
        ).encode(),
        kind: NotificationKind.paymentDue,
      );
      scheduled++;
    }

    return scheduled;
  }

  /// Class reminders for classes the member has booked (brain.md §6.9).
  Future<int> _scheduleClassReminders(String memberId, DateTime now) async {
    final bookings = await _db.classDao.watchBookingsFor(memberId).first;
    var scheduled = 0;

    for (final booking in bookings) {
      if (booking.status != 'booked') continue;

      final gymClass = await _db.classDao.classById(booking.classId);
      if (gymClass == null ||
          gymClass.isDeleted ||
          gymClass.status == 'cancelled') {
        continue;
      }

      final fireAt = gymClass.startsAt.subtract(
        const Duration(hours: ReminderTiming.classReminderHours),
      );

      if (!fireAt.isAfter(now)) continue;

      await Notifications.schedule(
        id: NotificationKind.classReminder.idFor(booking.id),
        title: gymClass.name,
        body: 'Starts in ${ReminderTiming.classReminderHours} hours'
            '${gymClass.location == null ? '' : ' at ${gymClass.location}'}.',
        at: fireAt,
        payload: NotificationPayload(
          type: NotificationTarget.gymClass,
          id: gymClass.id,
        ).encode(),
        kind: NotificationKind.classReminder,
      );
      scheduled++;
    }

    return scheduled;
  }

  /// Cancels every reminder. Called on sign-out, along with the data purge.
  Future<void> cancelAll() async {
    if (!Notifications.isSupported) return;

    for (final kind in [
      NotificationKind.membershipExpiry,
      NotificationKind.paymentDue,
      NotificationKind.classReminder,
      NotificationKind.dailyCheckIn,
    ]) {
      await Notifications.cancelKind(kind);
    }
  }
}
