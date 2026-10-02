import 'package:drift/drift.dart';

import '../../../core/constants/app_constants.dart';
import '../database.dart';
import '../tables/attendance_tables.dart';
import '../tables/invoice_tables.dart';
import 'synced_dao.dart';

part 'invoice_dao.g.dart';

/// Charges and their settlement (brain.md §6.5).
///
/// An invoice tracks `totalMinor` vs. `amountPaidMinor`; one or more
/// [Payments] rows settle it, in full or in installments. `amountPaidMinor`
/// and `status` are denormalized and kept correct by [applyPayment] and
/// [voidLinkedPayment], which update both rows in a single local transaction
/// — see the class doc on [Invoices] for why this is stored rather than a
/// live sum, and the accepted concurrent-offline-payment limitation.
@DriftAccessor(tables: [Invoices, Payments])
class InvoiceDao extends DatabaseAccessor<AppDatabase>
    with _$InvoiceDaoMixin, SyncedDaoMixin<AppDatabase, $InvoicesTable, Invoice> {
  InvoiceDao(super.db);

  @override
  $InvoicesTable get table => invoices;

  // --- Creation ---

  /// Creates the invoice for a plan assignment/renewal. Called by
  /// `MembershipRepository`, not by `MembershipDao` directly — invoicing is
  /// cross-domain orchestration and stays out of the single-table DAOs.
  Future<String> createChargeForMembership({
    required String memberId,
    required String membershipId,
    required int amountMinor,
    String? description,
    DateTime? dueDate,
    String? createdBy,
  }) => _create(
    memberId: memberId,
    membershipId: membershipId,
    kind: InvoiceKind.planCharge,
    amountMinor: amountMinor,
    description: description,
    dueDate: dueDate,
    createdBy: createdBy,
  );

  /// Creates a charge not tied to a plan renewal — a registration fee, a PT
  /// add-on, or a manual late fee (there is no separate late-fee mechanism;
  /// staff record one as an ad-hoc charge, brain.md §6.5).
  Future<String> createAdHocCharge({
    required String memberId,
    required String description,
    required int amountMinor,
    String? membershipId,
    DateTime? dueDate,
    String? createdBy,
  }) => _create(
    memberId: memberId,
    membershipId: membershipId,
    kind: InvoiceKind.adHoc,
    amountMinor: amountMinor,
    description: description,
    dueDate: dueDate,
    createdBy: createdBy,
  );

  Future<String> _create({
    required String memberId,
    required String? membershipId,
    required InvoiceKind kind,
    required int amountMinor,
    String? description,
    DateTime? dueDate,
    String? createdBy,
  }) async {
    final id = Uuid.v4();
    await into(invoices).insert(
      InvoicesCompanion.insert(
        id: id,
        memberId: memberId,
        membershipId: Value(membershipId),
        kind: kind.wireValue,
        description: Value(description),
        subtotalMinor: amountMinor,
        totalMinor: amountMinor,
        dueDate: Value(dueDate),
        createdBy: Value(createdBy),
        updatedAt: Value(DateTime.now()),
        isDirty: const Value(true),
      ),
    );
    return id;
  }

  // --- Discount ---

  /// Applies or replaces a discount on an invoice, recomputing
  /// [Invoices.totalMinor] and [Invoices.status].
  ///
  /// Rejects invoices that are already `paid` or `void`: a settled invoice's
  /// total must not move under the payments already recorded against it.
  Future<void> applyDiscount({
    required String invoiceId,
    required DiscountKind discountKind,
    required int discountValue,
  }) async {
    final invoice = await byId(invoiceId);
    if (invoice == null) throw StateError('Invoice not found: $invoiceId');
    if (invoice.status == 'paid' || invoice.status == 'void') {
      throw StateError(
        'Cannot change the discount on a ${invoice.status} invoice',
      );
    }

    final discountMinor = switch (discountKind) {
      DiscountKind.flat => discountValue,
      DiscountKind.percent =>
        (invoice.subtotalMinor * discountValue / 100).round(),
    }.clamp(0, invoice.subtotalMinor);

    final totalMinor = invoice.subtotalMinor - discountMinor;

    await (update(invoices)..where((t) => t.id.equals(invoiceId))).write(
      InvoicesCompanion(
        discountKind: Value(discountKind.wireValue),
        discountValue: Value(discountValue),
        discountMinor: Value(discountMinor),
        totalMinor: Value(totalMinor),
        status: Value(_statusFor(invoice.amountPaidMinor, totalMinor)),
        updatedAt: Value(DateTime.now()),
        isDirty: const Value(true),
      ),
    );
  }

  // --- Payment application ---

  /// Records a payment against an invoice and, unless [pending], applies it
  /// to the invoice's running balance — both writes happen in one local
  /// transaction so the two rows never disagree on this device.
  ///
  /// Rejects a `paid` amount that would exceed the remaining balance: an
  /// invoice must not go negative outstanding.
  Future<String> applyPayment({
    required String invoiceId,
    required int amountMinor,
    required PaymentMethod method,
    DateTime? paidAt,
    String? notes,
    String? recordedBy,
    String? receiptLocalPath,
    bool pending = false,
  }) async {
    return db.transaction(() async {
      final invoice = await byId(invoiceId);
      if (invoice == null) throw StateError('Invoice not found: $invoiceId');
      if (invoice.status == 'void') {
        throw StateError('Cannot pay a void invoice');
      }

      final remaining = invoice.totalMinor - invoice.amountPaidMinor;
      if (!pending && amountMinor > remaining) {
        throw StateError(
          'Amount exceeds the remaining balance of $remaining',
        );
      }

      final paymentId = Uuid.v4();
      await into(payments).insert(
        PaymentsCompanion.insert(
          id: paymentId,
          memberId: invoice.memberId,
          amountMinor: amountMinor,
          method: method.wireValue,
          membershipId: Value(invoice.membershipId),
          invoiceId: Value(invoiceId),
          paidAt: paidAt ?? DateTime.now(),
          status: Value(pending ? 'pending' : 'paid'),
          notes: Value(notes),
          recordedBy: Value(recordedBy),
          receiptLocalPath: Value(receiptLocalPath),
          updatedAt: Value(DateTime.now()),
          isDirty: const Value(true),
        ),
      );

      if (!pending) {
        await _applyToBalance(invoiceId, amountMinor);
      }

      return paymentId;
    });
  }

  /// Promotes a pending payment to paid and applies it to its invoice's
  /// balance, in one transaction. Payments with no linked invoice stay on
  /// the plain `PaymentDao.markPaid` path.
  Future<void> markPaymentPaid(String paymentId) async {
    await db.transaction(() async {
      final payment = await (select(
        payments,
      )..where((t) => t.id.equals(paymentId))).getSingle();

      await (update(payments)..where((t) => t.id.equals(paymentId))).write(
        PaymentsCompanion(
          status: const Value('paid'),
          updatedAt: Value(DateTime.now()),
          isDirty: const Value(true),
        ),
      );

      final invoiceId = payment.invoiceId;
      if (invoiceId != null) {
        await _applyToBalance(invoiceId, payment.amountMinor);
      }
    });
  }

  /// Voids a payment and, if it was counted toward an invoice, reverses it
  /// from that invoice's balance — both in one transaction.
  Future<void> voidLinkedPayment(String paymentId) async {
    await db.transaction(() async {
      final payment = await (select(
        payments,
      )..where((t) => t.id.equals(paymentId))).getSingle();

      await (update(payments)..where((t) => t.id.equals(paymentId))).write(
        PaymentsCompanion(
          isDeleted: const Value(true),
          updatedAt: Value(DateTime.now()),
          isDirty: const Value(true),
        ),
      );

      final invoiceId = payment.invoiceId;
      if (invoiceId != null && payment.status == 'paid') {
        await _applyToBalance(invoiceId, -payment.amountMinor);
      }
    });
  }

  /// Adds [deltaMinor] (negative to reverse) to an invoice's paid total and
  /// recomputes its status. Clamped to [0, totalMinor] so a race or a voided
  /// overpayment cannot push the balance out of range.
  Future<void> _applyToBalance(String invoiceId, int deltaMinor) async {
    final invoice = await byId(invoiceId);
    if (invoice == null) return;

    final amountPaidMinor = (invoice.amountPaidMinor + deltaMinor).clamp(
      0,
      invoice.totalMinor,
    );

    await (update(invoices)..where((t) => t.id.equals(invoiceId))).write(
      InvoicesCompanion(
        amountPaidMinor: Value(amountPaidMinor),
        status: Value(_statusFor(amountPaidMinor, invoice.totalMinor)),
        updatedAt: Value(DateTime.now()),
        isDirty: const Value(true),
      ),
    );
  }

  static String _statusFor(int amountPaidMinor, int totalMinor) {
    // A discount can bring the total to zero, which is fully settled even
    // though nothing was ever paid against it.
    if (amountPaidMinor >= totalMinor) return 'paid';
    if (amountPaidMinor <= 0) return 'unpaid';
    return 'partial';
  }

  // --- Reconciliation ---

  /// Re-derives `amountPaidMinor`/`status` from the linked `paid` payments,
  /// discarding whatever the stored total currently says.
  ///
  /// The stored balance is normally kept correct by [applyPayment] and
  /// [voidLinkedPayment], but two devices applying partial payments to the
  /// same invoice while both offline can leave it wrong after sync
  /// (last-write-wins on the invoice row, while both payment rows survive).
  /// Call this after a sync completes for any invoice touched by that sync.
  Future<void> recomputeFromPayments(String invoiceId) async {
    final invoice = await byId(invoiceId);
    if (invoice == null) return;

    final total = payments.amountMinor.sum();
    final query = selectOnly(payments)
      ..addColumns([total])
      ..where(
        payments.invoiceId.equals(invoiceId) &
            payments.status.equals('paid') &
            payments.isDeleted.equals(false),
      );
    final amountPaidMinor = ((await query.getSingle()).read(total) ?? 0)
        .clamp(0, invoice.totalMinor);

    await (update(invoices)..where((t) => t.id.equals(invoiceId))).write(
      InvoicesCompanion(
        amountPaidMinor: Value(amountPaidMinor),
        status: Value(_statusFor(amountPaidMinor, invoice.totalMinor)),
        updatedAt: Value(DateTime.now()),
        isDirty: const Value(true),
      ),
    );
  }

  // --- Void ---

  /// Voids an invoice. Does not touch any payments already recorded against
  /// it — those are voided separately if staff need to reverse them too.
  Future<void> voidInvoice(String id) async {
    await (update(invoices)..where((t) => t.id.equals(id))).write(
      InvoicesCompanion(
        status: const Value('void'),
        updatedAt: Value(DateTime.now()),
        isDirty: const Value(true),
      ),
    );
    await softDelete(id);
  }

  // --- Reads ---

  Future<Invoice?> byId(String id) {
    return (select(invoices)..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  /// A member's outstanding balance in paise (0 if fully settled or no
  /// invoices).
  Future<int> balanceFor(String memberId) async {
    final remaining = invoices.totalMinor - invoices.amountPaidMinor;
    final total = remaining.sum();

    final query = selectOnly(invoices)
      ..addColumns([total])
      ..where(
        invoices.memberId.equals(memberId) &
            invoices.isDeleted.equals(false) &
            invoices.status.isIn(['unpaid', 'partial']),
      );

    final row = await query.getSingle();
    return row.read(total) ?? 0;
  }

  /// System-wide outstanding balance, for a dashboard tile.
  Future<int> totalOutstanding() async {
    final remaining = invoices.totalMinor - invoices.amountPaidMinor;
    final total = remaining.sum();

    final query = selectOnly(invoices)
      ..addColumns([total])
      ..where(
        invoices.isDeleted.equals(false) &
            invoices.status.isIn(['unpaid', 'partial']),
      );

    final row = await query.getSingle();
    return row.read(total) ?? 0;
  }

  /// Open invoices (unpaid or partially paid), most overdue first — the
  /// dues/outstanding-balances screen. Scoped to one member when given.
  Future<List<Invoice>> outstandingInvoices({String? memberId}) {
    final query = select(invoices)
      ..where(
        (t) =>
            t.isDeleted.equals(false) &
            t.status.isIn(['unpaid', 'partial']) &
            (memberId == null
                ? const Constant(true)
                : t.memberId.equals(memberId)),
      )
      ..orderBy([
        (t) => OrderingTerm(
          expression: t.dueDate,
          mode: OrderingMode.asc,
          nulls: NullsOrder.last,
        ),
      ]);
    return query.get();
  }

  Stream<List<Invoice>> watchOutstanding({String? memberId}) {
    final query = select(invoices)
      ..where(
        (t) =>
            t.isDeleted.equals(false) &
            t.status.isIn(['unpaid', 'partial']) &
            (memberId == null
                ? const Constant(true)
                : t.memberId.equals(memberId)),
      )
      ..orderBy([
        (t) => OrderingTerm(
          expression: t.dueDate,
          mode: OrderingMode.asc,
          nulls: NullsOrder.last,
        ),
      ]);
    return query.watch();
  }

  /// Outstanding invoices whose due date has passed.
  Future<List<Invoice>> overdue({DateTime? asOf}) async {
    final cutoff = asOf ?? DateTime.now();
    return (select(invoices)
          ..where(
            (t) =>
                t.isDeleted.equals(false) &
                t.status.isIn(['unpaid', 'partial']) &
                t.dueDate.isSmallerThanValue(cutoff),
          )
          ..orderBy([(t) => OrderingTerm.asc(t.dueDate)]))
        .get();
  }

  /// All invoices for a member, any status, newest first.
  Future<List<Invoice>> historyFor(String memberId) {
    return (select(invoices)
          ..where(
            (t) => t.memberId.equals(memberId) & t.isDeleted.equals(false),
          )
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .get();
  }

  Stream<List<Invoice>> watchHistoryFor(String memberId) {
    return (select(invoices)
          ..where(
            (t) => t.memberId.equals(memberId) & t.isDeleted.equals(false),
          )
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .watch();
  }

  Stream<List<Invoice>> watchAll({int limit = 200}) {
    return (select(invoices)
          ..where((t) => t.isDeleted.equals(false))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
          ..limit(limit))
        .watch();
  }
}
