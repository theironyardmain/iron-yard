import 'package:flutter_test/flutter_test.dart';
import 'package:iron_yard/core/constants/app_constants.dart';
import 'package:iron_yard/data/local/daos/attendance_dao.dart';
import 'package:iron_yard/data/local/daos/class_dao.dart';
import 'package:iron_yard/data/local/database.dart';
import 'package:iron_yard/features/attendance/data/attendance_repository.dart';
import 'package:iron_yard/features/checkin/data/checkin_repository.dart';
import 'package:iron_yard/features/checkin/data/checkin_settings.dart';
import 'package:iron_yard/features/dashboard/data/csv_exporter.dart';
import 'package:iron_yard/features/dashboard/data/dashboard_repository.dart';
import 'package:iron_yard/features/members/data/member_repository.dart';
import 'package:iron_yard/features/payments/data/payment_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Verifies every feature `brain.md` §7 promises works offline (tasks.md 16.1).
///
/// These run against the local database with **no Supabase client constructed
/// at all** — if any path reached for the network, it would throw here. That is
/// the point: the offline-first claim in `brain.md` §1 is the app's central
/// promise, and this is what checks it.
void main() {
  late AppDatabase db;
  late String memberId;
  late String planId;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.memory();

    memberId = await db.profileDao.createMember(
      fullName: 'Offline Member',
      phone: '9876543210',
    );
    planId = await db.membershipDao.createPlan(
      name: 'Monthly',
      durationDays: 30,
      priceMinor: 150000,
    );
    await db.membershipDao.assignPlan(memberId: memberId, planId: planId);
  });

  tearDown(() async => db.close());

  group('brain.md §7 — works fully offline', () {
    test('member profile', () async {
      final profile = await db.profileDao.byId(memberId);
      expect(profile!.fullName, 'Offline Member');

      final members = await MemberRepository(db).watchMembers().first;
      expect(members, hasLength(1));
      expect(members.single.status, isNotNull);
    });

    test('QR card renders from cached data', () async {
      // The member must be able to show their card at the desk with no signal.
      final payload = await AttendanceRepository(db).cardFor(memberId);

      expect(payload, isNotNull);
      expect(payload!.memberId, memberId);
      expect(payload.encode(), contains(memberId));
    });

    test('attendance scanning', () async {
      final repository = AttendanceRepository(db);
      final card = (await repository.cardFor(memberId))!.encode();

      final outcome = await repository.handleScan(card);

      expect(outcome.recorded, isTrue);
      expect(await repository.todayCount(), 1);
    });

    test('attendance history', () async {
      await db.attendanceDao.recordCheckIn(
        memberId: memberId,
        source: AttendanceSource.qrScan,
      );

      final history = await db.attendanceDao.historyFor(memberId);
      expect(history, hasLength(1));
    });

    test('workout plans', () async {
      final templateId = await db.planDao.createWorkoutPlan(name: 'Push');
      await db.planDao.addExercise(
        planId: templateId,
        name: 'Bench Press',
        sets: 4,
        reps: 8,
      );

      final assignedId = await db.planDao.assignWorkoutPlan(
        templateId: templateId,
        memberId: memberId,
      );

      final exercises = await db.planDao.exercisesFor(assignedId);
      expect(exercises, hasLength(1));
      expect(exercises.single.name, 'Bench Press');
    });

    test('diet plans', () async {
      final templateId = await db.planDao.createDietPlan(
        name: 'Cutting',
        mealsJson: '[{"meal":"Breakfast","items":["Oats"]}]',
      );
      final assignedId = await db.planDao.assignDietPlan(
        templateId: templateId,
        memberId: memberId,
      );

      final plan = await db.planDao.dietPlanById(assignedId);
      expect(plan!.mealsJson, contains('Oats'));
    });

    test('exercise progress', () async {
      final templateId = await db.planDao.createWorkoutPlan(name: 'Push');
      final exerciseId = await db.planDao.addExercise(
        planId: templateId,
        name: 'Squat',
      );

      final done = await db.planDao.toggleCompletion(
        exerciseId: exerciseId,
        memberId: memberId,
      );

      expect(done, isTrue);
      expect(
        await db.planDao.completedOn(memberId: memberId),
        contains(exerciseId),
      );
    });

    test('draft payments', () async {
      final repository = PaymentRepository(db);

      final id = await repository.record(
        memberId: memberId,
        amountMinor: 150000,
        method: PaymentMethod.cash,
      );

      expect((await db.paymentDao.byId(id))!.isDirty, isTrue);
      expect(await repository.historyFor(memberId), hasLength(1));
    });

    test('downloaded payment history', () async {
      await PaymentRepository(db).record(
        memberId: memberId,
        amountMinor: 150000,
        method: PaymentMethod.upi,
      );

      final history = await db.paymentDao.historyFor(memberId);
      expect(history, hasLength(1));
    });

    test('downloaded class schedule', () async {
      final future = DateTime.now().add(const Duration(days: 2));
      await db.classDao.createClass(
        name: 'Yoga',
        startsAt: future,
        endsAt: future.add(const Duration(hours: 1)),
        capacity: 10,
      );

      final upcoming = await db.classDao.watchUpcoming().first;
      expect(upcoming, hasLength(1));
    });

    test('class booking is queued offline', () async {
      final future = DateTime.now().add(const Duration(days: 2));
      final classId = await db.classDao.createClass(
        name: 'Yoga',
        startsAt: future,
        endsAt: future.add(const Duration(hours: 1)),
        capacity: 10,
      );

      final result = await db.classDao.book(
        classId: classId,
        memberId: memberId,
      );

      expect(result, BookingResult.booked);

      final booking = await db.classDao.bookingFor(
        classId: classId,
        memberId: memberId,
      );
      expect(booking!.isDirty, isTrue, reason: 'queued for upload');
    });

    test('announcement history', () async {
      await db.announcementDao.create(title: 'Closed Monday', body: 'Notice');

      final feed = await db.announcementDao.watchPublished().first;
      expect(feed, hasLength(1));
    });

    test('daily check-in capture', () async {
      final prefs = await SharedPreferences.getInstance();
      final repository = CheckInRepository(
        db: db,
        settings: CheckInSettingsStore(prefs),
      );

      // Pinned inside today: "an hour ago" lands on yesterday when the suite
      // runs just after midnight, which files the record under the wrong day.
      final now = DateTime.now();
      final result = await repository.logSession(
        memberId: memberId,
        startedAt: DateTime(now.year, now.month, now.day, 9),
        endedAt: DateTime(now.year, now.month, now.day, 10),
      );

      expect(result, CheckInResult.recorded);
      expect(await repository.todaysRecord(memberId), isNotNull);
    });

    test('feedback submission is queued offline', () async {
      await db.announcementDao.submitFeedback(
        memberId: memberId,
        message: 'Raised on the gym floor with no signal.',
      );

      final mine = await db.announcementDao.watchFeedbackFor(memberId).first;
      expect(mine.single.isDirty, isTrue);
    });

    test('emergency contacts', () async {
      // Device-only by design (brain.md §6.2) — never leaves the phone.
      await db.profileDao.setEmergencyContact(
        profileId: memberId,
        name: 'Anil',
        phone: '9000000000',
      );

      final contact = await db.profileDao.emergencyContactFor(memberId);
      expect(contact!.name, 'Anil');
    });

    test('the admin dashboard opens with figures', () async {
      await db.attendanceDao.recordCheckIn(
        memberId: memberId,
        source: AttendanceSource.qrScan,
      );
      await PaymentRepository(db).record(
        memberId: memberId,
        amountMinor: 150000,
        method: PaymentMethod.cash,
      );

      final summary = await DashboardRepository(db).summary();

      expect(summary.todayAttendance, 1);
      expect(summary.activeMembers, 1);
      expect(summary.monthRevenueMinor, 150000);
    });

    test('CSV export works from the cache', () async {
      final csv = await CsvExporter(db).build(ExportKind.members);
      expect(csv, contains('Offline Member'));
    });
  });

  group('offline work is preserved for sync', () {
    test('every offline write is marked dirty', () async {
      // Anything not flagged would never upload — silent data loss.
      await db.attendanceDao.recordCheckIn(
        memberId: memberId,
        source: AttendanceSource.qrScan,
      );
      await PaymentRepository(db).record(
        memberId: memberId,
        amountMinor: 1000,
        method: PaymentMethod.cash,
      );
      await db.announcementDao.submitFeedback(
        memberId: memberId,
        message: 'Note',
      );

      expect(await db.hasUnsyncedChanges(), isTrue);

      expect((await db.attendanceDao.pendingUpload()), isNotEmpty);
      expect((await db.paymentDao.pendingUpload()), isNotEmpty);
    });

    test('a full offline session survives without any sync', () async {
      // A whole day at the desk with no connection: scan, take payment,
      // assign a plan, book a class. Nothing may be lost.
      final future = DateTime.now().add(const Duration(days: 1));

      await db.attendanceDao.recordCheckIn(
        memberId: memberId,
        source: AttendanceSource.qrScan,
      );
      await PaymentRepository(db).record(
        memberId: memberId,
        amountMinor: 150000,
        method: PaymentMethod.cash,
      );
      final templateId = await db.planDao.createWorkoutPlan(name: 'Full Body');
      await db.planDao.assignWorkoutPlan(
        templateId: templateId,
        memberId: memberId,
      );
      final classId = await db.classDao.createClass(
        name: 'Spin',
        startsAt: future,
        endsAt: future.add(const Duration(hours: 1)),
        capacity: 10,
      );
      await db.classDao.book(classId: classId, memberId: memberId);

      expect(await db.attendanceDao.historyFor(memberId), hasLength(1));
      expect(await db.paymentDao.historyFor(memberId), hasLength(1));
      expect(await db.planDao.assignedWorkoutsFor(memberId), hasLength(1));
      expect(await db.classDao.bookedCount(classId), 1);
      expect(await db.hasUnsyncedChanges(), isTrue);
    });
  });
}
