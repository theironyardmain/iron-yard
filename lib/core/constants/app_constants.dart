/// App-wide constants.
class AppConstants {
  const AppConstants._();

  static const String appName = 'The Iron Yard';

  /// Local database file name (Drift / SQLite).
  static const String dbName = 'iron_yard.sqlite';
}

/// User roles. Mirrors the `role` column on `profiles` and the RLS policies
/// described in brain.md §2.
enum UserRole {
  admin,
  trainer,
  member;

  static UserRole? fromString(String? value) => switch (value) {
    'admin' => UserRole.admin,
    'trainer' => UserRole.trainer,
    'member' => UserRole.member,
    _ => null,
  };

  String get wireValue => name;
}

/// How an attendance record was captured (brain.md §6.7).
///
/// [qrScan] is the staff-verified, primary record used for admin reporting.
/// [selfReported] comes from the member's daily check-in and is treated as a
/// secondary/unverified source.
enum AttendanceSource {
  qrScan,
  selfReported;

  static AttendanceSource? fromString(String? value) => switch (value) {
    'qr_scan' => AttendanceSource.qrScan,
    'self_reported' => AttendanceSource.selfReported,
    _ => null,
  };

  String get wireValue => switch (this) {
    AttendanceSource.qrScan => 'qr_scan',
    AttendanceSource.selfReported => 'self_reported',
  };
}

/// Payment methods (brain.md §6.5, pitch.md).
///
/// No online gateway in v1 — every method here is recorded manually by staff.
enum PaymentMethod {
  cash,
  bankTransfer,
  upi,
  external;

  static PaymentMethod? fromString(String? value) => switch (value) {
    'cash' => PaymentMethod.cash,
    'bank_transfer' => PaymentMethod.bankTransfer,
    'upi' => PaymentMethod.upi,
    'external' => PaymentMethod.external,
    _ => null,
  };

  String get wireValue => switch (this) {
    PaymentMethod.cash => 'cash',
    PaymentMethod.bankTransfer => 'bank_transfer',
    PaymentMethod.upi => 'upi',
    PaymentMethod.external => 'external',
  };

  String get label => switch (this) {
    PaymentMethod.cash => 'Cash',
    PaymentMethod.bankTransfer => 'Bank Transfer',
    PaymentMethod.upi => 'UPI',
    PaymentMethod.external => 'Other',
  };
}

/// What generated an invoice (brain.md §6.5).
///
/// [planCharge] is created automatically when a plan is assigned or renewed;
/// [adHoc] covers everything staff create by hand — registration fees, PT
/// add-ons, and manual late fees all use this rather than a dedicated kind.
enum InvoiceKind {
  planCharge,
  adHoc;

  static InvoiceKind? fromString(String? value) => switch (value) {
    'plan_charge' => InvoiceKind.planCharge,
    'ad_hoc' => InvoiceKind.adHoc,
    _ => null,
  };

  String get wireValue => switch (this) {
    InvoiceKind.planCharge => 'plan_charge',
    InvoiceKind.adHoc => 'ad_hoc',
  };
}

/// An invoice's settlement state, derived from `amountPaidMinor` vs.
/// `totalMinor` (brain.md §6.5).
enum InvoiceStatus {
  unpaid,
  partial,
  paid,
  void_;

  static InvoiceStatus? fromString(String? value) => switch (value) {
    'unpaid' => InvoiceStatus.unpaid,
    'partial' => InvoiceStatus.partial,
    'paid' => InvoiceStatus.paid,
    'void' => InvoiceStatus.void_,
    _ => null,
  };

  String get wireValue => switch (this) {
    InvoiceStatus.unpaid => 'unpaid',
    InvoiceStatus.partial => 'partial',
    InvoiceStatus.paid => 'paid',
    InvoiceStatus.void_ => 'void',
  };

  String get label => switch (this) {
    InvoiceStatus.unpaid => 'Unpaid',
    InvoiceStatus.partial => 'Partially paid',
    InvoiceStatus.paid => 'Paid',
    InvoiceStatus.void_ => 'Void',
  };
}

/// How a discount amount was entered, so an edit can re-show the original
/// input instead of back-solving a percentage from a resolved amount.
enum DiscountKind {
  flat,
  percent;

  static DiscountKind? fromString(String? value) => switch (value) {
    'flat' => DiscountKind.flat,
    'percent' => DiscountKind.percent,
    _ => null,
  };

  String get wireValue => switch (this) {
    DiscountKind.flat => 'flat',
    DiscountKind.percent => 'percent',
  };
}
