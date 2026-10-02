import 'package:flutter_test/flutter_test.dart';
import 'package:iron_yard/core/constants/app_constants.dart';
import 'package:iron_yard/core/notifications/notification_service.dart';
import 'package:iron_yard/data/local/database.dart';
import 'package:iron_yard/features/notifications/data/notification_payload.dart';
import 'package:iron_yard/features/notifications/data/notification_router.dart';
import 'package:iron_yard/features/notifications/data/reminder_scheduler.dart';

void main() {
  group('NotificationKind id ranges', () {
    test('every kind has a distinct range', () {
      // Android identifies a notification by one int. Overlapping ranges would
      // let a membership reminder silently replace a class reminder.
      for (final a in NotificationKind.values) {
        for (final b in NotificationKind.values) {
          if (a == b) continue;
          expect(
            a.base >= b.rangeEnd || b.base >= a.rangeEnd,
            isTrue,
            reason: '${a.name} and ${b.name} overlap',
          );
        }
      }
    });

    test('an id belongs only to its own kind', () {
      for (final kind in NotificationKind.values) {
        final id = kind.idFor('some-uuid');

        expect(kind.owns(id), isTrue, reason: kind.name);

        for (final other in NotificationKind.values) {
          if (other == kind) continue;
          expect(other.owns(id), isFalse, reason: '${other.name} claimed $id');
        }
      }
    });

    test('ids are stable for the same key', () {
      // An unstable id would stack duplicates instead of replacing.
      expect(
        NotificationKind.classReminder.idFor('booking-1'),
        NotificationKind.classReminder.idFor('booking-1'),
      );
    });

    test('ids differ between keys', () {
      expect(
        NotificationKind.classReminder.idFor('booking-1'),
        isNot(NotificationKind.classReminder.idFor('booking-2')),
      );
    });

    test('ids stay inside a 32-bit positive int', () {
      // Android rejects ids outside this range.
      for (final kind in NotificationKind.values) {
        for (final key in ['', 'a', 'a-very-long-uuid-value-here', '12345']) {
          final id = kind.idFor(key);
          expect(id, greaterThanOrEqualTo(0));
          expect(id, lessThan(1 << 31));
        }
      }
    });

    test('reminders and urgent notices use different channels', () {
      // So a member can silence reminders without losing closure notices.
      expect(
        NotificationKind.membershipExpiry.channel,
        isNot(NotificationKind.urgent.channel),
      );
      expect(NotificationKind.urgent.isUrgent, isTrue);
      expect(NotificationKind.membershipExpiry.isUrgent, isFalse);
    });

    test('all reminder kinds share one channel', () {
      final channels = {
        NotificationKind.membershipExpiry.channel,
        NotificationKind.paymentDue.channel,
        NotificationKind.classReminder.channel,
        NotificationKind.dailyCheckIn.channel,
      };
      expect(channels, hasLength(1));
    });
  });

  group('NotificationPayload', () {
    test('round-trips', () {
      const payload = NotificationPayload(
        type: NotificationTarget.gymClass,
        id: 'abc-123',
      );

      final parsed = NotificationPayload.tryParse(payload.encode());

      expect(parsed!.type, NotificationTarget.gymClass);
      expect(parsed.id, 'abc-123');
    });

    test('uses "class" on the wire, not the Dart enum name', () {
      expect(
        const NotificationPayload(
          type: NotificationTarget.gymClass,
          id: 'x',
        ).encode(),
        'class:x',
      );
    });

    test('handles ids containing a colon', () {
      // Splitting on the last colon would corrupt the id.
      final parsed = NotificationPayload.tryParse('membership:a:b:c');
      expect(parsed!.id, 'a:b:c');
    });

    group('rejects unusable payloads', () {
      // A payload written by an older version must not crash the launch path.
      final cases = <String, String?>{
        'null': null,
        'empty': '',
        'no separator': 'membership',
        'unknown type': 'mystery:abc',
        'empty type': ':abc',
        'empty id': 'membership:',
      };

      cases.forEach((label, raw) {
        test(label, () => expect(NotificationPayload.tryParse(raw), isNull));
      });
    });

    test('every target round-trips through its wire value', () {
      for (final target in NotificationTarget.values) {
        expect(NotificationTarget.fromString(target.wireValue), target);
      }
    });
  });

  group('ReminderTiming', () {
    test('expiry reminders are ordered furthest-out first', () {
      final days = ReminderTiming.membershipExpiryDays;
      expect(days, isNotEmpty);
      for (var i = 1; i < days.length; i++) {
        expect(days[i], lessThan(days[i - 1]));
      }
    });

    test('reminders fire at a civil hour', () {
      // A notification at 06:00 is missed or resented.
      expect(ReminderTiming.reminderHour, greaterThanOrEqualTo(8));
      expect(ReminderTiming.reminderHour, lessThanOrEqualTo(20));
    });

    test('class reminders leave time to travel', () {
      expect(ReminderTiming.classReminderHours, greaterThanOrEqualTo(1));
    });
  });

  group('ReminderScheduler', () {
    late AppDatabase db;
    late ReminderScheduler scheduler;
    late String memberId;
    late String planId;

    setUp(() async {
      db = AppDatabase.memory();
      scheduler = ReminderScheduler(db);
      memberId = await db.profileDao.createMember(fullName: 'Member');
      planId = await db.membershipDao.createPlan(
        name: 'Monthly',
        durationDays: 30,
        priceMinor: 150000,
      );
    });

    tearDown(() async => db.close());

    // The test VM has dart:io, so the conditional import resolves to the
    // Android implementation and the scheduler runs for real. The plugin has
    // no platform behind it, so every call fails inside the service and is
    // swallowed — which is exactly the guarantee these tests check: the
    // reminder path must never break the sync or screen that triggered it.
    test('reports support in an environment with dart:io', () {
      expect(Notifications.isSupported, isTrue);
    });

    test('never throws, even with no data at all', () async {
      await expectLater(scheduler.rescheduleFor('nobody'), completes);
    });

    test('never throws with a full set of data', () async {
      await db.membershipDao.assignPlan(memberId: memberId, planId: planId);
      await db.paymentDao.record(
        memberId: memberId,
        amountMinor: 150000,
        method: PaymentMethod.cash,
        pending: true,
      );

      final future = DateTime.now().add(const Duration(days: 2));
      final classId = await db.classDao.createClass(
        name: 'Yoga',
        startsAt: future,
        endsAt: future.add(const Duration(hours: 1)),
        capacity: 10,
      );
      await db.classDao.book(classId: classId, memberId: memberId);

      await expectLater(scheduler.rescheduleFor(memberId), completes);
    });

    test('cancelAll never throws', () async {
      await expectLater(scheduler.cancelAll(), completes);
    });
  });

  group('NotificationRouter', () {
    late NotificationRouter router;

    setUp(() => router = NotificationRouter());
    tearDown(() => router.dispose());

    test('holds a payload until something consumes it', () {
      // A cold-start tap is recorded before any screen exists, so it has to
      // wait rather than be dropped.
      router.handle('class:abc-123');

      expect(router.hasPending, isTrue);
      expect(router.pending!.id, 'abc-123');
    });

    test('consuming clears it, so it is acted on once', () {
      router.handle('membership:m1');

      final first = router.consume();
      expect(first!.id, 'm1');

      expect(router.consume(), isNull, reason: 'not re-navigated');
      expect(router.hasPending, isFalse);
    });

    test('consuming an empty router returns null', () {
      expect(router.consume(), isNull);
    });

    test('ignores an unparseable payload', () {
      router.handle('not a payload');
      router.handle('');
      router.handle(null);

      expect(router.hasPending, isFalse);
    });

    test('a later tap replaces an unconsumed one', () {
      // Two notifications tapped before the app is ready: the most recent is
      // what the user actually meant.
      router.handle('membership:m1');
      router.handle('class:c1');

      expect(router.consume()!.type, NotificationTarget.gymClass);
    });

    test('notifies listeners when a payload arrives', () {
      var notified = 0;
      router.addListener(() => notified++);

      router.handle('class:abc');
      expect(notified, 1);
    });

    test('clear drops anything waiting', () {
      // Sign-out purges the data a payload refers to.
      router.handle('membership:m1');
      router.clear();

      expect(router.hasPending, isFalse);
    });

    test('clearing an empty router does not notify', () {
      var notified = 0;
      router.addListener(() => notified++);

      router.clear();
      expect(notified, 0);
    });
  });

  group('tabFor', () {
    ({String label, NotificationTarget target, MemberTab tab}) expectation(
      String label,
      NotificationTarget target,
      MemberTab tab,
    ) => (label: label, target: target, tab: tab);

    final cases = [
      expectation('membership expiry opens home', NotificationTarget.membership,
          MemberTab.home),
      expectation('payment due opens home', NotificationTarget.payment,
          MemberTab.home),
      expectation('check-in opens home', NotificationTarget.checkIn,
          MemberTab.home),
      expectation('class reminder opens classes', NotificationTarget.gymClass,
          MemberTab.classes),
      expectation('announcement opens news', NotificationTarget.announcement,
          MemberTab.news),
    ];

    for (final item in cases) {
      test(item.label, () {
        final payload = NotificationPayload(type: item.target, id: 'x');
        expect(tabFor(payload), item.tab);
      });
    }

    test('every target maps somewhere', () {
      // A missing case would silently leave the member on the wrong tab.
      for (final target in NotificationTarget.values) {
        expect(
          () => tabFor(NotificationPayload(type: target, id: 'x')),
          returnsNormally,
          reason: target.name,
        );
      }
    });

    test('tab indices match the member shell order', () {
      // MemberShell destinations are Home, Plans, Classes, News.
      expect(MemberTab.home.index, 0);
      expect(MemberTab.plans.index, 1);
      expect(MemberTab.classes.index, 2);
      expect(MemberTab.news.index, 3);
    });
  });
}
