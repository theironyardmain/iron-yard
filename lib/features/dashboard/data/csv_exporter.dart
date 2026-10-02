import 'package:csv/csv.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/utils/money.dart';
import '../../../data/local/daos/membership_dao.dart';
import '../../../data/local/database.dart';

/// What can be exported (brain.md §6.3).
enum ExportKind {
  members,
  payments,
  attendance;

  String get label => switch (this) {
    ExportKind.members => 'Members',
    ExportKind.payments => 'Payments',
    ExportKind.attendance => 'Attendance',
  };

  String get fileName => switch (this) {
    ExportKind.members => 'members',
    ExportKind.payments => 'payments',
    ExportKind.attendance => 'attendance',
  };
}

/// Builds CSV exports from the local cache (brain.md §6.3).
///
/// Amounts are written as plain decimal rupees, not the paise integers used
/// internally: the file is for the owner's accountant, not for re-import.
class CsvExporter {
  CsvExporter(this._db);

  final AppDatabase _db;

  static final DateFormat _date = DateFormat('yyyy-MM-dd');
  static final DateFormat _dateTime = DateFormat('yyyy-MM-dd HH:mm');

  /// Generates CSV text for [kind].
  Future<String> build(ExportKind kind, {DateTime? from, DateTime? to}) async {
    final rows = switch (kind) {
      ExportKind.members => await _members(),
      ExportKind.payments => await _payments(from: from, to: to),
      ExportKind.attendance => await _attendance(from: from, to: to),
    };

    // CRLF and a UTF-8 BOM, because Excel is where a gym owner will actually
    // open this. Without the BOM, member names with non-ASCII characters
    // render as mojibake.
    return Csv(addBom: true).encode(rows);
  }

  /// A dated file name, e.g. `members_2026-09-21.csv`.
  String fileNameFor(ExportKind kind, {DateTime? asOf}) =>
      '${kind.fileName}_${_date.format(asOf ?? DateTime.now())}.csv';

  Future<List<List<Object?>>> _members() async {
    final members = await _db.profileDao.members(activeOnly: false);

    final rows = <List<Object?>>[
      [
        'Name',
        'Phone',
        'Email',
        'Status',
        'Plan expires',
        'Date of birth',
        'Joined',
        'Active',
      ],
    ];

    for (final member in members) {
      final membership = await _db.membershipDao.currentFor(member.id);
      final status = MembershipDao.statusOf(membership);

      rows.add([
        member.fullName,
        member.phone ?? '',
        member.email ?? '',
        _statusLabel(status),
        membership == null ? '' : _date.format(membership.endDate),
        member.dateOfBirth == null ? '' : _date.format(member.dateOfBirth!),
        member.joinedAt == null ? '' : _date.format(member.joinedAt!),
        member.isActive ? 'Yes' : 'No',
      ]);
    }

    return rows;
  }

  Future<List<List<Object?>>> _payments({
    DateTime? from,
    DateTime? to,
  }) async {
    final payments = from == null || to == null
        ? await _db.paymentDao.watchAll().first
        : await _db.paymentDao.inRange(from: from, to: to);

    final rows = <List<Object?>>[
      ['Date', 'Member', 'Amount', 'Method', 'Status', 'Notes'],
    ];

    for (final payment in payments) {
      final member = await _db.profileDao.byId(payment.memberId);
      final method = PaymentMethod.fromString(payment.method);

      rows.add([
        _date.format(payment.paidAt),
        member?.fullName ?? 'Unknown',
        // Plain decimal rupees for a spreadsheet, not paise.
        (payment.amountMinor / Money.minorPerMajor).toStringAsFixed(2),
        method?.label ?? payment.method,
        payment.status,
        payment.notes ?? '',
      ]);
    }

    return rows;
  }

  Future<List<List<Object?>>> _attendance({
    DateTime? from,
    DateTime? to,
  }) async {
    final now = DateTime.now();
    final start = from ?? DateTime(now.year, now.month - 1, now.day);
    final end = to ?? now;

    final records = await _db.attendanceDao.inRange(from: start, to: end);

    final rows = <List<Object?>>[
      ['Date', 'Member', 'Check in', 'Check out', 'Source'],
    ];

    for (final record in records) {
      final member = await _db.profileDao.byId(record.memberId);
      final source = AttendanceSource.fromString(record.source);

      rows.add([
        _date.format(record.attendanceDate),
        member?.fullName ?? 'Unknown',
        record.checkInAt == null ? '' : _dateTime.format(record.checkInAt!),
        record.checkOutAt == null ? '' : _dateTime.format(record.checkOutAt!),
        // Spelled out rather than the wire value: the file is read by a person.
        switch (source) {
          AttendanceSource.qrScan => 'Staff scan',
          AttendanceSource.selfReported => 'Self-reported',
          null => record.source,
        },
      ]);
    }

    return rows;
  }

  static String _statusLabel(MembershipStatus status) => switch (status) {
    MembershipStatus.active => 'Active',
    MembershipStatus.expiringSoon => 'Expiring soon',
    MembershipStatus.expired => 'Expired',
    MembershipStatus.cancelled => 'Cancelled',
    MembershipStatus.none => 'No plan',
  };
}
