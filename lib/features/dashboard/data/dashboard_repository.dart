import 'package:drift/drift.dart';

import '../../../core/constants/app_constants.dart';
import '../../../data/local/daos/membership_dao.dart';
import '../../../data/local/database.dart';

/// The figures on the admin home (brain.md §6.3).
class DashboardSummary {
  const DashboardSummary({
    required this.todayAttendance,
    required this.activeMembers,
    required this.expiringSoon,
    required this.expired,
    required this.monthRevenueMinor,
    required this.pendingPayments,
    required this.upcomingClasses,
    required this.unverifiedToday,
  });

  /// Staff-verified check-ins today. Self-reported entries are counted
  /// separately in [unverifiedToday] while owner decision #1 is open.
  final int todayAttendance;

  /// Self-reported check-ins today, shown apart from the verified figure.
  final int unverifiedToday;

  final int activeMembers;
  final int expiringSoon;
  final int expired;
  final int monthRevenueMinor;
  final int pendingPayments;
  final int upcomingClasses;

  /// Members needing attention — expiring or already lapsed.
  int get needsAttention => expiringSoon + expired;
}

/// A day's attendance, for the trend chart.
typedef AttendancePoint = ({DateTime day, int verified, int selfReported});

/// Dashboard and report figures, all from the local cache (brain.md §6.3).
///
/// Nothing here touches the network: the dashboard must open offline, showing
/// whatever the last sync delivered.
class DashboardRepository {
  DashboardRepository(this._db);

  final AppDatabase _db;

  /// Everything the admin home needs, in one pass.
  Future<DashboardSummary> summary({DateTime? asOf}) async {
    final now = asOf ?? DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final monthStart = DateTime(now.year, now.month);
    final monthEnd = DateTime(
      now.year,
      now.month + 1,
    ).subtract(const Duration(microseconds: 1));

    final memberships = await _membershipCounts(asOf: now);

    return DashboardSummary(
      todayAttendance: await _db.attendanceDao.countForDay(day: today),
      unverifiedToday:
          await _db.attendanceDao.countForDay(
            day: today,
            verifiedOnly: false,
          ) -
          await _db.attendanceDao.countForDay(day: today),
      activeMembers: memberships.active,
      expiringSoon: memberships.expiringSoon,
      expired: memberships.expired,
      monthRevenueMinor: await _db.paymentDao.revenueInRange(
        from: monthStart,
        to: monthEnd,
      ),
      pendingPayments: (await _db.paymentDao.pendingPayments()).length,
      upcomingClasses: await _upcomingClassCount(from: now),
    );
  }

  /// Counts members by derived membership status.
  ///
  /// Derived from dates rather than the stored status: `expire_memberships()`
  /// on the server may not have run, and the dashboard must not claim a lapsed
  /// membership is active.
  Future<({int active, int expiringSoon, int expired})> _membershipCounts({
    DateTime? asOf,
  }) async {
    final now = asOf ?? DateTime.now();

    final rows = await _db
        .customSelect(
          '''
          SELECT m.end_date, m.status
          FROM memberships m
          JOIN profiles p ON p.id = m.member_id
          WHERE m.is_deleted = 0
            AND p.is_deleted = 0
            AND p.is_active = 1
            AND m.id = (
              SELECT m2.id FROM memberships m2
              WHERE m2.member_id = m.member_id AND m2.is_deleted = 0
              ORDER BY m2.end_date DESC LIMIT 1
            )
          ''',
          readsFrom: {_db.memberships, _db.profiles},
        )
        .get();

    var active = 0;
    var expiringSoon = 0;
    var expired = 0;

    for (final row in rows) {
      if (row.data['status'] == 'cancelled') continue;

      final endRaw = row.data['end_date'];
      final end = endRaw is int
          ? DateTime.fromMillisecondsSinceEpoch(endRaw * 1000)
          : DateTime.tryParse('$endRaw');
      if (end == null) continue;

      final endDay = DateTime(end.year, end.month, end.day);
      final today = DateTime(now.year, now.month, now.day);
      final soonCutoff = DateTime(
        today.year,
        today.month,
        today.day + MembershipDao.expiringSoonDays,
      );

      if (endDay.isBefore(today)) {
        expired++;
      } else if (endDay.isBefore(soonCutoff)) {
        expiringSoon++;
      } else {
        active++;
      }
    }

    return (active: active, expiringSoon: expiringSoon, expired: expired);
  }

  Future<int> _upcomingClassCount({DateTime? from}) async {
    final since = from ?? DateTime.now();
    final count = _db.classes.id.count();

    final query = _db.selectOnly(_db.classes)
      ..addColumns([count])
      ..where(
        _db.classes.isDeleted.equals(false) &
            _db.classes.status.equals('scheduled') &
            _db.classes.startsAt.isBiggerThanValue(since),
      );

    return (await query.getSingle()).read(count) ?? 0;
  }

  /// Daily attendance over the last [days], oldest first.
  ///
  /// Verified and self-reported are kept apart: mixing them would silently
  /// decide owner question #1 (brain.md §6.7).
  Future<List<AttendancePoint>> attendanceTrend({
    int days = 14,
    DateTime? asOf,
  }) async {
    final now = asOf ?? DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final from = DateTime(today.year, today.month, today.day - days + 1);

    final records = await _db.attendanceDao.inRange(from: from, to: today);

    final verified = <String, int>{};
    final selfReported = <String, int>{};

    for (final record in records) {
      final day = record.attendanceDate;
      final key = '${day.year}-${day.month}-${day.day}';

      if (record.source == AttendanceSource.qrScan.wireValue) {
        verified[key] = (verified[key] ?? 0) + 1;
      } else {
        selfReported[key] = (selfReported[key] ?? 0) + 1;
      }
    }

    return [
      for (var i = 0; i < days; i++)
        () {
          final day = DateTime(today.year, today.month, today.day - days + 1 + i);
          final key = '${day.year}-${day.month}-${day.day}';
          return (
            day: day,
            verified: verified[key] ?? 0,
            selfReported: selfReported[key] ?? 0,
          );
        }(),
    ];
  }

  /// Members whose membership is expiring or has expired, soonest first.
  Future<List<({Profile member, Membership membership})>> needsAttention({
    DateTime? asOf,
  }) async {
    final now = asOf ?? DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final cutoff = DateTime(
      today.year,
      today.month,
      today.day + MembershipDao.expiringSoonDays,
    );

    final memberships = await (_db.select(_db.memberships)
          ..where(
            (t) =>
                t.isDeleted.equals(false) &
                t.status.equals('cancelled').not() &
                t.endDate.isSmallerThanValue(cutoff),
          )
          ..orderBy([(t) => OrderingTerm.asc(t.endDate)]))
        .get();

    final result = <({Profile member, Membership membership})>[];
    final seen = <String>{};

    for (final membership in memberships) {
      // Only the current membership per member; an old expired one alongside a
      // current active one is not a problem to chase.
      if (!seen.add(membership.memberId)) continue;

      final current = await _db.membershipDao.currentFor(membership.memberId);
      if (current == null || current.id != membership.id) continue;

      final member = await _db.profileDao.byId(membership.memberId);
      if (member == null || member.isDeleted || !member.isActive) continue;

      result.add((member: member, membership: membership));
    }

    return result;
  }

  /// Revenue per month over the last [months], oldest first.
  Future<List<({DateTime month, int revenueMinor})>> revenueTrend({
    int months = 6,
    DateTime? asOf,
  }) async {
    final now = asOf ?? DateTime.now();
    final result = <({DateTime month, int revenueMinor})>[];

    for (var i = months - 1; i >= 0; i--) {
      final start = DateTime(now.year, now.month - i);
      final end = DateTime(
        now.year,
        now.month - i + 1,
      ).subtract(const Duration(microseconds: 1));

      result.add((
        month: start,
        revenueMinor: await _db.paymentDao.revenueInRange(
          from: start,
          to: end,
        ),
      ));
    }

    return result;
  }
}
