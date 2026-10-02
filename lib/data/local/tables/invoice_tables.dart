import 'package:drift/drift.dart';

import 'profile_tables.dart';
import 'sync_columns.dart';

/// A charge against a member — a plan renewal, or an ad-hoc fee (brain.md
/// §6.5). No payment gateway in v1: this is a ledger for money owed, settled
/// by one or more manually recorded [Payments] rows.
///
/// [amountPaidMinor] and [status] are denormalized (recomputed by
/// `InvoiceDao.applyPayment` in the same local transaction as the payment
/// insert) rather than derived live by summing [Payments], because the dues
/// list reads this on every render and the sync engine cannot join across
/// tables atomically. See brain.md §6.5 for the accepted concurrency
/// tradeoff this implies.
class Invoices extends Table with SyncColumns {
  @ReferenceName('invoicesAsMember')
  TextColumn get memberId => text().references(Profiles, #id)();

  /// The membership this invoice charges for. Null for an ad-hoc charge not
  /// tied to a plan (registration fee, PT add-on, manual late fee).
  TextColumn get membershipId =>
      text().nullable().references(Memberships, #id)();

  /// `plan_charge` | `ad_hoc` — see `InvoiceKind`.
  TextColumn get kind => text()();

  TextColumn get description => text().nullable()();

  /// Paise, before discount.
  IntColumn get subtotalMinor => integer()();

  /// `flat` | `percent`, null when no discount is applied.
  TextColumn get discountKind => text().nullable()();

  /// The raw number staff entered: paise if [discountKind] is `flat`, a whole
  /// 0-100 percentage if `percent`. Kept alongside the resolved
  /// [discountMinor] so editing the discount can re-show what was typed
  /// instead of back-solving a percentage from an amount.
  IntColumn get discountValue => integer().nullable()();

  /// Resolved discount in paise, always present (0 when none).
  IntColumn get discountMinor =>
      integer().withDefault(const Constant(0))();

  /// subtotalMinor - discountMinor, clamped to >= 0.
  IntColumn get totalMinor => integer()();

  /// Sum of `paid`-status payments applied against this invoice.
  IntColumn get amountPaidMinor =>
      integer().withDefault(const Constant(0))();

  /// `unpaid` | `partial` | `paid` | `void`.
  TextColumn get status =>
      text().withDefault(const Constant('unpaid'))();

  DateTimeColumn get dueDate => dateTime().nullable()();

  @ReferenceName('invoicesAsCreator')
  TextColumn get createdBy => text().nullable().references(Profiles, #id)();

  TextColumn get notes => text().nullable()();
}
