import 'package:flutter_test/flutter_test.dart';
import 'package:iron_yard/core/constants/app_constants.dart';
import 'package:iron_yard/data/local/database.dart';
import 'package:iron_yard/features/attendance/data/attendance_repository.dart';
import 'package:iron_yard/features/attendance/data/qr_payload.dart';
import 'package:iron_yard/features/attendance/data/scan_result.dart';

void main() {
  group('QrPayload', () {
    test('round-trips a member', () {
      const payload = QrPayload(
        memberId: 'abc-123',
        fullName: 'Priya Sharma',
      );

      final parsed = QrPayload.tryParse(payload.encode());

      expect(parsed, isNotNull);
      expect(parsed!.memberId, 'abc-123');
      expect(parsed.fullName, 'Priya Sharma');
    });

    test('survives names with quotes and unicode', () {
      // JSON encoding must not be defeated by the name itself.
      const payload = QrPayload(
        memberId: 'id-1',
        fullName: r'O"Brien \ प्रिया',
      );

      final parsed = QrPayload.tryParse(payload.encode());
      expect(parsed!.fullName, r'O"Brien \ प्रिया');
    });

    test('carries a version tag', () {
      const payload = QrPayload(memberId: 'x', fullName: 'Y');
      expect(payload.encode(), contains('"v":1'));
    });

    group('rejects codes that are not our cards', () {
      // A scanner picks up every barcode in view, so unrecognised input must
      // return null rather than throwing or producing a bogus member.
      final cases = <String, String?>{
        'null': null,
        'empty': '',
        'plain text': 'hello world',
        'a URL': 'https://example.com',
        'a bare uuid': '550e8400-e29b-41d4-a716-446655440000',
        'malformed JSON': '{"v":1,"id":',
        'a JSON array': '[1,2,3]',
        'a JSON string': '"just a string"',
        'a JSON number': '42',
        'an object with no id': '{"v":1,"n":"Someone"}',
        'an empty id': '{"v":1,"id":"","n":"Someone"}',
        'a non-string id': '{"v":1,"id":123,"n":"Someone"}',
        'no version': '{"id":"abc","n":"Someone"}',
        'a non-integer version': '{"v":"1","id":"abc"}',
        'a future version': '{"v":99,"id":"abc","n":"Someone"}',
      };

      cases.forEach((label, raw) {
        test(label, () => expect(QrPayload.tryParse(raw), isNull));
      });
    });

    test('tolerates a missing name', () {
      // The id is what matters; the name is only for the offline display.
      final parsed = QrPayload.tryParse('{"v":1,"id":"abc"}');
      expect(parsed, isNotNull);
      expect(parsed!.fullName, '');
    });
  });

  group('handleScan', () {
    late AppDatabase db;
    late AttendanceRepository repository;
    late String memberId;
    late String planId;

    setUp(() async {
      db = AppDatabase.memory();
      repository = AttendanceRepository(db);
      memberId = await db.profileDao.createMember(fullName: 'Scan Member');
      planId = await db.membershipDao.createPlan(
        name: 'Monthly',
        durationDays: 30,
        priceMinor: 150000,
      );
    });
    tearDown(() async => db.close());

    Future<String> cardFor(String id) async {
      final payload = await repository.cardFor(id);
      return payload!.encode();
    }

    Future<void> giveActivePlan() => db.membershipDao.assignPlan(
      memberId: memberId,
      planId: planId,
    );

    test('records a valid scan', () async {
      await giveActivePlan();

      final outcome = await repository.handleScan(await cardFor(memberId));

      expect(outcome, isA<ScanAccepted>());
      expect(outcome.memberName, 'Scan Member');
      expect(outcome.recorded, isTrue);
      expect(await db.attendanceDao.hasCheckedIn(memberId), isTrue);
    });

    test('tags the scan as qr_scan, not self-reported', () async {
      await giveActivePlan();
      await repository.handleScan(await cardFor(memberId));

      final records = await db.attendanceDao.historyFor(memberId);
      expect(records.single.source, AttendanceSource.qrScan.wireValue);
    });

    test('attributes the scan to the staff member', () async {
      await giveActivePlan();
      final staffId = await db.profileDao.createMember(
        fullName: 'Front Desk',
        role: UserRole.admin,
      );

      await repository.handleScan(
        await cardFor(memberId),
        recordedBy: staffId,
      );

      final records = await db.attendanceDao.historyFor(memberId);
      expect(records.single.recordedBy, staffId);
    });

    test('a second scan the same day reports already checked in', () async {
      await giveActivePlan();
      final card = await cardFor(memberId);

      await repository.handleScan(card);
      final second = await repository.handleScan(card);

      expect(second, isA<ScanAlreadyCheckedIn>());
      expect(await db.attendanceDao.countForDay(), 1);
    });

    test('an expired membership still records the visit', () async {
      // The person physically came in; discarding that would leave no trace.
      await db.membershipDao.assignPlan(
        memberId: memberId,
        planId: planId,
        startDate: DateTime.now().subtract(const Duration(days: 60)),
      );

      final outcome = await repository.handleScan(await cardFor(memberId));

      expect(outcome, isA<ScanExpired>());
      expect(outcome.recorded, isTrue);
      expect(await db.attendanceDao.hasCheckedIn(memberId), isTrue);
    });

    test('a member with no plan is recorded but flagged', () async {
      final outcome = await repository.handleScan(await cardFor(memberId));

      expect(outcome, isA<ScanExpired>());
      expect((outcome as ScanExpired).expiredOn, isNull);
      expect(outcome.recorded, isTrue);
    });

    test('a deactivated member is refused and not recorded', () async {
      await giveActivePlan();
      final card = await cardFor(memberId);
      await db.profileDao.setActive(memberId, isActive: false);

      final outcome = await repository.handleScan(card);

      expect(outcome, isA<ScanDeactivated>());
      expect(outcome.recorded, isFalse);
      expect(
        await db.attendanceDao.hasCheckedIn(memberId),
        isFalse,
        reason: 'a deactivated member must not be checked in',
      );
    });

    test('an unsynced member is reported as unknown, not as a bad card',
        () async {
      // Blaming the card would send staff chasing a non-existent problem.
      const card = '{"v":1,"id":"not-on-this-device","n":"Ghost Member"}';

      final outcome = await repository.handleScan(card);

      expect(outcome, isA<ScanUnknownMember>());
      expect((outcome as ScanUnknownMember).scannedName, 'Ghost Member');
    });

    test('a foreign barcode is reported as not a card', () async {
      final outcome = await repository.handleScan('https://example.com');
      expect(outcome, isA<ScanNotACard>());
      expect(outcome.recorded, isFalse);
    });

    test('a scan upgrades a self-report from the same day', () async {
      // QR is the trusted record for admin reporting (brain.md §6.7).
      await giveActivePlan();
      await db.attendanceDao.recordSelfReported(
        memberId: memberId,
        startedAt: DateTime.now(),
      );

      final outcome = await repository.handleScan(await cardFor(memberId));

      expect(outcome, isA<ScanAccepted>());
      expect((outcome as ScanAccepted).upgraded, isTrue);

      final records = await db.attendanceDao.historyFor(memberId);
      expect(records, hasLength(1), reason: 'upgrade, not duplicate');
      expect(records.single.source, AttendanceSource.qrScan.wireValue);
    });

    test('an expiring membership is accepted with a warning', () async {
      await db.membershipDao.assignPlan(
        memberId: memberId,
        planId: planId,
        startDate: DateTime.now().subtract(const Duration(days: 27)),
      );

      final outcome = await repository.handleScan(await cardFor(memberId));

      expect(outcome, isA<ScanAccepted>());
      expect((outcome as ScanAccepted).warnsAboutExpiry, isTrue);
      expect(outcome.expiresOn, isNotNull);
    });

    test('scans on different days both record', () async {
      await giveActivePlan();
      final card = await cardFor(memberId);

      await repository.handleScan(
        card,
        at: DateTime.now().subtract(const Duration(days: 1)),
      );
      final today = await repository.handleScan(card);

      expect(today, isA<ScanAccepted>());
      expect(await db.attendanceDao.historyFor(memberId), hasLength(2));
    });

    test('todayCount counts verified scans only', () async {
      await giveActivePlan();
      await repository.handleScan(await cardFor(memberId));

      final other = await db.profileDao.createMember(fullName: 'Self Reporter');
      await db.attendanceDao.recordSelfReported(
        memberId: other,
        startedAt: DateTime.now(),
      );

      expect(await repository.todayCount(), 1);
      expect(await repository.todayCount(verifiedOnly: false), 2);
    });

    test('cardFor returns null for a deleted member', () async {
      await db.profileDao.softDelete(memberId);
      expect(await repository.cardFor(memberId), isNull);
    });
  });
}
