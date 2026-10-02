import 'package:flutter_test/flutter_test.dart';
import 'package:iron_yard/core/constants/app_constants.dart';
import 'package:iron_yard/data/local/daos/attendance_dao.dart';
import 'package:iron_yard/data/local/database.dart';
import 'package:iron_yard/features/checkin/data/checkin_repository.dart';
import 'package:iron_yard/features/checkin/data/checkin_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late AppDatabase db;
  late CheckInRepository repository;
  late String memberId;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    db = AppDatabase.memory();
    repository = CheckInRepository(
      db: db,
      settings: CheckInSettingsStore(prefs),
    );
    memberId = await db.profileDao.createMember(fullName: 'Member');
  });

  tearDown(() async => db.close());

  group('settings', () {
    test('the reminder is off until the member turns it on', () async {
      // The app must not start notifying someone who never asked.
      expect(repository.readSettings().enabled, isFalse);
    });

    test('defaults to a sensible evening time', () {
      final defaults = CheckInSettings.defaults;
      expect(defaults.hour, greaterThanOrEqualTo(17));
      expect(defaults.hour, lessThanOrEqualTo(21));
    });

    test('persists what the member chose', () async {
      await repository.updateSettings(
        const CheckInSettings(enabled: true, hour: 19, minute: 30),
      );

      final saved = repository.readSettings();
      expect(saved.enabled, isTrue);
      expect(saved.hour, 19);
      expect(saved.minute, 30);
    });

    test('formats the time with a leading zero', () {
      const settings = CheckInSettings(enabled: true, hour: 9, minute: 5);
      expect(settings.formattedTime, '09:05');
    });

    test('copyWith leaves untouched fields alone', () {
      const settings = CheckInSettings(enabled: true, hour: 19, minute: 30);
      final updated = settings.copyWith(enabled: false);

      expect(updated.enabled, isFalse);
      expect(updated.hour, 19);
      expect(updated.minute, 30);
    });

    test('applying a reminder never throws', () async {
      await expectLater(repository.applyReminder(), completes);
      await repository.updateSettings(
        const CheckInSettings(enabled: true, hour: 20, minute: 0),
      );
      await expectLater(repository.applyReminder(), completes);
    });
  });

  group('logging a session', () {
    test('records a self-reported entry', () async {
      // Pinned inside today: "an hour ago" lands on yesterday when the suite
      // runs just after midnight, which files the record under the wrong day.
      final now = DateTime.now();
      final result = await repository.logSession(
        memberId: memberId,
        startedAt: DateTime(now.year, now.month, now.day, 9),
        endedAt: DateTime(now.year, now.month, now.day, 10),
      );

      expect(result, CheckInResult.recorded);

      final record = await repository.todaysRecord(memberId);
      expect(record, isNotNull);
      expect(record!.source, AttendanceSource.selfReported.wireValue);
      expect(record.isDirty, isTrue, reason: 'rides the existing sync');
    });

    test('stores the time range', () async {
      final now = DateTime.now();
      final start = DateTime(now.year, now.month, now.day, 9);
      final end = DateTime(now.year, now.month, now.day, 10);

      await repository.logSession(
        memberId: memberId,
        startedAt: start,
        endedAt: end,
      );

      final record = await repository.todaysRecord(memberId);
      expect(record!.checkInAt, isNotNull);
      expect(record.checkOutAt, isNotNull);
    });

    test('an end time is optional', () async {
      await repository.logSession(
        memberId: memberId,
        startedAt: DateTime.now(),
      );

      final record = await repository.todaysRecord(memberId);
      expect(record!.checkOutAt, isNull);
    });

    test('a second log the same day is refused', () async {
      await repository.logSession(
        memberId: memberId,
        startedAt: DateTime.now(),
      );

      final second = await repository.logSession(
        memberId: memberId,
        startedAt: DateTime.now(),
      );

      expect(second, CheckInResult.duplicate);
    });

    test('a self-report never overwrites a staff scan', () async {
      // A member must not be able to downgrade a verified record.
      await db.attendanceDao.recordCheckIn(
        memberId: memberId,
        source: AttendanceSource.qrScan,
      );

      final result = await repository.logSession(
        memberId: memberId,
        startedAt: DateTime.now(),
      );

      expect(result, CheckInResult.duplicate);

      final record = await repository.todaysRecord(memberId);
      expect(record!.source, AttendanceSource.qrScan.wireValue);
    });

    test('a staff scan still upgrades an earlier self-report', () async {
      // The reverse direction: verified outranks self-reported.
      await repository.logSession(
        memberId: memberId,
        startedAt: DateTime.now(),
      );

      final result = await db.attendanceDao.recordCheckIn(
        memberId: memberId,
        source: AttendanceSource.qrScan,
      );

      expect(result, CheckInResult.upgradedFromSelfReport);

      final record = await repository.todaysRecord(memberId);
      expect(record!.source, AttendanceSource.qrScan.wireValue);
    });

    test('logging on different days both record', () async {
      await repository.logSession(
        memberId: memberId,
        startedAt: DateTime.now().subtract(const Duration(days: 1)),
      );

      final today = await repository.logSession(
        memberId: memberId,
        startedAt: DateTime.now(),
      );

      expect(today, CheckInResult.recorded);
      expect(await db.attendanceDao.historyFor(memberId), hasLength(2));
    });
  });

  group('todaysRecord', () {
    test('is null before anything is logged', () async {
      expect(await repository.todaysRecord(memberId), isNull);
    });

    test('ignores yesterday', () async {
      await repository.logSession(
        memberId: memberId,
        startedAt: DateTime.now().subtract(const Duration(days: 1)),
      );

      expect(await repository.todaysRecord(memberId), isNull);
    });

    test('hasLoggedToday matches either source', () async {
      expect(await repository.hasLoggedToday(memberId), isFalse);

      await db.attendanceDao.recordCheckIn(
        memberId: memberId,
        source: AttendanceSource.qrScan,
      );

      expect(await repository.hasLoggedToday(memberId), isTrue);
    });

    test('is scoped to the member', () async {
      final other = await db.profileDao.createMember(fullName: 'Other');
      await repository.logSession(
        memberId: memberId,
        startedAt: DateTime.now(),
      );

      expect(await repository.todaysRecord(other), isNull);
    });
  });

  group('owner decision: self-reports stay separate (2026-09-21)', () {
    test('a self-report does not raise the official attendance count',
        () async {
      await repository.logSession(
        memberId: memberId,
        startedAt: DateTime.now(),
      );

      // countForDay defaults to verified-only — the figure the admin
      // dashboard and reports use.
      expect(await db.attendanceDao.countForDay(), 0);
      expect(
        await db.attendanceDao.countForDay(verifiedOnly: false),
        1,
      );
    });

    test('a staff scan does raise it', () async {
      await db.attendanceDao.recordCheckIn(
        memberId: memberId,
        source: AttendanceSource.qrScan,
      );

      expect(await db.attendanceDao.countForDay(), 1);
    });

    test('self-reports remain visible in the member\'s own history', () async {
      // Separate from official stats, but not hidden from the member.
      await repository.logSession(
        memberId: memberId,
        startedAt: DateTime.now(),
      );

      final history = await db.attendanceDao.historyFor(memberId);
      expect(history, hasLength(1));
      expect(history.single.source, AttendanceSource.selfReported.wireValue);
    });
  });
}
