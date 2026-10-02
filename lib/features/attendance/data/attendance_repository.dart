import '../../../core/constants/app_constants.dart';
import '../../../data/local/daos/attendance_dao.dart';
import '../../../data/local/daos/membership_dao.dart';
import '../../../data/local/database.dart';
import 'qr_payload.dart';
import 'scan_result.dart';

/// Records attendance from QR scans, local-first (brain.md §6.4).
///
/// Every decision is made against the local cache, so the scanner works with no
/// connection. The server re-checks the duplicate constraint on upload.
class AttendanceRepository {
  AttendanceRepository(this._db);

  final AppDatabase _db;

  /// Processes a scanned code end to end.
  ///
  /// [recordedBy] is the profile id of the staff member scanning.
  Future<ScanOutcome> handleScan(
    String? rawCode, {
    String? recordedBy,
    DateTime? at,
  }) async {
    final payload = QrPayload.tryParse(rawCode);
    if (payload == null) return const ScanNotACard();

    final profile = await _db.profileDao.byId(payload.memberId);
    if (profile == null || profile.isDeleted) {
      // The card is well-formed but this device has not synced the member yet.
      return ScanUnknownMember(scannedName: payload.fullName);
    }

    if (!profile.isActive) {
      return ScanDeactivated(name: profile.fullName);
    }

    final membership = await _db.membershipDao.currentFor(profile.id);
    final status = MembershipDao.statusOf(membership, asOf: at);

    final result = await _db.attendanceDao.recordCheckIn(
      memberId: profile.id,
      source: AttendanceSource.qrScan,
      at: at,
      recordedBy: recordedBy,
    );

    if (result == CheckInResult.duplicate) {
      final today = await _db.attendanceDao.historyFor(profile.id, limit: 1);
      return ScanAlreadyCheckedIn(
        name: profile.fullName,
        checkedInAt: today.isEmpty ? null : today.first.checkInAt,
      );
    }

    // An expired member is still recorded: they physically visited, and
    // discarding that leaves the gym with no trace of the entry. Staff are
    // shown the lapse so they can ask about renewal.
    if (status == MembershipStatus.expired ||
        status == MembershipStatus.none ||
        status == MembershipStatus.cancelled) {
      return ScanExpired(
        name: profile.fullName,
        expiredOn: membership?.endDate,
        wasRecorded: true,
      );
    }

    return ScanAccepted(
      name: profile.fullName,
      status: status,
      result: result,
      expiresOn: membership?.endDate,
    );
  }

  /// Today's verified attendance count for the admin home (brain.md §6.4).
  Future<int> todayCount({bool verifiedOnly = true}) =>
      _db.attendanceDao.countForDay(verifiedOnly: verifiedOnly);

  Stream<List<AttendanceData>> watchHistoryFor(String memberId) =>
      _db.attendanceDao.watchHistoryFor(memberId);

  Future<List<AttendanceData>> historyFor(String memberId, {int limit = 100}) =>
      _db.attendanceDao.historyFor(memberId, limit: limit);

  Future<List<AttendanceData>> inRange({
    required DateTime from,
    required DateTime to,
    bool verifiedOnly = false,
  }) => _db.attendanceDao.inRange(from: from, to: to, verifiedOnly: verifiedOnly);

  /// The QR payload for a member's card.
  Future<QrPayload?> cardFor(String memberId) async {
    final profile = await _db.profileDao.byId(memberId);
    if (profile == null || profile.isDeleted) return null;
    return QrPayload(memberId: profile.id, fullName: profile.fullName);
  }
}
