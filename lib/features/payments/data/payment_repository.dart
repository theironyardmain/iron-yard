import '../../../core/constants/app_constants.dart';
import '../../../data/local/database.dart';
import 'receipt_store.dart';

/// Records payments, local-first (brain.md §6.5).
///
/// No payment gateway in v1: everything here is a manual record of money that
/// changed hands elsewhere.
class PaymentRepository {
  PaymentRepository(this._db);

  final AppDatabase _db;

  /// Whether this platform can capture receipt photos.
  static bool get supportsReceipts => ReceiptStore.isSupported;

  /// Records a payment, optionally with a receipt photo.
  ///
  /// [receiptSourcePath] is a file the user just picked or captured. It is
  /// copied into the app's own storage first: the picker's temp file can be
  /// cleared by the OS at any time, which would lose the receipt before it
  /// ever uploads.
  Future<String> record({
    required String memberId,
    required int amountMinor,
    required PaymentMethod method,
    String? membershipId,
    DateTime? paidAt,
    String? notes,
    String? recordedBy,
    String? receiptSourcePath,
    bool pending = false,
  }) async {
    String? storedPath;
    if (receiptSourcePath != null && ReceiptStore.isSupported) {
      storedPath = await ReceiptStore.store(receiptSourcePath);
    }

    return _db.paymentDao.record(
      memberId: memberId,
      amountMinor: amountMinor,
      method: method,
      membershipId: membershipId,
      paidAt: paidAt,
      notes: notes,
      recordedBy: recordedBy,
      receiptLocalPath: storedPath,
      pending: pending,
    );
  }

  Stream<List<Payment>> watchAll() => _db.paymentDao.watchAll();

  Stream<List<Payment>> watchHistoryFor(String memberId) =>
      _db.paymentDao.watchHistoryFor(memberId);

  Future<List<Payment>> historyFor(String memberId) =>
      _db.paymentDao.historyFor(memberId);

  Future<List<Payment>> pendingPayments() => _db.paymentDao.pendingPayments();

  Future<List<Payment>> inRange({
    required DateTime from,
    required DateTime to,
  }) => _db.paymentDao.inRange(from: from, to: to);

  Future<int> revenueInRange({required DateTime from, required DateTime to}) =>
      _db.paymentDao.revenueInRange(from: from, to: to);

  /// Promotes a pending payment to paid. Routes through `InvoiceDao` when the
  /// payment is linked to an invoice, so the invoice's balance moves with it.
  Future<void> markPaid(String id) async {
    final payment = await _db.paymentDao.byId(id);
    if (payment?.invoiceId != null) {
      await _db.invoiceDao.markPaymentPaid(id);
    } else {
      await _db.paymentDao.markPaid(id);
    }
  }

  /// Voids a payment and removes its unsynced receipt from the device.
  ///
  /// Only a local file is deleted; an already-uploaded receipt stays in
  /// storage, because the payment row is soft-deleted rather than erased.
  /// Routes through `InvoiceDao` when the payment is linked to an invoice, so
  /// a voided payment's amount is returned to the invoice's outstanding
  /// balance.
  Future<void> voidPayment(String id) async {
    final payment = await _db.paymentDao.byId(id);
    final localPath = payment?.receiptLocalPath;

    if (payment?.invoiceId != null) {
      await _db.invoiceDao.voidLinkedPayment(id);
    } else {
      await _db.paymentDao.voidPayment(id);
    }

    if (localPath != null) {
      await ReceiptStore.delete(localPath);
    }
  }

  /// Records a payment against an invoice, optionally with a receipt photo.
  /// Supports a partial amount — the invoice tracks the remaining balance
  /// across as many payments as it takes to settle it.
  Future<String> applyPayment({
    required String invoiceId,
    required int amountMinor,
    required PaymentMethod method,
    DateTime? paidAt,
    String? notes,
    String? recordedBy,
    String? receiptSourcePath,
    bool pending = false,
  }) async {
    String? storedPath;
    if (receiptSourcePath != null && ReceiptStore.isSupported) {
      storedPath = await ReceiptStore.store(receiptSourcePath);
    }

    return _db.invoiceDao.applyPayment(
      invoiceId: invoiceId,
      amountMinor: amountMinor,
      method: method,
      paidAt: paidAt,
      notes: notes,
      recordedBy: recordedBy,
      receiptLocalPath: storedPath,
      pending: pending,
    );
  }

  /// Receipts captured offline that still need uploading (Phase 10).
  Future<List<Payment>> awaitingReceiptUpload() =>
      _db.paymentDao.awaitingReceiptUpload();

  /// Totals per payment method in a range, for the revenue report.
  Future<Map<PaymentMethod, int>> revenueByMethod({
    required DateTime from,
    required DateTime to,
  }) async {
    final payments = await inRange(from: from, to: to);
    final totals = <PaymentMethod, int>{};

    for (final payment in payments) {
      if (payment.status != 'paid') continue;
      final method = PaymentMethod.fromString(payment.method);
      if (method == null) continue;
      totals[method] = (totals[method] ?? 0) + payment.amountMinor;
    }

    return totals;
  }
}
