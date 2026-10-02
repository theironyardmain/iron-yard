import 'package:drift/drift.dart';

import 'invoice_tables.dart';
import 'profile_tables.dart';
import 'sync_columns.dart';

/// Gym visits (brain.md §6.4, §6.7).
///
/// Two sources share this table:
///  - `qr_scan`      — staff-verified, the trusted record for admin reporting
///  - `self_reported`— the member's daily check-in, treated as unverified
///
/// [attendanceDate] is stored separately from [checkInAt] as a date-only value
/// so the "one visit per member per day" rule is a plain uniqueness check that
/// cannot be defeated by two timestamps landing on either side of midnight.
class Attendance extends Table with SyncColumns {
  @ReferenceName('attendanceAsMember')
  TextColumn get memberId => text().references(Profiles, #id)();

  /// Date-only (local midnight). Paired with [memberId] in a unique index.
  DateTimeColumn get attendanceDate => dateTime()();

  DateTimeColumn get checkInAt => dateTime().nullable()();
  DateTimeColumn get checkOutAt => dateTime().nullable()();

  /// `qr_scan` | `self_reported` — see `AttendanceSource`.
  TextColumn get source => text()();

  /// Profile id of the staff member who performed the scan. Null for
  /// self-reported entries.
  @ReferenceName('attendanceAsRecorder')
  TextColumn get recordedBy => text().nullable().references(Profiles, #id)();

  TextColumn get notes => text().nullable()();
}

/// Manually recorded payments (brain.md §6.5). No gateway in v1.
class Payments extends Table with SyncColumns {
  @ReferenceName('paymentsAsMember')
  TextColumn get memberId => text().references(Profiles, #id)();

  /// The membership this payment settles, when it is a plan purchase or
  /// renewal. Null for ad-hoc payments. Kept alongside [invoiceId] (rather
  /// than replaced by it) so existing rows recorded before invoicing existed
  /// stay meaningful without a join.
  TextColumn get membershipId =>
      text().nullable().references(Memberships, #id)();

  /// The invoice this payment settles. Null for a payment recorded through
  /// the legacy free-floating flow (`PaymentDao.record` called directly,
  /// rather than `InvoiceDao.applyPayment`).
  @ReferenceName('paymentsAsInvoice')
  TextColumn get invoiceId =>
      text().nullable().references(Invoices, #id)();

  /// Paise, as an integer — see `MembershipPlans.priceMinor`.
  IntColumn get amountMinor => integer()();

  /// `cash` | `bank_transfer` | `upi` | `external` — see `PaymentMethod`.
  TextColumn get method => text()();

  /// `paid` | `pending`.
  TextColumn get status => text().withDefault(const Constant('paid'))();

  DateTimeColumn get paidAt => dateTime()();

  /// Remote URL of the receipt once uploaded to Supabase Storage.
  TextColumn get receiptUrl => text().nullable()();

  /// On-device path of a receipt photo captured offline and still awaiting
  /// upload. Cleared once [receiptUrl] is populated.
  TextColumn get receiptLocalPath => text().nullable()();

  TextColumn get notes => text().nullable()();
  @ReferenceName('paymentsAsRecorder')
  TextColumn get recordedBy => text().nullable().references(Profiles, #id)();
}
