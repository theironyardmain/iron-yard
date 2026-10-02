import 'package:drift/drift.dart';

import '../../../core/constants/app_constants.dart';
import '../database.dart';
import '../tables/attendance_tables.dart';
import 'synced_dao.dart';

part 'payment_dao.g.dart';

@DriftAccessor(tables: [Payments])
class PaymentDao extends DatabaseAccessor<AppDatabase>
    with _$PaymentDaoMixin, SyncedDaoMixin<AppDatabase, $PaymentsTable, Payment> {
  PaymentDao(super.db);

  @override
  $PaymentsTable get table => payments;

  /// Records a payment. [amountMinor] is in paise (brain.md §6.5).
  Future<String> record({
    required String memberId,
    required int amountMinor,
    required PaymentMethod method,
    String? membershipId,
    DateTime? paidAt,
    String? notes,
    String? recordedBy,
    String? receiptLocalPath,
    bool pending = false,
  }) async {
    final id = Uuid.v4();
    await into(payments).insert(
      PaymentsCompanion.insert(
        id: id,
        memberId: memberId,
        amountMinor: amountMinor,
        method: method.wireValue,
        paidAt: paidAt ?? DateTime.now(),
        membershipId: Value(membershipId),
        status: Value(pending ? 'pending' : 'paid'),
        notes: Value(notes),
        recordedBy: Value(recordedBy),
        receiptLocalPath: Value(receiptLocalPath),
        updatedAt: Value(DateTime.now()),
        isDirty: const Value(true),
      ),
    );
    return id;
  }

  Future<List<Payment>> historyFor(String memberId) {
    return (select(payments)
          ..where((t) => t.memberId.equals(memberId) & t.isDeleted.equals(false))
          ..orderBy([(t) => OrderingTerm.desc(t.paidAt)]))
        .get();
  }

  Stream<List<Payment>> watchHistoryFor(String memberId) {
    return (select(payments)
          ..where((t) => t.memberId.equals(memberId) & t.isDeleted.equals(false))
          ..orderBy([(t) => OrderingTerm.desc(t.paidAt)]))
        .watch();
  }

  Future<List<Payment>> pendingPayments() {
    return (select(payments)
          ..where(
            (t) => t.status.equals('pending') & t.isDeleted.equals(false),
          )
          ..orderBy([(t) => OrderingTerm.desc(t.paidAt)]))
        .get();
  }

  /// Receipts captured offline that still need uploading to Storage.
  Future<List<Payment>> awaitingReceiptUpload() {
    return (select(payments)
          ..where(
            (t) =>
                t.receiptLocalPath.isNotNull() &
                t.receiptUrl.isNull() &
                t.isDeleted.equals(false),
          ))
        .get();
  }

  Future<void> attachReceiptUrl(String paymentId, String url) async {
    await (update(payments)..where((t) => t.id.equals(paymentId))).write(
      PaymentsCompanion(
        receiptUrl: Value(url),
        receiptLocalPath: const Value(null),
        updatedAt: Value(DateTime.now()),
        isDirty: const Value(true),
      ),
    );
  }

  Future<void> markPaid(String paymentId) async {
    await (update(payments)..where((t) => t.id.equals(paymentId))).write(
      PaymentsCompanion(
        status: const Value('paid'),
        updatedAt: Value(DateTime.now()),
        isDirty: const Value(true),
      ),
    );
  }

  Future<Payment?> byId(String id) {
    return (select(payments)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
  }

  /// All payments, newest first — the admin payments list.
  Stream<List<Payment>> watchAll({int limit = 200}) {
    return (select(payments)
          ..where((t) => t.isDeleted.equals(false))
          ..orderBy([(t) => OrderingTerm.desc(t.paidAt)])
          ..limit(limit))
        .watch();
  }

  /// Payments in a date range, newest first — for reports and CSV export.
  Future<List<Payment>> inRange({
    required DateTime from,
    required DateTime to,
  }) {
    return (select(payments)
          ..where(
            (t) => t.paidAt.isBetweenValues(from, to) &
                t.isDeleted.equals(false),
          )
          ..orderBy([(t) => OrderingTerm.desc(t.paidAt)]))
        .get();
  }

  /// Voids a payment.
  ///
  /// Soft-deletes rather than erasing: a recorded payment that turns out to be
  /// wrong is a correction with an audit trail, not something that should
  /// vanish from the books.
  Future<void> voidPayment(String id) => softDelete(id);

  /// Total revenue in a date range, in paise — the revenue report figure.
  ///
  /// Counts only `paid` rows; pending payments are not revenue.
  Future<int> revenueInRange({
    required DateTime from,
    required DateTime to,
  }) async {
    final total = payments.amountMinor.sum();

    final query = selectOnly(payments)
      ..addColumns([total])
      ..where(
        payments.paidAt.isBetweenValues(from, to) &
            payments.status.equals('paid') &
            payments.isDeleted.equals(false),
      );

    final row = await query.getSingle();
    return row.read(total) ?? 0;
  }
}
