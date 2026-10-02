import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:iron_yard/core/constants/app_constants.dart';
import 'package:iron_yard/data/local/daos/invoice_dao.dart';
import 'package:iron_yard/data/local/database.dart';

void main() {
  late AppDatabase db;
  late InvoiceDao dao;
  late String memberId;

  setUp(() async {
    db = AppDatabase.memory();
    dao = db.invoiceDao;
    memberId = await db.profileDao.createMember(fullName: 'Payer');
  });

  tearDown(() async => db.close());

  group('creation', () {
    test('createChargeForMembership creates an unpaid invoice for the full amount',
        () async {
      final membershipId = await _membership(db, memberId);

      final invoiceId = await dao.createChargeForMembership(
        memberId: memberId,
        membershipId: membershipId,
        amountMinor: 150000,
        description: 'Monthly membership',
      );

      final invoice = await dao.byId(invoiceId);
      expect(invoice!.kind, 'plan_charge');
      expect(invoice.subtotalMinor, 150000);
      expect(invoice.totalMinor, 150000);
      expect(invoice.amountPaidMinor, 0);
      expect(invoice.status, 'unpaid');
      expect(invoice.isDirty, isTrue, reason: 'must sync');
    });

    test('createAdHocCharge is not tied to a membership', () async {
      final invoiceId = await dao.createAdHocCharge(
        memberId: memberId,
        description: 'Registration fee',
        amountMinor: 50000,
      );

      final invoice = await dao.byId(invoiceId);
      expect(invoice!.kind, 'ad_hoc');
      expect(invoice.membershipId, isNull);
      expect(invoice.totalMinor, 50000);
    });
  });

  group('discount', () {
    test('a flat discount reduces the total', () async {
      final invoiceId = await dao.createAdHocCharge(
        memberId: memberId,
        description: 'PT sessions',
        amountMinor: 100000,
      );

      await dao.applyDiscount(
        invoiceId: invoiceId,
        discountKind: DiscountKind.flat,
        discountValue: 20000,
      );

      final invoice = await dao.byId(invoiceId);
      expect(invoice!.discountMinor, 20000);
      expect(invoice.totalMinor, 80000);
      expect(invoice.status, 'unpaid');
    });

    test('a percent discount is resolved against the subtotal', () async {
      final invoiceId = await dao.createAdHocCharge(
        memberId: memberId,
        description: 'PT sessions',
        amountMinor: 100000,
      );

      await dao.applyDiscount(
        invoiceId: invoiceId,
        discountKind: DiscountKind.percent,
        discountValue: 25,
      );

      final invoice = await dao.byId(invoiceId);
      expect(invoice!.discountMinor, 25000);
      expect(invoice.totalMinor, 75000);
    });

    test('a discount is clamped so the total cannot go negative', () async {
      final invoiceId = await dao.createAdHocCharge(
        memberId: memberId,
        description: 'Small fee',
        amountMinor: 10000,
      );

      await dao.applyDiscount(
        invoiceId: invoiceId,
        discountKind: DiscountKind.flat,
        discountValue: 999999,
      );

      final invoice = await dao.byId(invoiceId);
      expect(invoice!.discountMinor, 10000);
      expect(invoice.totalMinor, 0);
    });

    test('recomputes status when a discount fully covers the balance',
        () async {
      final invoiceId = await dao.createAdHocCharge(
        memberId: memberId,
        description: 'Comped fee',
        amountMinor: 10000,
      );

      await dao.applyDiscount(
        invoiceId: invoiceId,
        discountKind: DiscountKind.flat,
        discountValue: 10000,
      );

      final invoice = await dao.byId(invoiceId);
      expect(invoice!.status, 'paid');
    });

    test('rejects a discount on a paid invoice', () async {
      final invoiceId = await dao.createAdHocCharge(
        memberId: memberId,
        description: 'Fee',
        amountMinor: 10000,
      );
      await dao.applyPayment(
        invoiceId: invoiceId,
        amountMinor: 10000,
        method: PaymentMethod.cash,
      );

      expect(
        () => dao.applyDiscount(
          invoiceId: invoiceId,
          discountKind: DiscountKind.flat,
          discountValue: 1000,
        ),
        throwsStateError,
      );
    });

    test('rejects a discount on a void invoice', () async {
      final invoiceId = await dao.createAdHocCharge(
        memberId: memberId,
        description: 'Fee',
        amountMinor: 10000,
      );
      await dao.voidInvoice(invoiceId);

      expect(
        () => dao.applyDiscount(
          invoiceId: invoiceId,
          discountKind: DiscountKind.flat,
          discountValue: 1000,
        ),
        throwsStateError,
      );
    });
  });

  group('applyPayment', () {
    test('a full payment settles the invoice', () async {
      final invoiceId = await dao.createAdHocCharge(
        memberId: memberId,
        description: 'Fee',
        amountMinor: 100000,
      );

      final paymentId = await dao.applyPayment(
        invoiceId: invoiceId,
        amountMinor: 100000,
        method: PaymentMethod.cash,
      );

      final invoice = await dao.byId(invoiceId);
      expect(invoice!.amountPaidMinor, 100000);
      expect(invoice.status, 'paid');

      final payment = await db.paymentDao.byId(paymentId);
      expect(payment!.invoiceId, invoiceId);
      expect(payment.memberId, memberId);
    });

    test('partial payments accumulate toward the total', () async {
      final invoiceId = await dao.createAdHocCharge(
        memberId: memberId,
        description: 'Fee',
        amountMinor: 100000,
      );

      await dao.applyPayment(
        invoiceId: invoiceId,
        amountMinor: 40000,
        method: PaymentMethod.cash,
      );
      var invoice = await dao.byId(invoiceId);
      expect(invoice!.amountPaidMinor, 40000);
      expect(invoice.status, 'partial');

      await dao.applyPayment(
        invoiceId: invoiceId,
        amountMinor: 60000,
        method: PaymentMethod.upi,
      );
      invoice = await dao.byId(invoiceId);
      expect(invoice!.amountPaidMinor, 100000);
      expect(invoice.status, 'paid');
    });

    test('rejects a paid amount exceeding the remaining balance', () async {
      final invoiceId = await dao.createAdHocCharge(
        memberId: memberId,
        description: 'Fee',
        amountMinor: 50000,
      );

      expect(
        () => dao.applyPayment(
          invoiceId: invoiceId,
          amountMinor: 60000,
          method: PaymentMethod.cash,
        ),
        throwsStateError,
      );
    });

    test('a pending payment is recorded but does not move the balance',
        () async {
      final invoiceId = await dao.createAdHocCharge(
        memberId: memberId,
        description: 'Fee',
        amountMinor: 50000,
      );

      await dao.applyPayment(
        invoiceId: invoiceId,
        amountMinor: 50000,
        method: PaymentMethod.cash,
        pending: true,
      );

      final invoice = await dao.byId(invoiceId);
      expect(invoice!.amountPaidMinor, 0);
      expect(invoice.status, 'unpaid');
    });

    test('a pending payment may exceed the remaining balance', () async {
      // Not yet received, so it cannot overdraw a balance that hasn't moved.
      final invoiceId = await dao.createAdHocCharge(
        memberId: memberId,
        description: 'Fee',
        amountMinor: 50000,
      );

      await dao.applyPayment(
        invoiceId: invoiceId,
        amountMinor: 999999,
        method: PaymentMethod.cash,
        pending: true,
      );

      expect((await dao.byId(invoiceId))!.amountPaidMinor, 0);
    });

    test('rejects a payment against a void invoice', () async {
      final invoiceId = await dao.createAdHocCharge(
        memberId: memberId,
        description: 'Fee',
        amountMinor: 50000,
      );
      await dao.voidInvoice(invoiceId);

      expect(
        () => dao.applyPayment(
          invoiceId: invoiceId,
          amountMinor: 50000,
          method: PaymentMethod.cash,
        ),
        throwsStateError,
      );
    });
  });

  group('markPaymentPaid', () {
    test('promotes a pending payment and applies it to the invoice',
        () async {
      final invoiceId = await dao.createAdHocCharge(
        memberId: memberId,
        description: 'Fee',
        amountMinor: 50000,
      );
      final paymentId = await dao.applyPayment(
        invoiceId: invoiceId,
        amountMinor: 50000,
        method: PaymentMethod.cash,
        pending: true,
      );

      await dao.markPaymentPaid(paymentId);

      expect((await db.paymentDao.byId(paymentId))!.status, 'paid');
      final invoice = await dao.byId(invoiceId);
      expect(invoice!.amountPaidMinor, 50000);
      expect(invoice.status, 'paid');
    });
  });

  group('voidLinkedPayment', () {
    test('reverses a paid payment from the invoice balance', () async {
      final invoiceId = await dao.createAdHocCharge(
        memberId: memberId,
        description: 'Fee',
        amountMinor: 100000,
      );
      final paymentId = await dao.applyPayment(
        invoiceId: invoiceId,
        amountMinor: 40000,
        method: PaymentMethod.cash,
      );

      await dao.voidLinkedPayment(paymentId);

      final invoice = await dao.byId(invoiceId);
      expect(invoice!.amountPaidMinor, 0);
      expect(invoice.status, 'unpaid');

      final payment = await db.paymentDao.byId(paymentId);
      expect(payment!.isDeleted, isTrue);
      expect(payment.isDirty, isTrue, reason: 'the void must sync');
    });

    test('voiding a pending payment does not touch the balance', () async {
      final invoiceId = await dao.createAdHocCharge(
        memberId: memberId,
        description: 'Fee',
        amountMinor: 100000,
      );
      final paymentId = await dao.applyPayment(
        invoiceId: invoiceId,
        amountMinor: 40000,
        method: PaymentMethod.cash,
        pending: true,
      );

      await dao.voidLinkedPayment(paymentId);

      expect((await dao.byId(invoiceId))!.amountPaidMinor, 0);
    });
  });

  group('recomputeFromPayments', () {
    test('re-derives the balance from paid payments', () async {
      final invoiceId = await dao.createAdHocCharge(
        memberId: memberId,
        description: 'Fee',
        amountMinor: 100000,
      );
      await dao.applyPayment(
        invoiceId: invoiceId,
        amountMinor: 40000,
        method: PaymentMethod.cash,
      );

      // Simulate a stored total that has drifted from what the payments
      // actually add up to (the scenario this method exists to repair).
      await (db.update(db.invoices)
            ..where((t) => t.id.equals(invoiceId)))
          .write(
        const InvoicesCompanion(amountPaidMinor: Value(999)),
      );

      await dao.recomputeFromPayments(invoiceId);

      final invoice = await dao.byId(invoiceId);
      expect(invoice!.amountPaidMinor, 40000);
      expect(invoice.status, 'partial');
    });
  });

  group('balance queries', () {
    test('balanceFor sums remaining amounts across open invoices', () async {
      final a = await dao.createAdHocCharge(
        memberId: memberId,
        description: 'Fee A',
        amountMinor: 50000,
      );
      await dao.createAdHocCharge(
        memberId: memberId,
        description: 'Fee B',
        amountMinor: 30000,
      );
      await dao.applyPayment(
        invoiceId: a,
        amountMinor: 20000,
        method: PaymentMethod.cash,
      );

      // Remaining: (50000-20000) + 30000 = 60000.
      expect(await dao.balanceFor(memberId), 60000);
    });

    test('balanceFor excludes paid and void invoices', () async {
      final paid = await dao.createAdHocCharge(
        memberId: memberId,
        description: 'Paid',
        amountMinor: 10000,
      );
      await dao.applyPayment(
        invoiceId: paid,
        amountMinor: 10000,
        method: PaymentMethod.cash,
      );

      final voided = await dao.createAdHocCharge(
        memberId: memberId,
        description: 'Voided',
        amountMinor: 10000,
      );
      await dao.voidInvoice(voided);

      expect(await dao.balanceFor(memberId), 0);
    });

    test('balanceFor is zero for a member with no invoices', () async {
      expect(await dao.balanceFor(memberId), 0);
    });

    test('totalOutstanding sums across members', () async {
      final other = await db.profileDao.createMember(fullName: 'Other');
      await dao.createAdHocCharge(
        memberId: memberId,
        description: 'Fee',
        amountMinor: 10000,
      );
      await dao.createAdHocCharge(
        memberId: other,
        description: 'Fee',
        amountMinor: 20000,
      );

      expect(await dao.totalOutstanding(), 30000);
    });

    test('outstandingInvoices excludes paid and void', () async {
      final open = await dao.createAdHocCharge(
        memberId: memberId,
        description: 'Open',
        amountMinor: 10000,
      );
      final paid = await dao.createAdHocCharge(
        memberId: memberId,
        description: 'Paid',
        amountMinor: 10000,
      );
      await dao.applyPayment(
        invoiceId: paid,
        amountMinor: 10000,
        method: PaymentMethod.cash,
      );

      final list = await dao.outstandingInvoices(memberId: memberId);
      expect(list.map((i) => i.id), [open]);
    });

    test('overdue includes only invoices past their due date', () async {
      final past = DateTime.now().subtract(const Duration(days: 5));
      final future = DateTime.now().add(const Duration(days: 5));

      await dao.createAdHocCharge(
        memberId: memberId,
        description: 'Overdue',
        amountMinor: 10000,
        dueDate: past,
      );
      await dao.createAdHocCharge(
        memberId: memberId,
        description: 'Not due yet',
        amountMinor: 10000,
        dueDate: future,
      );

      final overdue = await dao.overdue();
      expect(overdue, hasLength(1));
      expect(overdue.single.description, 'Overdue');
    });

    test('historyFor returns invoices of every status', () async {
      final first = await dao.createAdHocCharge(
        memberId: memberId,
        description: 'First',
        amountMinor: 10000,
      );
      await dao.applyPayment(
        invoiceId: first,
        amountMinor: 10000,
        method: PaymentMethod.cash,
      );
      await dao.createAdHocCharge(
        memberId: memberId,
        description: 'Second',
        amountMinor: 10000,
      );

      final history = await dao.historyFor(memberId);
      expect(history, hasLength(2));
      expect(
        history.map((i) => i.description),
        containsAll(['First', 'Second']),
      );
      expect(
        history.firstWhere((i) => i.description == 'First').status,
        'paid',
      );
      expect(
        history.firstWhere((i) => i.description == 'Second').status,
        'unpaid',
      );
    });
  });

  group('voidInvoice', () {
    test('marks the invoice void and soft-deletes it', () async {
      final invoiceId = await dao.createAdHocCharge(
        memberId: memberId,
        description: 'Fee',
        amountMinor: 10000,
      );

      await dao.voidInvoice(invoiceId);

      final raw = await (db.select(
        db.invoices,
      )..where((t) => t.id.equals(invoiceId))).getSingle();
      expect(raw.status, 'void');
      expect(raw.isDeleted, isTrue);
      expect(raw.isDirty, isTrue, reason: 'the void must sync');
    });
  });
}

Future<String> _membership(AppDatabase db, String memberId) async {
  final planId = await db.membershipDao.createPlan(
    name: 'Monthly',
    durationDays: 30,
    priceMinor: 150000,
  );
  return db.membershipDao.assignPlan(memberId: memberId, planId: planId);
}
