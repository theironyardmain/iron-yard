import 'package:sqlite3/sqlite3.dart' show SqliteException;
import 'package:flutter_test/flutter_test.dart';
import 'package:iron_yard/core/constants/app_constants.dart';
import 'package:iron_yard/data/local/daos/attendance_dao.dart';
import 'package:iron_yard/data/local/daos/membership_dao.dart';
import 'package:iron_yard/data/local/daos/synced_dao.dart';
import 'package:iron_yard/data/local/database.dart';

void main() {
  late AppDatabase db;
  late String memberId;

  setUp(() async {
    db = AppDatabase.memory();
    memberId = await db.profileDao.createMember(
      fullName: 'Test Member',
      phone: '9990001111',
    );
  });

  tearDown(() async => db.close());

  group('schema', () {
    test('creates a profile with sync columns populated', () async {
      final profile = await db.profileDao.byId(memberId);

      expect(profile, isNotNull);
      expect(profile!.fullName, 'Test Member');
      expect(profile.isDeleted, isFalse);
      // Locally created rows must be dirty so the first sync uploads them.
      expect(profile.isDirty, isTrue);
      expect(profile.role, UserRole.member.wireValue);
    });

    test('enforces foreign keys', () async {
      // beforeOpen sets PRAGMA foreign_keys = ON; without it the references on
      // the tables would be decorative.
      await expectLater(
        db.attendanceDao.recordCheckIn(
          memberId: 'does-not-exist',
          source: AttendanceSource.qrScan,
        ),
        throwsA(isA<SqliteException>()),
      );
    });

    test('seeds one sync-state row per synced table', () async {
      final rows = await db.syncDao.allSyncState();
      expect(rows, hasLength(AppDatabase.syncedTableNames.length));
      expect(rows.every((r) => r.lastSyncedAt == null), isTrue);
    });
  });

  group('attendance duplicate guard (brain.md §6.4)', () {
    test('records a first check-in', () async {
      final result = await db.attendanceDao.recordCheckIn(
        memberId: memberId,
        source: AttendanceSource.qrScan,
      );
      expect(result, CheckInResult.recorded);
      expect(await db.attendanceDao.hasCheckedIn(memberId), isTrue);
    });

    test('rejects a second scan on the same day', () async {
      await db.attendanceDao.recordCheckIn(
        memberId: memberId,
        source: AttendanceSource.qrScan,
      );
      final second = await db.attendanceDao.recordCheckIn(
        memberId: memberId,
        source: AttendanceSource.qrScan,
      );

      expect(second, CheckInResult.duplicate);
      expect(await db.attendanceDao.countForDay(), 1);
    });

    test('allows check-ins on different days', () async {
      final today = DateTime.now();
      final yesterday = today.subtract(const Duration(days: 1));

      await db.attendanceDao.recordCheckIn(
        memberId: memberId,
        source: AttendanceSource.qrScan,
        at: yesterday,
      );
      final result = await db.attendanceDao.recordCheckIn(
        memberId: memberId,
        source: AttendanceSource.qrScan,
        at: today,
      );

      expect(result, CheckInResult.recorded);
      expect(await db.attendanceDao.historyFor(memberId), hasLength(2));
    });

    test('treats late-evening and early-morning as different days', () async {
      // The guard keys on a normalised date, not a timestamp, so two scans
      // either side of midnight must not collapse into one day.
      final lateNight = DateTime(2026, 3, 10, 23, 55);
      final earlyNext = DateTime(2026, 3, 11, 0, 5);

      expect(
        await db.attendanceDao.recordCheckIn(
          memberId: memberId,
          source: AttendanceSource.qrScan,
          at: lateNight,
        ),
        CheckInResult.recorded,
      );
      expect(
        await db.attendanceDao.recordCheckIn(
          memberId: memberId,
          source: AttendanceSource.qrScan,
          at: earlyNext,
        ),
        CheckInResult.recorded,
      );
    });

    test('two scans hours apart on one day still collapse to one', () async {
      final morning = DateTime(2026, 3, 10, 6, 0);
      final evening = DateTime(2026, 3, 10, 19, 30);

      await db.attendanceDao.recordCheckIn(
        memberId: memberId,
        source: AttendanceSource.qrScan,
        at: morning,
      );
      final second = await db.attendanceDao.recordCheckIn(
        memberId: memberId,
        source: AttendanceSource.qrScan,
        at: evening,
      );

      expect(second, CheckInResult.duplicate);
    });
  });

  group('self-reported check-in (brain.md §6.7)', () {
    test('records with a time range', () async {
      final start = DateTime(2026, 3, 10, 18, 0);
      final end = DateTime(2026, 3, 10, 19, 30);

      final result = await db.attendanceDao.recordSelfReported(
        memberId: memberId,
        startedAt: start,
        endedAt: end,
      );

      expect(result, CheckInResult.recorded);

      final rows = await db.attendanceDao.historyFor(memberId);
      expect(rows.single.source, AttendanceSource.selfReported.wireValue);
      expect(rows.single.checkOutAt, end);
    });

    test('a QR scan upgrades an existing self-report for the same day', () async {
      // QR is the trusted source for admin reporting, so it must win rather
      // than being rejected as a duplicate.
      final day = DateTime(2026, 3, 10, 7, 0);

      await db.attendanceDao.recordSelfReported(
        memberId: memberId,
        startedAt: day,
      );

      final result = await db.attendanceDao.recordCheckIn(
        memberId: memberId,
        source: AttendanceSource.qrScan,
        at: DateTime(2026, 3, 10, 9, 0),
      );

      expect(result, CheckInResult.upgradedFromSelfReport);

      final rows = await db.attendanceDao.historyFor(memberId);
      expect(rows, hasLength(1), reason: 'must upgrade, not duplicate');
      expect(rows.single.source, AttendanceSource.qrScan.wireValue);
    });

    test('a self-report does not downgrade an existing QR scan', () async {
      final day = DateTime(2026, 3, 10, 9, 0);

      await db.attendanceDao.recordCheckIn(
        memberId: memberId,
        source: AttendanceSource.qrScan,
        at: day,
      );
      final result = await db.attendanceDao.recordSelfReported(
        memberId: memberId,
        startedAt: DateTime(2026, 3, 10, 18, 0),
      );

      expect(result, CheckInResult.duplicate);

      final rows = await db.attendanceDao.historyFor(memberId);
      expect(rows.single.source, AttendanceSource.qrScan.wireValue);
    });

    test('countForDay excludes self-reports by default', () async {
      // Pending owner decision (brain.md §6.7) — the safe default is to keep
      // unverified entries out of admin figures.
      final day = DateTime(2026, 3, 10, 18, 0);
      await db.attendanceDao.recordSelfReported(
        memberId: memberId,
        startedAt: day,
      );

      expect(await db.attendanceDao.countForDay(day: day), 0);
      expect(
        await db.attendanceDao.countForDay(day: day, verifiedOnly: false),
        1,
      );
    });
  });

  group('memberships', () {
    late String planId;

    setUp(() async {
      planId = await db.membershipDao.createPlan(
        name: 'Monthly',
        durationDays: 30,
        priceMinor: 150000,
      );
    });

    test('assigning a plan derives the expiry date from its duration', () async {
      final start = DateTime(2026, 3, 1);
      await db.membershipDao.assignPlan(
        memberId: memberId,
        planId: planId,
        startDate: start,
      );

      final current = await db.membershipDao.currentFor(memberId);
      expect(current, isNotNull);
      expect(current!.endDate, DateTime(2026, 3, 31));
    });

    test('currentFor returns the membership with the latest end date', () async {
      await db.membershipDao.assignPlan(
        memberId: memberId,
        planId: planId,
        startDate: DateTime(2026, 1, 1),
      );
      await db.membershipDao.assignPlan(
        memberId: memberId,
        planId: planId,
        startDate: DateTime(2026, 6, 1),
      );

      final current = await db.membershipDao.currentFor(memberId);
      expect(current!.startDate, DateTime(2026, 6, 1));
    });

    test('expiringWithin finds memberships inside the window only', () async {
      final today = DayKey.of();

      await db.membershipDao.assignPlan(
        memberId: memberId,
        planId: planId,
        // Ends in 3 days — inside a 7-day window.
        startDate: today.subtract(const Duration(days: 27)),
      );

      final soon = await db.membershipDao.expiringWithin();
      expect(soon, hasLength(1));

      final other = await db.profileDao.createMember(fullName: 'Far Future');
      await db.membershipDao.assignPlan(
        memberId: other,
        planId: planId,
        startDate: today,
      );

      // Still 1 — the second membership ends 30 days out.
      expect(await db.membershipDao.expiringWithin(), hasLength(1));
    });

    group('statusOf', () {
      Membership build({required DateTime end, String status = 'active'}) {
        return Membership(
          id: 'm1',
          memberId: memberId,
          planId: 'p1',
          startDate: end.subtract(const Duration(days: 30)),
          endDate: end,
          status: status,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          isDeleted: false,
          isDirty: false,
        );
      }

      test('none when there is no membership', () {
        expect(MembershipDao.statusOf(null), MembershipStatus.none);
      });

      test('expired when the end date has passed', () {
        final m = build(end: DateTime.now().subtract(const Duration(days: 1)));
        expect(MembershipDao.statusOf(m), MembershipStatus.expired);
      });

      test('expiringSoon inside the warning window', () {
        final m = build(end: DateTime.now().add(const Duration(days: 3)));
        expect(MembershipDao.statusOf(m), MembershipStatus.expiringSoon);
      });

      test('active well before expiry', () {
        final m = build(end: DateTime.now().add(const Duration(days: 60)));
        expect(MembershipDao.statusOf(m), MembershipStatus.active);
      });

      test('cancelled overrides the dates', () {
        final m = build(
          end: DateTime.now().add(const Duration(days: 60)),
          status: 'cancelled',
        );
        expect(MembershipDao.statusOf(m), MembershipStatus.cancelled);
      });

      test('a membership ending today still counts as expiring, not expired', () {
        final m = build(end: DateTime.now());
        expect(MembershipDao.statusOf(m), MembershipStatus.expiringSoon);
      });
    });
  });

  group('payments', () {
    test('revenue sums paid rows only', () async {
      await db.paymentDao.record(
        memberId: memberId,
        amountMinor: 150000,
        method: PaymentMethod.cash,
        paidAt: DateTime(2026, 3, 5),
      );
      await db.paymentDao.record(
        memberId: memberId,
        amountMinor: 50000,
        method: PaymentMethod.upi,
        paidAt: DateTime(2026, 3, 6),
        pending: true,
      );

      final revenue = await db.paymentDao.revenueInRange(
        from: DateTime(2026, 3, 1),
        to: DateTime(2026, 3, 31),
      );

      expect(revenue, 150000, reason: 'pending payments are not revenue');
    });

    test('revenue excludes payments outside the range', () async {
      await db.paymentDao.record(
        memberId: memberId,
        amountMinor: 99999,
        method: PaymentMethod.cash,
        paidAt: DateTime(2026, 1, 15),
      );

      expect(
        await db.paymentDao.revenueInRange(
          from: DateTime(2026, 3, 1),
          to: DateTime(2026, 3, 31),
        ),
        0,
      );
    });

    test('tracks receipts captured offline', () async {
      final id = await db.paymentDao.record(
        memberId: memberId,
        amountMinor: 150000,
        method: PaymentMethod.cash,
        receiptLocalPath: '/tmp/receipt.jpg',
      );

      expect(await db.paymentDao.awaitingReceiptUpload(), hasLength(1));

      await db.paymentDao.attachReceiptUrl(id, 'https://storage/receipt.jpg');

      expect(await db.paymentDao.awaitingReceiptUpload(), isEmpty);
    });
  });

  group('soft delete and dirty tracking', () {
    test('softDelete hides the row but keeps it for sync', () async {
      await db.attendanceDao.recordCheckIn(
        memberId: memberId,
        source: AttendanceSource.qrScan,
      );
      final row = (await db.attendanceDao.historyFor(memberId)).single;

      await db.attendanceDao.softDelete(row.id);

      expect(await db.attendanceDao.historyFor(memberId), isEmpty);

      // Still present in the table, flagged for upload.
      final all = await db.select(db.attendance).get();
      expect(all.single.isDeleted, isTrue);
      expect(all.single.isDirty, isTrue);
    });

    test('clearDirty releases rows the server accepted', () async {
      await db.attendanceDao.recordCheckIn(
        memberId: memberId,
        source: AttendanceSource.qrScan,
      );
      final pending = await db.attendanceDao.pendingUpload();
      expect(pending, hasLength(1));

      await db.attendanceDao.clearDirty(pending.map((r) => r.id));

      expect(await db.attendanceDao.pendingUpload(), isEmpty);
    });

    test('a soft-deleted member frees the day for a new check-in', () async {
      // The unique index is partial (WHERE is_deleted = 0), so a deleted row
      // must not block a fresh record for the same day.
      await db.attendanceDao.recordCheckIn(
        memberId: memberId,
        source: AttendanceSource.qrScan,
      );
      final row = (await db.attendanceDao.historyFor(memberId)).single;
      await db.attendanceDao.softDelete(row.id);

      final result = await db.attendanceDao.recordCheckIn(
        memberId: memberId,
        source: AttendanceSource.qrScan,
      );
      expect(result, CheckInResult.recorded);
    });
  });

  group('sync queue', () {
    test('drains in FIFO order and clears accepted entries', () async {
      await db.syncDao.enqueue(
        entityTable: 'attendance',
        entityId: 'a1',
        operation: 'insert',
      );
      await db.syncDao.enqueue(
        entityTable: 'payments',
        entityId: 'p1',
        operation: 'insert',
      );

      final batch = await db.syncDao.nextBatch();
      expect(batch, hasLength(2));
      expect(batch.first.entityId, 'a1');

      await db.syncDao.clearAccepted([batch.first.id]);
      expect(await db.syncDao.pendingCount(), 1);
    });

    test('rejected entries leave the batch but are retained', () async {
      await db.syncDao.enqueue(
        entityTable: 'class_bookings',
        entityId: 'b1',
        operation: 'insert',
      );
      final entry = (await db.syncDao.nextBatch()).single;

      await db.syncDao.markRejected(entry.id, 'Class is full');

      expect(await db.syncDao.nextBatch(), isEmpty);
      expect(await db.syncDao.pendingCount(), 0);

      final rejected = await db.syncDao.rejectedEntries();
      expect(rejected.single.lastError, 'Class is full');
    });

    test('tracks the per-table high-water mark', () async {
      expect(await db.syncDao.lastSyncedAt('attendance'), isNull);

      final at = DateTime(2026, 3, 10, 12, 0);
      await db.syncDao.setLastSyncedAt('attendance', at);

      expect(await db.syncDao.lastSyncedAt('attendance'), at);
      // Independent per table, so one failure does not stall the others.
      expect(await db.syncDao.lastSyncedAt('payments'), isNull);
    });

    test('oldestSyncedAt is null until every table has synced', () async {
      await db.syncDao.setLastSyncedAt('attendance', DateTime(2026, 3, 10));
      expect(await db.syncDao.oldestSyncedAt(), isNull);

      for (final table in AppDatabase.syncedTableNames) {
        await db.syncDao.setLastSyncedAt(table, DateTime(2026, 3, 11));
      }
      await db.syncDao.setLastSyncedAt('attendance', DateTime(2026, 3, 9));

      expect(await db.syncDao.oldestSyncedAt(), DateTime(2026, 3, 9));
    });
  });

  group('member search', () {
    test('matches on name, phone, and email', () async {
      await db.profileDao.createMember(
        fullName: 'Priya Sharma',
        phone: '9876543210',
        email: 'priya@example.com',
      );

      expect(await db.profileDao.searchMembers('Priya'), hasLength(1));
      expect(await db.profileDao.searchMembers('98765'), hasLength(1));
      expect(await db.profileDao.searchMembers('example.com'), hasLength(1));
      expect(await db.profileDao.searchMembers('nobody'), isEmpty);
    });

    test('deactivated members are hidden but not deleted', () async {
      await db.profileDao.setActive(memberId, isActive: false);

      expect(await db.profileDao.members(), isEmpty);
      expect(await db.profileDao.members(activeOnly: false), hasLength(1));
    });
  });

  group('emergency contacts (device-only, brain.md §6.2)', () {
    test('stores and replaces a contact', () async {
      await db.profileDao.setEmergencyContact(
        profileId: memberId,
        name: 'Anil',
        phone: '9000000000',
        relationship: 'Brother',
      );

      var contact = await db.profileDao.emergencyContactFor(memberId);
      expect(contact!.name, 'Anil');

      await db.profileDao.setEmergencyContact(
        profileId: memberId,
        name: 'Meera',
        phone: '9111111111',
      );

      contact = await db.profileDao.emergencyContactFor(memberId);
      expect(contact!.name, 'Meera', reason: 'one contact per profile');
    });

    test('is not among the tables that sync', () {
      expect(
        AppDatabase.syncedTableNames,
        isNot(contains('emergency_contacts')),
      );
    });
  });

  group('Uuid', () {
    test('generates distinct v4 ids', () {
      final ids = List.generate(500, (_) => Uuid.v4());
      expect(ids.toSet(), hasLength(500));
    });

    test('has the v4 shape', () {
      final id = Uuid.v4();
      expect(
        RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ).hasMatch(id),
        isTrue,
        reason: 'got $id',
      );
    });
  });
}
