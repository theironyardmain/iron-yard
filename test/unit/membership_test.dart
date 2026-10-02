import 'package:flutter_test/flutter_test.dart';
import 'package:iron_yard/core/constants/app_constants.dart';
import 'package:iron_yard/core/utils/money.dart';
import 'package:iron_yard/data/local/daos/membership_dao.dart';
import 'package:iron_yard/data/local/database.dart';
import 'package:iron_yard/features/memberships/data/membership_repository.dart';

void main() {
  group('Money', () {
    test('formats whole rupees without decimals', () {
      // 150000 paise = 1500 rupees.
      expect(Money.format(150000), '₹1,500');
      expect(Money.format(100), '₹1');
      expect(Money.format(0), '₹0');
    });

    test('groups large amounts in the Indian system', () {
      // en_IN groups as lakh/crore: 12,34,567 not 1,234,567.
      expect(Money.format(123456700), '₹12,34,567');
    });

    test('shows paise only when they are non-zero', () {
      expect(Money.format(150050), contains('.50'));
      expect(Money.format(150000), isNot(contains('.')));
    });

    test('parses plain, comma-separated and symbol-prefixed input', () {
      expect(Money.parse('1500'), 150000);
      expect(Money.parse('1,500'), 150000);
      expect(Money.parse('₹1500'), 150000);
      expect(Money.parse(' 1500 '), 150000);
    });

    test('parses decimal rupees into paise', () {
      expect(Money.parse('1500.50'), 150050);
      expect(Money.parse('0.99'), 99);
    });

    test('rounds rather than truncating', () {
      // Truncation would lose a paisa on every such amount.
      expect(Money.parse('10.555'), 1056);
      expect(Money.parse('10.554'), 1055);
    });

    test('rejects invalid and negative input', () {
      expect(Money.parse(''), isNull);
      expect(Money.parse('abc'), isNull);
      expect(Money.parse('-100'), isNull);
      expect(Money.parse('₹'), isNull);
    });

    test('round-trips through toInput', () {
      for (final minor in [0, 100, 150000, 99, 150050]) {
        expect(Money.parse(Money.toInput(minor)), minor, reason: '$minor');
      }
    });

    test('toInput omits decimals for whole rupees', () {
      expect(Money.toInput(150000), '1500');
      expect(Money.toInput(150050), '1500.50');
    });
  });

  group('formatDuration', () {
    test('uses the units people say', () {
      expect(formatDuration(30), '1 month');
      expect(formatDuration(90), '3 months');
      expect(formatDuration(365), '1 year');
      expect(formatDuration(7), '1 week');
      expect(formatDuration(14), '2 weeks');
      expect(formatDuration(1), '1 day');
      expect(formatDuration(45), '45 days');
    });

    test('prefers years over months where both divide', () {
      // 730 is both 24 months and 2 years; "2 years" is what a person says.
      expect(formatDuration(730), '2 years');
    });
  });

  group('plan management', () {
    late AppDatabase db;
    late MembershipDao dao;

    setUp(() {
      db = AppDatabase.memory();
      dao = db.membershipDao;
    });
    tearDown(() async => db.close());

    test('creates and reads back a plan', () async {
      final id = await dao.createPlan(
        name: 'Monthly',
        durationDays: 30,
        priceMinor: 150000,
        description: 'Full gym access',
      );

      final plan = await dao.planById(id);
      expect(plan!.name, 'Monthly');
      expect(plan.priceMinor, 150000);
      expect(plan.isActive, isTrue);
      expect(plan.isDirty, isTrue, reason: 'new rows must sync');
    });

    test('updates a plan', () async {
      final id = await dao.createPlan(
        name: 'Monthly',
        durationDays: 30,
        priceMinor: 150000,
      );

      await dao.updatePlan(
        id: id,
        name: 'Monthly Plus',
        durationDays: 31,
        priceMinor: 175000,
      );

      final plan = await dao.planById(id);
      expect(plan!.name, 'Monthly Plus');
      expect(plan.priceMinor, 175000);
      expect(plan.durationDays, 31);
    });

    test('retiring a plan hides it from the picker but keeps it listed',
        () async {
      final id = await dao.createPlan(
        name: 'Old Plan',
        durationDays: 30,
        priceMinor: 100,
      );

      await dao.setPlanActive(id, isActive: false);

      expect(await dao.plans(), isEmpty);
      expect(await dao.plans(activeOnly: false), hasLength(1));
    });

    test('retiring a plan does not touch existing memberships', () async {
      // Staff must be able to stop selling a plan without cancelling the
      // members already on it.
      final memberId = await db.profileDao.createMember(fullName: 'M');
      final planId = await dao.createPlan(
        name: 'Retiring',
        durationDays: 30,
        priceMinor: 100,
      );
      await dao.assignPlan(memberId: memberId, planId: planId);

      await dao.setPlanActive(planId, isActive: false);

      final current = await dao.currentFor(memberId);
      expect(current, isNotNull);
      expect(current!.status, 'active');
    });

    test('counts memberships on a plan', () async {
      final planId = await dao.createPlan(
        name: 'Popular',
        durationDays: 30,
        priceMinor: 100,
      );

      expect(await dao.membershipCountFor(planId), 0);

      for (var i = 0; i < 3; i++) {
        final memberId = await db.profileDao.createMember(fullName: 'M$i');
        await dao.assignPlan(memberId: memberId, planId: planId);
      }

      expect(await dao.membershipCountFor(planId), 3);
    });
  });

  group('renewal (brain.md §6.3)', () {
    late AppDatabase db;
    late MembershipDao dao;
    late String memberId;
    late String planId;

    setUp(() async {
      db = AppDatabase.memory();
      dao = db.membershipDao;
      memberId = await db.profileDao.createMember(fullName: 'Renewer');
      planId = await dao.createPlan(
        name: 'Monthly',
        durationDays: 30,
        priceMinor: 150000,
      );
    });
    tearDown(() async => db.close());

    test('a first assignment starts today', () async {
      final today = DateTime(2026, 3, 10);
      await dao.renew(memberId: memberId, planId: planId, asOf: today);

      final current = await dao.currentFor(memberId);
      expect(current!.startDate, today);
      expect(current.endDate, DateTime(2026, 4, 9));
    });

    test('renewing early continues from the current expiry', () async {
      // The member paid for those days; renewing must not discard them.
      await dao.assignPlan(
        memberId: memberId,
        planId: planId,
        startDate: DateTime(2026, 3, 1),
      );
      // Current term runs to 31 Mar. Renew on 20 Mar, 11 days early.
      await dao.renew(
        memberId: memberId,
        planId: planId,
        asOf: DateTime(2026, 3, 20),
      );

      final current = await dao.currentFor(memberId);
      expect(
        current!.startDate,
        DateTime(2026, 4, 1),
        reason: 'the new term starts the day after the old one ends',
      );
      expect(current.endDate, DateTime(2026, 5, 1));
    });

    test('renewing after expiry starts today, not from the lapsed date',
        () async {
      // Otherwise a member who lapsed for months would get backdated days.
      await dao.assignPlan(
        memberId: memberId,
        planId: planId,
        startDate: DateTime(2026, 1, 1),
      );
      await dao.renew(
        memberId: memberId,
        planId: planId,
        asOf: DateTime(2026, 6, 15),
      );

      final current = await dao.currentFor(memberId);
      expect(current!.startDate, DateTime(2026, 6, 15));
      expect(current.endDate, DateTime(2026, 7, 15));
    });

    test('renewing on the exact expiry day loses no days', () async {
      await dao.assignPlan(
        memberId: memberId,
        planId: planId,
        startDate: DateTime(2026, 3, 1),
      );
      // Term ends 31 Mar; renew that day.
      await dao.renew(
        memberId: memberId,
        planId: planId,
        asOf: DateTime(2026, 3, 31),
      );

      final current = await dao.currentFor(memberId);
      expect(current!.startDate, DateTime(2026, 4, 1));
    });

    test('renewing the day after expiry starts that day', () async {
      await dao.assignPlan(
        memberId: memberId,
        planId: planId,
        startDate: DateTime(2026, 3, 1),
      );
      await dao.renew(
        memberId: memberId,
        planId: planId,
        asOf: DateTime(2026, 4, 1),
      );

      final current = await dao.currentFor(memberId);
      expect(current!.startDate, DateTime(2026, 4, 1));
    });

    test('a cancelled membership does not extend a renewal', () async {
      final id = await dao.assignPlan(
        memberId: memberId,
        planId: planId,
        startDate: DateTime(2026, 3, 1),
      );
      await dao.cancel(id);

      await dao.renew(
        memberId: memberId,
        planId: planId,
        asOf: DateTime(2026, 3, 10),
      );

      final current = await dao.currentFor(memberId);
      expect(
        current!.startDate,
        DateTime(2026, 3, 10),
        reason: 'a cancelled term must not be continued from',
      );
    });

    test('repeated renewals stack without gaps or overlaps', () async {
      // Renew three times, each a few days before the running term ends, so
      // every call takes the "renew early" branch.
      await dao.renew(
        memberId: memberId,
        planId: planId,
        asOf: DateTime(2026, 1, 1),
      );
      for (final asOf in [DateTime(2026, 1, 28), DateTime(2026, 2, 25)]) {
        await dao.renew(memberId: memberId, planId: planId, asOf: asOf);
      }

      final history = await dao.historyFor(memberId);
      expect(history, hasLength(3));

      // Sorted newest first; walk back and check each starts the day after
      // the previous one ends.
      final ordered = history.reversed.toList();
      for (var i = 1; i < ordered.length; i++) {
        final previousEnd = ordered[i - 1].endDate;
        expect(
          ordered[i].startDate,
          DateTime(previousEnd.year, previousEnd.month, previousEnd.day + 1),
          reason: 'term $i must start the day after term ${i - 1} ends',
        );
      }
    });

    test('renewal keeps the member continuously active', () async {
      await dao.assignPlan(
        memberId: memberId,
        planId: planId,
        startDate: DateTime.now().subtract(const Duration(days: 28)),
      );
      expect(
        MembershipDao.statusOf(await dao.currentFor(memberId)),
        MembershipStatus.expiringSoon,
      );

      await dao.renew(memberId: memberId, planId: planId);

      expect(
        MembershipDao.statusOf(await dao.currentFor(memberId)),
        MembershipStatus.active,
      );
    });
  });

  group('expiringWithin', () {
    late AppDatabase db;
    late MembershipDao dao;
    late String planId;

    setUp(() async {
      db = AppDatabase.memory();
      dao = db.membershipDao;
      planId = await dao.createPlan(
        name: 'Monthly',
        durationDays: 30,
        priceMinor: 100,
      );
    });
    tearDown(() async => db.close());

    Future<String> memberExpiringIn(int days) async {
      final id = await db.profileDao.createMember(fullName: 'Ends in $days');
      final today = DateTime.now();
      await dao.assignPlan(
        memberId: id,
        planId: planId,
        startDate: DateTime(today.year, today.month, today.day + days - 30),
      );
      return id;
    }

    test('includes memberships inside the window', () async {
      await memberExpiringIn(3);
      expect(await dao.expiringWithin(), hasLength(1));
    });

    test('excludes memberships outside the window', () async {
      await memberExpiringIn(20);
      expect(await dao.expiringWithin(), isEmpty);
    });

    test('excludes already-expired memberships', () async {
      // They belong in an "expired" list, not a renewal prompt.
      await memberExpiringIn(-5);
      expect(await dao.expiringWithin(), isEmpty);
    });

    test('includes a membership expiring today', () async {
      await memberExpiringIn(0);
      expect(await dao.expiringWithin(), hasLength(1));
    });

    test('excludes cancelled memberships', () async {
      final id = await memberExpiringIn(3);
      final current = await dao.currentFor(id);
      await dao.cancel(current!.id);

      expect(await dao.expiringWithin(), isEmpty);
    });

    test('orders soonest first', () async {
      await memberExpiringIn(5);
      await memberExpiringIn(1);
      await memberExpiringIn(3);

      final expiring = await dao.expiringWithin();
      final dates = expiring.map((m) => m.endDate).toList();
      final sorted = [...dates]..sort();
      expect(dates, sorted);
    });
  });

  group('MembershipRepository (brain.md §6.5)', () {
    late AppDatabase db;
    late MembershipRepository repository;
    late String memberId;
    late String planId;

    setUp(() async {
      db = AppDatabase.memory();
      repository = MembershipRepository(db);
      memberId = await db.profileDao.createMember(fullName: 'Invoiced');
      planId = await db.membershipDao.createPlan(
        name: 'Monthly',
        durationDays: 30,
        priceMinor: 150000,
      );
    });
    tearDown(() async => db.close());

    test('assignPlan creates the membership and an invoice for the plan price',
        () async {
      final result = await repository.assignPlan(
        memberId: memberId,
        planId: planId,
      );

      final membership = await db.membershipDao.currentFor(memberId);
      expect(membership!.id, result.membershipId);

      final invoice = await db.invoiceDao.byId(result.invoiceId);
      expect(invoice!.memberId, memberId);
      expect(invoice.membershipId, result.membershipId);
      expect(invoice.totalMinor, 150000);
      expect(invoice.status, 'unpaid');
      expect(invoice.kind, 'plan_charge');
    });

    test('renew creates a new invoice each time', () async {
      final first = await repository.assignPlan(
        memberId: memberId,
        planId: planId,
      );
      final second = await repository.renew(
        memberId: memberId,
        planId: planId,
      );

      expect(second.invoiceId, isNot(first.invoiceId));
      expect(await db.invoiceDao.balanceFor(memberId), 300000);
    });

    test('createdBy is attributed to the invoice', () async {
      final staffId = await db.profileDao.createMember(
        fullName: 'Desk',
        role: UserRole.admin,
      );

      final result = await repository.assignPlan(
        memberId: memberId,
        planId: planId,
        createdBy: staffId,
      );

      final invoice = await db.invoiceDao.byId(result.invoiceId);
      expect(invoice!.createdBy, staffId);
    });
  });
}
