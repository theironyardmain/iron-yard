import 'package:flutter_test/flutter_test.dart';
import 'package:iron_yard/core/constants/app_constants.dart';
import 'package:iron_yard/data/local/daos/membership_dao.dart';
import 'package:iron_yard/data/local/database.dart';
import 'package:iron_yard/features/members/data/member_repository.dart';
import 'package:iron_yard/features/members/models/member_summary.dart';

void main() {
  late AppDatabase db;
  late MemberRepository repository;

  setUp(() {
    db = AppDatabase.memory();
    repository = MemberRepository(db);
  });

  tearDown(() async => db.close());

  Future<String> addMember(String name, {String? phone, String? email}) =>
      repository.create(fullName: name, phone: phone, email: email);

  group('watchMembers', () {
    test('lists members with no membership as status none', () async {
      await addMember('Solo Member');

      final members = await repository.watchMembers().first;

      expect(members, hasLength(1));
      expect(members.single.status, MembershipStatus.none);
      expect(members.single.membership, isNull);
    });

    test('excludes trainers and admins', () async {
      await addMember('A Member');
      await db.profileDao.createMember(
        fullName: 'A Trainer',
        role: UserRole.trainer,
      );
      await db.profileDao.createMember(
        fullName: 'An Admin',
        role: UserRole.admin,
      );

      final members = await repository.watchMembers().first;

      expect(members, hasLength(1));
      expect(members.single.fullName, 'A Member');
    });

    test('sorts by name, case-insensitively', () async {
      await addMember('zara');
      await addMember('Amit');
      await addMember('Bhavna');

      final members = await repository.watchMembers().first;

      expect(
        members.map((m) => m.fullName),
        ['Amit', 'Bhavna', 'zara'],
      );
    });

    test('picks the membership with the latest end date', () async {
      // A member renewing keeps old rows; the list must show the current one,
      // matching MembershipDao.currentFor.
      final id = await addMember('Renewer');
      final planId = await db.membershipDao.createPlan(
        name: 'Monthly',
        durationDays: 30,
        priceMinor: 150000,
      );

      await db.membershipDao.assignPlan(
        memberId: id,
        planId: planId,
        startDate: DateTime(2026, 1, 1),
      );
      await db.membershipDao.assignPlan(
        memberId: id,
        planId: planId,
        startDate: DateTime(2026, 6, 1),
      );

      final members = await repository.watchMembers().first;

      expect(members, hasLength(1), reason: 'the join must not duplicate rows');
      expect(members.single.membership!.startDate, DateTime(2026, 6, 1));
    });

    test('a member with several memberships appears exactly once', () async {
      final id = await addMember('Multi');
      final planId = await db.membershipDao.createPlan(
        name: 'Monthly',
        durationDays: 30,
        priceMinor: 100,
      );

      for (var month = 1; month <= 4; month++) {
        await db.membershipDao.assignPlan(
          memberId: id,
          planId: planId,
          startDate: DateTime(2026, month, 1),
        );
      }

      final members = await repository.watchMembers().first;
      expect(members, hasLength(1));
    });

    test('includes deactivated members so they can be reactivated', () async {
      final id = await addMember('Gone Away');
      await repository.setActive(id, isActive: false);

      final members = await repository.watchMembers().first;

      expect(members, hasLength(1));
      expect(members.single.isActive, isFalse);
    });

    test('emits again when a member is added', () async {
      final stream = repository.watchMembers();
      expect(await stream.first, isEmpty);

      await addMember('New Member');

      expect(await stream.first, hasLength(1));
    });
  });

  group('daysRemaining', () {
    test('is positive before expiry and negative after', () async {
      final id = await addMember('Timed');
      final planId = await db.membershipDao.createPlan(
        name: '30 day',
        durationDays: 30,
        priceMinor: 100,
      );
      await db.membershipDao.assignPlan(
        memberId: id,
        planId: planId,
        startDate: DateTime.now().subtract(const Duration(days: 10)),
      );

      final summary = await repository.summaryFor(id);
      expect(summary!.daysRemaining, 20);
    });

    test('is null without a membership', () async {
      final id = await addMember('No Plan');
      final summary = await repository.summaryFor(id);
      expect(summary!.daysRemaining, isNull);
    });
  });

  group('applySearch', () {
    late List<MemberSummary> members;

    setUp(() async {
      await addMember('Priya Sharma', phone: '9876543210',
          email: 'priya@example.com');
      await addMember('Rahul Verma', phone: '9123456789');
      await addMember('Anita Desai', email: 'anita@test.in');
      members = await repository.watchMembers().first;
    });

    test('matches on name, ignoring case', () {
      expect(
        MemberRepository.applySearch(members, query: 'priya'),
        hasLength(1),
      );
      expect(
        MemberRepository.applySearch(members, query: 'PRIYA'),
        hasLength(1),
      );
    });

    test('matches on a partial phone number', () {
      final results = MemberRepository.applySearch(members, query: '98765');
      expect(results.single.fullName, 'Priya Sharma');
    });

    test('matches on email', () {
      final results = MemberRepository.applySearch(members, query: 'test.in');
      expect(results.single.fullName, 'Anita Desai');
    });

    test('an empty query returns everything', () {
      expect(MemberRepository.applySearch(members), hasLength(3));
    });

    test('a whitespace-only query returns everything', () {
      expect(
        MemberRepository.applySearch(members, query: '   '),
        hasLength(3),
      );
    });

    test('no match returns empty rather than everything', () {
      expect(
        MemberRepository.applySearch(members, query: 'nobody here'),
        isEmpty,
      );
    });

    test('does not crash on members with null phone or email', () {
      // Anita has no phone, Rahul has no email.
      expect(
        () => MemberRepository.applySearch(members, query: '9'),
        returnsNormally,
      );
    });
  });

  group('MemberFilter', () {
    late String activeId;
    late String expiringId;
    late String expiredId;
    late String noPlanId;
    late String inactiveId;
    late List<MemberSummary> members;

    setUp(() async {
      final planId = await db.membershipDao.createPlan(
        name: 'Monthly',
        durationDays: 30,
        priceMinor: 100,
      );
      final today = DateTime.now();

      activeId = await addMember('Active Member');
      await db.membershipDao.assignPlan(
        memberId: activeId,
        planId: planId,
        startDate: today,
      );

      expiringId = await addMember('Expiring Member');
      await db.membershipDao.assignPlan(
        memberId: expiringId,
        planId: planId,
        startDate: today.subtract(const Duration(days: 27)),
      );

      expiredId = await addMember('Expired Member');
      await db.membershipDao.assignPlan(
        memberId: expiredId,
        planId: planId,
        startDate: today.subtract(const Duration(days: 60)),
      );

      noPlanId = await addMember('No Plan Member');

      inactiveId = await addMember('Inactive Member');
      await repository.setActive(inactiveId, isActive: false);

      members = await repository.watchMembers().first;
    });

    List<String> idsFor(MemberFilter filter) =>
        MemberRepository.applySearch(members, filter: filter)
            .map((m) => m.id)
            .toList();

    test('all hides deactivated members', () {
      // A deactivated member must not read as current in the default view.
      final ids = idsFor(MemberFilter.all);
      expect(ids, hasLength(4));
      expect(ids, isNot(contains(inactiveId)));
    });

    test('active matches only current memberships', () {
      expect(idsFor(MemberFilter.active), [activeId]);
    });

    test('expiringSoon matches the warning window', () {
      expect(idsFor(MemberFilter.expiringSoon), [expiringId]);
    });

    test('expired matches lapsed memberships', () {
      expect(idsFor(MemberFilter.expired), [expiredId]);
    });

    test('noMembership matches members who never had a plan', () {
      expect(idsFor(MemberFilter.noMembership), [noPlanId]);
    });

    test('inactive matches only deactivated members', () {
      expect(idsFor(MemberFilter.inactive), [inactiveId]);
    });

    test('every active member falls in exactly one status filter', () {
      // Overlapping filters would make the chip counts misleading.
      const statusFilters = [
        MemberFilter.active,
        MemberFilter.expiringSoon,
        MemberFilter.expired,
        MemberFilter.noMembership,
      ];

      for (final member in members.where((m) => m.isActive)) {
        final matches =
            statusFilters.where((f) => f.matches(member)).toList();
        expect(
          matches,
          hasLength(1),
          reason: '${member.fullName} matched $matches',
        );
      }
    });

    test('filter and search compose', () {
      final results = MemberRepository.applySearch(
        members,
        query: 'Expired',
        filter: MemberFilter.expired,
      );
      expect(results.single.id, expiredId);

      // The same query under a different filter must find nothing.
      expect(
        MemberRepository.applySearch(
          members,
          query: 'Expired',
          filter: MemberFilter.active,
        ),
        isEmpty,
      );
    });

    test('every filter has a non-empty label', () {
      for (final filter in MemberFilter.values) {
        expect(filter.label, isNotEmpty);
      }
    });
  });

  group('create and update', () {
    test('create stores the supplied fields', () async {
      final id = await repository.create(
        fullName: 'Full Details',
        email: 'full@example.com',
        phone: '9000000000',
        dateOfBirth: DateTime(1990, 5, 20),
        gender: 'Female',
        address: '12 Gym Road',
        heightCm: 165,
        weightKg: 60.5,
        notes: 'Prefers morning sessions',
      );

      final profile = await db.profileDao.byId(id);

      expect(profile!.fullName, 'Full Details');
      expect(profile.email, 'full@example.com');
      expect(profile.dateOfBirth, DateTime(1990, 5, 20));
      expect(profile.heightCm, 165);
      expect(profile.weightKg, 60.5);
      expect(profile.notes, 'Prefers morning sessions');
      expect(profile.role, UserRole.member.wireValue);
    });

    test('height and weight are optional and default to null', () async {
      final id = await repository.create(fullName: 'No Metrics');
      final profile = await db.profileDao.byId(id);

      expect(profile!.heightCm, isNull);
      expect(profile.weightKg, isNull);
    });

    test('update changes height and weight', () async {
      final id = await repository.create(
        fullName: 'Changing',
        heightCm: 170,
        weightKg: 70,
      );

      await repository.update(
        id: id,
        fullName: 'Changing',
        heightCm: 172,
        weightKg: 68.5,
      );

      final profile = await db.profileDao.byId(id);
      expect(profile!.heightCm, 172);
      expect(profile.weightKg, 68.5);
    });

    test('update overwrites and can clear optional fields', () async {
      final id = await repository.create(
        fullName: 'Before',
        phone: '9000000000',
        notes: 'Old note',
      );

      await repository.update(
        id: id,
        fullName: 'After',
        phone: null,
        notes: null,
      );

      final profile = await db.profileDao.byId(id);
      expect(profile!.fullName, 'After');
      expect(profile.phone, isNull);
      expect(profile.notes, isNull);
    });

    test('update marks the row dirty for sync', () async {
      final id = await repository.create(fullName: 'Syncable');
      await db.profileDao.clearDirty([id]);
      expect((await db.profileDao.byId(id))!.isDirty, isFalse);

      await repository.update(id: id, fullName: 'Renamed');

      expect((await db.profileDao.byId(id))!.isDirty, isTrue);
    });

    test('deactivating keeps the member and their history', () async {
      final id = await repository.create(fullName: 'Leaver');
      await db.attendanceDao.recordCheckIn(
        memberId: id,
        source: AttendanceSource.qrScan,
      );

      await repository.setActive(id, isActive: false);

      expect((await db.profileDao.byId(id))!.isActive, isFalse);
      expect(await db.attendanceDao.historyFor(id), hasLength(1));
    });

    test('deactivation is reversible', () async {
      final id = await repository.create(fullName: 'Returner');
      await repository.setActive(id, isActive: false);
      await repository.setActive(id, isActive: true);

      expect((await db.profileDao.byId(id))!.isActive, isTrue);
    });
  });

  group('expiry window boundaries', () {
    late String planId;

    setUp(() async {
      planId = await db.membershipDao.createPlan(
        name: 'Monthly',
        durationDays: 30,
        priceMinor: 100,
      );
    });

    Future<MemberSummary> memberEndingIn(int days) async {
      final id = await addMember('Ends in $days');
      final today = DateTime.now();
      await db.membershipDao.assignPlan(
        memberId: id,
        planId: planId,
        startDate: DateTime(today.year, today.month, today.day + days - 30),
      );
      return (await repository.summaryFor(id))!;
    }

    test('a membership ending today is expiring, not expired', () async {
      final member = await memberEndingIn(0);
      expect(member.daysRemaining, 0);
      expect(member.status, MembershipStatus.expiringSoon);
      expect(MemberFilter.expired.matches(member), isFalse);
    });

    test('a membership that ended yesterday is expired', () async {
      final member = await memberEndingIn(-1);
      expect(member.daysRemaining, -1);
      expect(member.status, MembershipStatus.expired);
    });

    test('the last day inside the warning window is expiringSoon', () async {
      // expiringSoonDays is 7, so day 6 is the last one inside it.
      final member = await memberEndingIn(6);
      expect(member.status, MembershipStatus.expiringSoon);
    });

    test('the first day outside the warning window is active', () async {
      final member = await memberEndingIn(7);
      expect(member.status, MembershipStatus.active);
    });
  });

  group('emergency contact (device-only, brain.md §6.2)', () {
    test('saves and replaces a contact', () async {
      final id = await repository.create(fullName: 'Contactable');

      await repository.setEmergencyContact(
        memberId: id,
        name: 'Anil',
        phone: '9000000000',
        relationship: 'Brother',
      );

      var contact = await repository.emergencyContactFor(id);
      expect(contact!.name, 'Anil');
      expect(contact.relationship, 'Brother');

      await repository.setEmergencyContact(
        memberId: id,
        name: 'Meera',
        phone: '9111111111',
      );

      contact = await repository.emergencyContactFor(id);
      expect(contact!.name, 'Meera');
      expect(contact.relationship, isNull);
    });

    test('is null when never set', () async {
      final id = await repository.create(fullName: 'No Contact');
      expect(await repository.emergencyContactFor(id), isNull);
    });
  });
}
