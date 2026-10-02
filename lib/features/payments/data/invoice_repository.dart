import '../../../core/constants/app_constants.dart';
import '../../../data/local/database.dart';

/// Charges against a member and their outstanding balance (brain.md §6.5).
///
/// Sits over `InvoiceDao` the way `PaymentRepository` sits over `PaymentDao`.
/// Auto-invoicing on plan assign/renew lives in `MembershipRepository`; this
/// covers the rest — ad-hoc charges, discounts, and the dues/balance reads.
class InvoiceRepository {
  InvoiceRepository(this._db);

  final AppDatabase _db;

  /// Creates a charge not tied to a plan renewal — a registration fee, a PT
  /// add-on, or a manual late fee.
  Future<String> createAdHocCharge({
    required String memberId,
    required String description,
    required int amountMinor,
    String? membershipId,
    DateTime? dueDate,
    String? createdBy,
  }) => _db.invoiceDao.createAdHocCharge(
    memberId: memberId,
    description: description,
    amountMinor: amountMinor,
    membershipId: membershipId,
    dueDate: dueDate,
    createdBy: createdBy,
  );

  Future<void> applyDiscount({
    required String invoiceId,
    required DiscountKind discountKind,
    required int discountValue,
  }) => _db.invoiceDao.applyDiscount(
    invoiceId: invoiceId,
    discountKind: discountKind,
    discountValue: discountValue,
  );

  Future<void> voidInvoice(String id) => _db.invoiceDao.voidInvoice(id);

  Future<Invoice?> byId(String id) => _db.invoiceDao.byId(id);

  Future<int> balanceFor(String memberId) =>
      _db.invoiceDao.balanceFor(memberId);

  Future<int> totalOutstanding() => _db.invoiceDao.totalOutstanding();

  Future<List<Invoice>> outstandingInvoices({String? memberId}) =>
      _db.invoiceDao.outstandingInvoices(memberId: memberId);

  Stream<List<Invoice>> watchOutstanding({String? memberId}) =>
      _db.invoiceDao.watchOutstanding(memberId: memberId);

  Future<List<Invoice>> overdue({DateTime? asOf}) =>
      _db.invoiceDao.overdue(asOf: asOf);

  Future<List<Invoice>> historyFor(String memberId) =>
      _db.invoiceDao.historyFor(memberId);

  Stream<List<Invoice>> watchHistoryFor(String memberId) =>
      _db.invoiceDao.watchHistoryFor(memberId);

  Stream<List<Invoice>> watchAll() => _db.invoiceDao.watchAll();
}
