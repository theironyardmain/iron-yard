import 'package:flutter_test/flutter_test.dart';
import 'package:iron_yard/core/constants/app_constants.dart';
import 'package:iron_yard/data/local/database.dart';
import 'package:iron_yard/features/dashboard/data/csv_exporter.dart';
import 'package:iron_yard/features/dashboard/data/dashboard_repository.dart';

void main() {
  late AppDatabase db;
  late DashboardRepository dashboard;
  late CsvExporter exporter;
  late String planId;

  setUp(() async {
    db = AppDatabase.memory();
    dashboard = DashboardRepository(db);
    exporter = CsvExporter(db);
    planId = await db.membershipDao.createPlan(
      name: 'Monthly',
      durationDays: 30,
      priceMinor: 150000,
    );
  });

  tearDown(() async => db.close());

  /// Adds a member whose membership ends [endsInDays] from today.
  Future<String> memberExpiringIn(int endsInDays, {String? name}) async {
    final id = await db.profileDao.createMember(
      fullName: name ?? 'Ends in $endsInDays',
    );
    final today = DateTime.now();
    await db.membershipDao.assignPlan(
      memberId: id,
      planId: planId,
      startDate: DateTime(
        today.year,
        today.month,
        today.day + endsInDays - 30,
      ),
    );
    return id;
  }

  group('summary', () {
    test('is all zeros on an empty gym', () async {
      final summary = await dashboard.summary();

      expect(summary.todayAttendance, 0);
      expect(summary.activeMembers, 0);
      expect(summary.monthRevenueMinor, 0);
      expect(summary.needsAttention, 0);
    });

    test('counts today\'s verified check-ins', () async {
      final a = await db.profileDao.createMember(fullName: 'A');
      final b = await db.profileDao.createMember(fullName: 'B');

      await db.attendanceDao.recordCheckIn(
        memberId: a,
        source: AttendanceSource.qrScan,
      );
      await db.attendanceDao.recordCheckIn(
        memberId: b,
        source: AttendanceSource.qrScan,
      );

      expect((await dashboard.summary()).todayAttendance, 2);
    });

    test('keeps self-reported check-ins out of the headline figure', () async {
      // Whether they count officially is still an owner decision
      // (brain.md §6.7), so folding them in would decide it silently.
      final a = await db.profileDao.createMember(fullName: 'A');
      final b = await db.profileDao.createMember(fullName: 'B');

      await db.attendanceDao.recordCheckIn(
        memberId: a,
        source: AttendanceSource.qrScan,
      );
      await db.attendanceDao.recordSelfReported(
        memberId: b,
        startedAt: DateTime.now(),
      );

      final summary = await dashboard.summary();
      expect(summary.todayAttendance, 1);
      expect(summary.unverifiedToday, 1);
    });

    test('yesterday\'s check-ins do not count toward today', () async {
      final a = await db.profileDao.createMember(fullName: 'A');
      await db.attendanceDao.recordCheckIn(
        memberId: a,
        source: AttendanceSource.qrScan,
        at: DateTime.now().subtract(const Duration(days: 1)),
      );

      expect((await dashboard.summary()).todayAttendance, 0);
    });

    test('splits members into active, expiring and expired', () async {
      await memberExpiringIn(60);
      await memberExpiringIn(3);
      await memberExpiringIn(-10);

      final summary = await dashboard.summary();

      expect(summary.activeMembers, 1);
      expect(summary.expiringSoon, 1);
      expect(summary.expired, 1);
      expect(summary.needsAttention, 2);
    });

    test('a member with no plan is not counted as active', () async {
      await db.profileDao.createMember(fullName: 'No Plan');
      expect((await dashboard.summary()).activeMembers, 0);
    });

    test('a deactivated member is excluded entirely', () async {
      final id = await memberExpiringIn(60);
      await db.profileDao.setActive(id, isActive: false);

      final summary = await dashboard.summary();
      expect(summary.activeMembers, 0);
      expect(summary.needsAttention, 0);
    });

    test('a renewed member counts once, by their current membership',
        () async {
      // Their old expired membership must not also appear as "expired".
      final id = await memberExpiringIn(-40);
      await db.membershipDao.renew(memberId: id, planId: planId);

      final summary = await dashboard.summary();
      expect(summary.activeMembers, 1);
      expect(summary.expired, 0);
    });

    test('counts this month\'s paid revenue only', () async {
      final id = await db.profileDao.createMember(fullName: 'Payer');
      final now = DateTime.now();

      await db.paymentDao.record(
        memberId: id,
        amountMinor: 150000,
        method: PaymentMethod.cash,
        paidAt: DateTime(now.year, now.month, 2),
      );
      await db.paymentDao.record(
        memberId: id,
        amountMinor: 999999,
        method: PaymentMethod.cash,
        paidAt: DateTime(now.year, now.month, 3),
        pending: true,
      );
      await db.paymentDao.record(
        memberId: id,
        amountMinor: 500000,
        method: PaymentMethod.cash,
        paidAt: DateTime(now.year, now.month - 2, 10),
      );

      final summary = await dashboard.summary();
      expect(summary.monthRevenueMinor, 150000);
      expect(summary.pendingPayments, 1);
    });

    test('counts only upcoming, non-cancelled classes', () async {
      final future = DateTime.now().add(const Duration(days: 2));

      await db.classDao.createClass(
        name: 'Upcoming',
        startsAt: future,
        endsAt: future.add(const Duration(hours: 1)),
        capacity: 10,
      );
      await db.classDao.createClass(
        name: 'Past',
        startsAt: DateTime.now().subtract(const Duration(days: 1)),
        endsAt: DateTime.now(),
        capacity: 10,
      );
      final cancelled = await db.classDao.createClass(
        name: 'Cancelled',
        startsAt: future,
        endsAt: future.add(const Duration(hours: 1)),
        capacity: 10,
      );
      await db.classDao.cancelClass(cancelled);

      expect((await dashboard.summary()).upcomingClasses, 1);
    });
  });

  group('needsAttention', () {
    test('lists expiring and expired members, soonest first', () async {
      await memberExpiringIn(5, name: 'Later');
      await memberExpiringIn(1, name: 'Sooner');
      await memberExpiringIn(-3, name: 'Already Expired');

      final list = await dashboard.needsAttention();

      expect(list.map((e) => e.member.fullName), [
        'Already Expired',
        'Sooner',
        'Later',
      ]);
    });

    test('excludes members whose membership is comfortably current', () async {
      await memberExpiringIn(60);
      expect(await dashboard.needsAttention(), isEmpty);
    });

    test('a renewed member drops off the list', () async {
      final id = await memberExpiringIn(2);
      expect(await dashboard.needsAttention(), hasLength(1));

      await db.membershipDao.renew(memberId: id, planId: planId);

      expect(await dashboard.needsAttention(), isEmpty);
    });
  });

  group('attendanceTrend', () {
    test('returns one point per day, oldest first', () async {
      final points = await dashboard.attendanceTrend(days: 7);

      expect(points, hasLength(7));
      for (var i = 1; i < points.length; i++) {
        expect(points[i].day.isAfter(points[i - 1].day), isTrue);
      }
    });

    test('days with no visits are zero, not missing', () async {
      // A gap in the list would misalign every bar in the chart.
      final points = await dashboard.attendanceTrend(days: 5);
      expect(points.every((p) => p.verified == 0), isTrue);
      expect(points, hasLength(5));
    });

    test('separates verified from self-reported', () async {
      final a = await db.profileDao.createMember(fullName: 'A');
      final b = await db.profileDao.createMember(fullName: 'B');

      await db.attendanceDao.recordCheckIn(
        memberId: a,
        source: AttendanceSource.qrScan,
      );
      await db.attendanceDao.recordSelfReported(
        memberId: b,
        startedAt: DateTime.now(),
      );

      final today = (await dashboard.attendanceTrend(days: 3)).last;
      expect(today.verified, 1);
      expect(today.selfReported, 1);
    });
  });

  group('revenueTrend', () {
    test('returns one point per month, oldest first', () async {
      final months = await dashboard.revenueTrend(months: 4);

      expect(months, hasLength(4));
      for (var i = 1; i < months.length; i++) {
        expect(months[i].month.isAfter(months[i - 1].month), isTrue);
      }
    });

    test('attributes a payment to its own month', () async {
      final id = await db.profileDao.createMember(fullName: 'Payer');
      final now = DateTime.now();

      await db.paymentDao.record(
        memberId: id,
        amountMinor: 250000,
        method: PaymentMethod.cash,
        paidAt: DateTime(now.year, now.month, 5),
      );

      final months = await dashboard.revenueTrend(months: 3);
      expect(months.last.revenueMinor, 250000);
      expect(months.first.revenueMinor, 0);
    });
  });

  group('CSV export', () {
    test('members export has a header and one row per member', () async {
      await db.profileDao.createMember(
        fullName: 'Priya Sharma',
        phone: '9876543210',
      );
      await db.profileDao.createMember(fullName: 'Rahul Verma');

      final csv = await exporter.build(ExportKind.members);
      final lines = csv.trim().split('\r\n');

      expect(lines.first, contains('Name'));
      expect(lines, hasLength(3));
      expect(csv, contains('Priya Sharma'));
    });

    test('includes deactivated members, flagged', () async {
      // The owner exports for their own records; silently dropping former
      // members would make the file wrong.
      final id = await db.profileDao.createMember(fullName: 'Former');
      await db.profileDao.setActive(id, isActive: false);

      final csv = await exporter.build(ExportKind.members);
      expect(csv, contains('Former'));
      expect(csv, contains('No'));
    });

    test('payments export writes decimal rupees, not paise', () async {
      // 150000 paise is ₹1500.00 — writing the integer would be off by 100x.
      final id = await db.profileDao.createMember(fullName: 'Payer');
      await db.paymentDao.record(
        memberId: id,
        amountMinor: 150000,
        method: PaymentMethod.upi,
      );

      final csv = await exporter.build(ExportKind.payments);
      expect(csv, contains('1500.00'));
      expect(csv, isNot(contains('150000')));
    });

    test('payments export names the method in words', () async {
      final id = await db.profileDao.createMember(fullName: 'Payer');
      await db.paymentDao.record(
        memberId: id,
        amountMinor: 1000,
        method: PaymentMethod.bankTransfer,
      );

      final csv = await exporter.build(ExportKind.payments);
      expect(csv, contains('Bank Transfer'));
      expect(csv, isNot(contains('bank_transfer')));
    });

    test('attendance export spells out the source', () async {
      final id = await db.profileDao.createMember(fullName: 'Visitor');
      await db.attendanceDao.recordCheckIn(
        memberId: id,
        source: AttendanceSource.qrScan,
      );

      final csv = await exporter.build(ExportKind.attendance);
      expect(csv, contains('Staff scan'));
      expect(csv, isNot(contains('qr_scan')));
    });

    test('quotes fields containing commas', () async {
      // An unquoted comma would shift every later column in the row.
      await db.profileDao.createMember(fullName: 'Sharma, Priya');

      final csv = await exporter.build(ExportKind.members);
      expect(csv, contains('"Sharma, Priya"'));
    });

    test('starts with a UTF-8 BOM so Excel reads names correctly', () async {
      await db.profileDao.createMember(fullName: 'प्रिया');

      final csv = await exporter.build(ExportKind.members);
      expect(csv.codeUnitAt(0), 0xFEFF);
      expect(csv, contains('प्रिया'));
    });

    test('an empty gym still exports headers', () async {
      final csv = await exporter.build(ExportKind.members);
      expect(csv, contains('Name'));
      expect(csv.trim().split('\r\n'), hasLength(1));
    });

    test('file names are dated', () {
      final name = exporter.fileNameFor(
        ExportKind.payments,
        asOf: DateTime(2026, 9, 21),
      );
      expect(name, 'payments_2026-09-21.csv');
    });
  });
}
