import 'package:drift/drift.dart';

import '../../../core/constants/app_constants.dart';
import '../database.dart';
import '../tables/attendance_tables.dart';
import 'synced_dao.dart';

part 'attendance_dao.g.dart';

/// The outcome of attempting a check-in (brain.md §6.4).
enum CheckInResult {
  /// Recorded.
  recorded,

  /// The member already has an attendance record for today. Not an error — the
  /// scanner shows it as "already checked in" rather than failing.
  duplicate,

  /// Upgraded an existing self-reported entry to a staff-verified QR scan.
  upgradedFromSelfReport,
}

@DriftAccessor(tables: [Attendance])
class AttendanceDao extends DatabaseAccessor<AppDatabase>
    with _$AttendanceDaoMixin, SyncedDaoMixin<AppDatabase, $AttendanceTable, AttendanceData> {
  AttendanceDao(super.db);

  @override
  $AttendanceTable get table => attendance;

  /// Records a visit, enforcing one record per member per day.
  ///
  /// The unique index on `(member_id, attendance_date)` is the real guard; this
  /// method checks first so the caller gets a meaningful result instead of a
  /// constraint violation.
  ///
  /// A QR scan arriving after a self-reported entry for the same day *upgrades*
  /// that row rather than being rejected: the staff-verified source is the
  /// trusted one for reporting, so it must win.
  Future<CheckInResult> recordCheckIn({
    required String memberId,
    required AttendanceSource source,
    DateTime? at,
    String? recordedBy,
    String? notes,
  }) async {
    final instant = at ?? DateTime.now();
    final day = DayKey.of(instant);

    return transaction(() async {
      final existing = await _findForDay(memberId, day);

      if (existing != null) {
        final isUpgrade =
            existing.source == AttendanceSource.selfReported.wireValue &&
            source == AttendanceSource.qrScan;

        if (!isUpgrade) return CheckInResult.duplicate;

        await (update(attendance)..where((t) => t.id.equals(existing.id)))
            .write(
              AttendanceCompanion(
                source: Value(source.wireValue),
                recordedBy: Value(recordedBy),
                checkInAt: Value(instant),
                updatedAt: Value(DateTime.now()),
                isDirty: const Value(true),
              ),
            );
        return CheckInResult.upgradedFromSelfReport;
      }

      await into(attendance).insert(
        AttendanceCompanion.insert(
          id: Uuid.v4(),
          memberId: memberId,
          attendanceDate: day,
          source: source.wireValue,
          checkInAt: Value(instant),
          recordedBy: Value(recordedBy),
          notes: Value(notes),
          updatedAt: Value(DateTime.now()),
          isDirty: const Value(true),
        ),
      );
      return CheckInResult.recorded;
    });
  }

  /// Records a self-reported visit with an explicit time range (brain.md §6.7).
  Future<CheckInResult> recordSelfReported({
    required String memberId,
    required DateTime startedAt,
    DateTime? endedAt,
  }) async {
    final day = DayKey.of(startedAt);

    return transaction(() async {
      final existing = await _findForDay(memberId, day);
      if (existing != null) return CheckInResult.duplicate;

      await into(attendance).insert(
        AttendanceCompanion.insert(
          id: Uuid.v4(),
          memberId: memberId,
          attendanceDate: day,
          source: AttendanceSource.selfReported.wireValue,
          checkInAt: Value(startedAt),
          checkOutAt: Value(endedAt),
          updatedAt: Value(DateTime.now()),
          isDirty: const Value(true),
        ),
      );
      return CheckInResult.recorded;
    });
  }

  Future<AttendanceData?> _findForDay(String memberId, DateTime day) {
    return (select(attendance)
          ..where(
            (t) =>
                t.memberId.equals(memberId) &
                t.attendanceDate.equals(day) &
                t.isDeleted.equals(false),
          )
          ..limit(1))
        .getSingleOrNull();
  }

  /// Whether the member already has a record for the given day.
  Future<bool> hasCheckedIn(String memberId, [DateTime? day]) async =>
      await _findForDay(memberId, DayKey.of(day)) != null;

  /// Count of distinct members present on a day — the admin home figure
  /// (brain.md §6.4), computed from the local cache.
  ///
  /// [verifiedOnly] excludes self-reported entries. It defaults to true because
  /// QR scans are the trusted record for admin reporting; whether self-reports
  /// should count is an open owner decision (brain.md §6.7).
  Future<int> countForDay({DateTime? day, bool verifiedOnly = true}) async {
    final target = DayKey.of(day);
    final count = attendance.id.count();

    final query = selectOnly(attendance)
      ..addColumns([count])
      ..where(
        attendance.attendanceDate.equals(target) &
            attendance.isDeleted.equals(false) &
            (verifiedOnly
                ? attendance.source.equals(AttendanceSource.qrScan.wireValue)
                : const Constant(true)),
      );

    final row = await query.getSingle();
    return row.read(count) ?? 0;
  }

  /// A member's visit history, most recent first.
  Future<List<AttendanceData>> historyFor(
    String memberId, {
    int limit = 100,
  }) {
    return (select(attendance)
          ..where(
            (t) => t.memberId.equals(memberId) & t.isDeleted.equals(false),
          )
          ..orderBy([
            (t) => OrderingTerm.desc(t.attendanceDate),
          ])
          ..limit(limit))
        .get();
  }

  /// Live-updating stream of a member's history, for the UI.
  Stream<List<AttendanceData>> watchHistoryFor(String memberId) {
    return (select(attendance)
          ..where(
            (t) => t.memberId.equals(memberId) & t.isDeleted.equals(false),
          )
          ..orderBy([(t) => OrderingTerm.desc(t.attendanceDate)]))
        .watch();
  }

  /// Records within a date range, for reporting (brain.md §6.3).
  Future<List<AttendanceData>> inRange({
    required DateTime from,
    required DateTime to,
    bool verifiedOnly = false,
  }) {
    return (select(attendance)
          ..where(
            (t) =>
                t.attendanceDate.isBetweenValues(DayKey.of(from), DayKey.of(to)) &
                t.isDeleted.equals(false) &
                (verifiedOnly
                    ? t.source.equals(AttendanceSource.qrScan.wireValue)
                    : const Constant(true)),
          )
          ..orderBy([(t) => OrderingTerm.desc(t.attendanceDate)]))
        .get();
  }
}
