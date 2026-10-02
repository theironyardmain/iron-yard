import 'package:flutter_test/flutter_test.dart';
import 'package:iron_yard/core/constants/app_constants.dart';
import 'package:iron_yard/core/router/app_router.dart';
import 'package:iron_yard/data/local/database.dart';
import 'package:iron_yard/features/auth/data/auth_repository.dart';

void main() {
  group('Routes.homeFor', () {
    test('maps each role to its own shell', () {
      expect(Routes.homeFor(UserRole.admin), Routes.admin);
      expect(Routes.homeFor(UserRole.trainer), Routes.trainer);
      expect(Routes.homeFor(UserRole.member), Routes.member);
    });

    test('the three role homes are distinct', () {
      final homes = UserRole.values.map(Routes.homeFor).toSet();
      expect(homes, hasLength(3));
    });
  });

  group('AuthFailure', () {
    test('every failure has a user-facing message', () {
      for (final failure in AuthFailure.values) {
        expect(failure.message, isNotEmpty);
        // The message reaches the login screen, so it must not leak internals.
        expect(failure.message, isNot(contains('Exception')));
        expect(failure.message, isNot(contains('null')));
      }
    });

    test('sign-up failures are distinguishable from sign-in ones', () {
      // "Already registered" is a normal sign-up outcome, not a credential
      // error, and must not be reported as one.
      expect(
        AuthFailure.emailInUse.message.toLowerCase(),
        contains('already exists'),
      );
      expect(
        AuthFailure.emailInUse.message,
        isNot(AuthFailure.invalidCredentials.message),
      );
    });

    test('confirmation required reads as an instruction, not a failure', () {
      // The account was created; the user just has a step left.
      final message = AuthFailure.confirmationRequired.message.toLowerCase();
      expect(message, contains('confirm'));
      expect(message, isNot(contains('error')));
      expect(message, isNot(contains('failed')));
    });

    test('the weak-password message says what to do', () {
      expect(AuthFailure.weakPassword.message, contains('8'));
    });

    test('invalid credentials does not reveal which field was wrong', () {
      // Saying "no such email" would let someone enumerate members.
      final message = AuthFailure.invalidCredentials.message.toLowerCase();
      expect(message, contains('email or password'));
    });
  });

  group('SignInException', () {
    test('exposes the failure message', () {
      const e = SignInException(AuthFailure.network);
      expect(e.message, AuthFailure.network.message);
    });

    test('toString includes the detail for logs but message does not', () {
      const e = SignInException(AuthFailure.unknown, 'stack detail 42');
      expect(e.toString(), contains('stack detail 42'));
      expect(e.message, isNot(contains('stack detail 42')));
    });
  });

  group('local data purge on sign-out (tasks.md 3.7)', () {
    late AppDatabase db;

    setUp(() => db = AppDatabase.memory());
    tearDown(() async => db.close());

    test('wipeAllData clears every table', () async {
      final memberId = await db.profileDao.createMember(fullName: 'Member');
      await db.attendanceDao.recordCheckIn(
        memberId: memberId,
        source: AttendanceSource.qrScan,
      );
      await db.paymentDao.record(
        memberId: memberId,
        amountMinor: 1000,
        method: PaymentMethod.cash,
      );

      expect(await db.profileDao.members(), isNotEmpty);

      await db.wipeAllData();

      expect(await db.profileDao.members(), isEmpty);
      expect(await db.attendanceDao.historyFor(memberId), isEmpty);
      expect(await db.paymentDao.historyFor(memberId), isEmpty);
      expect(await db.select(db.attendance).get(), isEmpty);
    });

    test('wipeAllData re-seeds sync state so the app is usable after', () async {
      await db.wipeAllData();

      final rows = await db.syncDao.allSyncState();
      expect(rows, hasLength(AppDatabase.syncedTableNames.length));
      expect(rows.every((r) => r.lastSyncedAt == null), isTrue);
    });

    test('wipeAllData succeeds despite foreign keys', () async {
      // Deleting parents before children would raise; the wipe orders them.
      final memberId = await db.profileDao.createMember(fullName: 'M');
      final planId = await db.membershipDao.createPlan(
        name: 'Monthly',
        durationDays: 30,
        priceMinor: 150000,
      );
      await db.membershipDao.assignPlan(memberId: memberId, planId: planId);
      await db.paymentDao.record(
        memberId: memberId,
        amountMinor: 150000,
        method: PaymentMethod.upi,
      );

      await expectLater(db.wipeAllData(), completes);
    });

    test('hasUnsyncedChanges is false on a clean database', () async {
      await db.wipeAllData();
      expect(await db.hasUnsyncedChanges(), isFalse);
    });

    test('hasUnsyncedChanges detects a dirty row', () async {
      // Locally created rows are dirty until the server accepts them, so
      // signing out here would destroy real work.
      await db.profileDao.createMember(fullName: 'Unsynced Member');
      expect(await db.hasUnsyncedChanges(), isTrue);
    });

    test('hasUnsyncedChanges detects a queued entry with no dirty rows',
        () async {
      await db.syncDao.enqueue(
        entityTable: 'attendance',
        entityId: 'a1',
        operation: 'insert',
      );
      expect(await db.hasUnsyncedChanges(), isTrue);
    });

    test('hasUnsyncedChanges clears once the server accepts the rows',
        () async {
      final memberId = await db.profileDao.createMember(fullName: 'M');
      expect(await db.hasUnsyncedChanges(), isTrue);

      final pending = await db.profileDao.pendingUpload();
      await db.profileDao.clearDirty(pending.map((p) => p.id));

      expect(await db.hasUnsyncedChanges(), isFalse);
      expect(memberId, isNotEmpty);
    });
  });
}
