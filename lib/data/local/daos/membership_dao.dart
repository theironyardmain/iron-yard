import 'package:drift/drift.dart';

import '../database.dart';
import '../tables/profile_tables.dart';
import 'synced_dao.dart';

part 'membership_dao.g.dart';

/// Derived membership state for display (brain.md §6.2, §6.3).
enum MembershipStatus { active, expiringSoon, expired, cancelled, none }

@DriftAccessor(tables: [MembershipPlans, Memberships])
class MembershipDao extends DatabaseAccessor<AppDatabase>
    with _$MembershipDaoMixin, SyncedDaoMixin<AppDatabase, $MembershipsTable, Membership> {
  MembershipDao(super.db);

  @override
  $MembershipsTable get table => memberships;

  /// Days before expiry at which a membership is flagged "expiring soon".
  static const int expiringSoonDays = 7;

  // --- Plans ---

  Future<List<MembershipPlan>> plans({bool activeOnly = true}) {
    return (select(membershipPlans)
          ..where(
            (t) =>
                t.isDeleted.equals(false) &
                (activeOnly ? t.isActive.equals(true) : const Constant(true)),
          )
          ..orderBy([(t) => OrderingTerm.asc(t.name)]))
        .get();
  }

  Stream<List<MembershipPlan>> watchPlans() {
    return (select(membershipPlans)
          ..where((t) => t.isDeleted.equals(false) & t.isActive.equals(true))
          ..orderBy([(t) => OrderingTerm.asc(t.name)]))
        .watch();
  }

  Future<String> createPlan({
    required String name,
    required int durationDays,
    required int priceMinor,
    String? description,
  }) async {
    final id = Uuid.v4();
    await into(membershipPlans).insert(
      MembershipPlansCompanion.insert(
        id: id,
        name: name,
        durationDays: durationDays,
        priceMinor: priceMinor,
        description: Value(description),
        updatedAt: Value(DateTime.now()),
        isDirty: const Value(true),
      ),
    );
    return id;
  }

  Future<MembershipPlan?> planById(String id) {
    return (select(membershipPlans)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
  }

  Future<void> updatePlan({
    required String id,
    required String name,
    required int durationDays,
    required int priceMinor,
    String? description,
  }) async {
    await (update(membershipPlans)..where((t) => t.id.equals(id))).write(
      MembershipPlansCompanion(
        name: Value(name),
        durationDays: Value(durationDays),
        priceMinor: Value(priceMinor),
        description: Value(description),
        updatedAt: Value(DateTime.now()),
        isDirty: const Value(true),
      ),
    );
  }

  /// Retires a plan or brings it back.
  ///
  /// Retiring hides it from the assign picker but leaves existing memberships
  /// untouched — a member on a retired plan keeps their expiry date, and past
  /// revenue still attributes correctly.
  Future<void> setPlanActive(String id, {required bool isActive}) async {
    await (update(membershipPlans)..where((t) => t.id.equals(id))).write(
      MembershipPlansCompanion(
        isActive: Value(isActive),
        updatedAt: Value(DateTime.now()),
        isDirty: const Value(true),
      ),
    );
  }

  /// How many memberships reference this plan.
  ///
  /// Shown before retiring a plan so staff know the impact.
  Future<int> membershipCountFor(String planId) async {
    final count = memberships.id.count();
    final query = selectOnly(memberships)
      ..addColumns([count])
      ..where(
        memberships.planId.equals(planId) & memberships.isDeleted.equals(false),
      );
    return (await query.getSingle()).read(count) ?? 0;
  }

  // --- Memberships ---

  /// Assigns a plan to a member, deriving the expiry date from the plan
  /// duration.
  Future<String> assignPlan({
    required String memberId,
    required String planId,
    DateTime? startDate,
  }) async {
    final plan = await (select(membershipPlans)
          ..where((t) => t.id.equals(planId)))
        .getSingle();

    final start = DayKey.of(startDate);
    final end = DateTime(
      start.year,
      start.month,
      start.day + plan.durationDays,
    );

    final id = Uuid.v4();
    await into(memberships).insert(
      MembershipsCompanion.insert(
        id: id,
        memberId: memberId,
        planId: planId,
        startDate: start,
        endDate: end,
        updatedAt: Value(DateTime.now()),
        isDirty: const Value(true),
      ),
    );
    return id;
  }

  /// The member's current membership — the one with the latest end date.
  Future<Membership?> currentFor(String memberId) {
    return (select(memberships)
          ..where(
            (t) =>
                t.memberId.equals(memberId) &
                t.isDeleted.equals(false) &
                t.status.equals('cancelled').not(),
          )
          ..orderBy([(t) => OrderingTerm.desc(t.endDate)])
          ..limit(1))
        .getSingleOrNull();
  }

  Future<List<Membership>> historyFor(String memberId) {
    return (select(memberships)
          ..where((t) => t.memberId.equals(memberId) & t.isDeleted.equals(false))
          ..orderBy([(t) => OrderingTerm.desc(t.startDate)]))
        .get();
  }

  /// Memberships expiring within [days] — the admin "expiring soon" list.
  Future<List<Membership>> expiringWithin({
    int days = expiringSoonDays,
    DateTime? from,
  }) {
    final start = DayKey.of(from);
    final cutoff = DateTime(start.year, start.month, start.day + days);

    return (select(memberships)
          ..where(
            (t) =>
                t.isDeleted.equals(false) &
                t.status.equals('active') &
                t.endDate.isBiggerOrEqualValue(start) &
                t.endDate.isSmallerThanValue(cutoff),
          )
          ..orderBy([(t) => OrderingTerm.asc(t.endDate)]))
        .get();
  }

  /// Renews a member onto [planId], continuing from their current expiry.
  ///
  /// A member renewing before expiry keeps their remaining days: the new term
  /// starts the day after the current one ends, not today. Renewing after
  /// expiry starts from today.
  Future<String> renew({
    required String memberId,
    required String planId,
    DateTime? asOf,
  }) async {
    final current = await currentFor(memberId);
    final today = DayKey.of(asOf);

    var start = today;
    if (current != null && current.status == 'active') {
      final currentEnd = DayKey.of(current.endDate);
      if (!currentEnd.isBefore(today)) {
        start = DateTime(
          currentEnd.year,
          currentEnd.month,
          currentEnd.day + 1,
        );
      }
    }

    return assignPlan(memberId: memberId, planId: planId, startDate: start);
  }

  /// Live membership list for one member, newest first.
  Stream<List<Membership>> watchHistoryFor(String memberId) {
    return (select(memberships)
          ..where((t) => t.memberId.equals(memberId) & t.isDeleted.equals(false))
          ..orderBy([(t) => OrderingTerm.desc(t.startDate)]))
        .watch();
  }

  Future<void> cancel(String membershipId) async {
    await (update(memberships)..where((t) => t.id.equals(membershipId))).write(
      MembershipsCompanion(
        status: const Value('cancelled'),
        updatedAt: Value(DateTime.now()),
        isDirty: const Value(true),
      ),
    );
  }

  /// Derives display status from the stored status and dates.
  ///
  /// Dates are the source of truth for active/expired; the stored status only
  /// carries an explicit cancellation.
  static MembershipStatus statusOf(Membership? membership, {DateTime? asOf}) {
    if (membership == null) return MembershipStatus.none;
    if (membership.status == 'cancelled') return MembershipStatus.cancelled;

    final today = DayKey.of(asOf);
    final end = DayKey.of(membership.endDate);

    if (end.isBefore(today)) return MembershipStatus.expired;

    final soonCutoff = DateTime(
      today.year,
      today.month,
      today.day + expiringSoonDays,
    );
    if (end.isBefore(soonCutoff)) return MembershipStatus.expiringSoon;

    return MembershipStatus.active;
  }
}
