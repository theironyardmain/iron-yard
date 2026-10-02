import 'package:flutter_test/flutter_test.dart';
import 'package:iron_yard/core/constants/app_constants.dart';
import 'package:iron_yard/data/local/database.dart';
import 'package:iron_yard/features/payments/data/invoice_repository.dart';
import 'package:iron_yard/features/payments/data/payment_repository.dart';
import 'package:iron_yard/features/payments/providers/payment_providers.dart';

void main() {
  late AppDatabase db;
  late PaymentRepository repository;
  late String memberId;

  setUp(() async {
    db = AppDatabase.memory();
    repository = PaymentRepository(db);
    memberId = await db.profileDao.createMember(fullName: 'Payer');
  });

  tearDown(() async => db.close());

  Future<String> pay(
    int amountMinor, {
    PaymentMethod method = PaymentMethod.cash,
    DateTime? paidAt,
    bool pending = false,
  }) => repository.record(
    memberId: memberId,
    amountMinor: amountMinor,
    method: method,
    paidAt: paidAt,
    pending: pending,
  );

  group('recording', () {
    test('stores amount, method and date', () async {
      final id = await pay(
        150000,
        method: PaymentMethod.upi,
        paidAt: DateTime(2026, 3, 10),
      );

      final payment = await db.paymentDao.byId(id);
      expect(payment!.amountMinor, 150000);
      expect(payment.method, PaymentMethod.upi.wireValue);
      expect(payment.paidAt, DateTime(2026, 3, 10));
      expect(payment.status, 'paid');
      expect(payment.isDirty, isTrue, reason: 'must sync');
    });

    test('a pending payment is recorded but not counted as paid', () async {
      final id = await pay(50000, pending: true);

      final payment = await db.paymentDao.byId(id);
      expect(payment!.status, 'pending');
      expect(await repository.pendingPayments(), hasLength(1));
    });

    test('markPaid promotes a pending payment', () async {
      final id = await pay(50000, pending: true);
      await repository.markPaid(id);

      expect((await db.paymentDao.byId(id))!.status, 'paid');
      expect(await repository.pendingPayments(), isEmpty);
    });

    test('attributes the payment to the recording staff member', () async {
      final staffId = await db.profileDao.createMember(
        fullName: 'Desk',
        role: UserRole.admin,
      );

      final id = await repository.record(
        memberId: memberId,
        amountMinor: 1000,
        method: PaymentMethod.cash,
        recordedBy: staffId,
      );

      expect((await db.paymentDao.byId(id))!.recordedBy, staffId);
    });

    test('links the payment to a membership when given one', () async {
      final planId = await db.membershipDao.createPlan(
        name: 'Monthly',
        durationDays: 30,
        priceMinor: 150000,
      );
      final membershipId = await db.membershipDao.assignPlan(
        memberId: memberId,
        planId: planId,
      );

      final id = await repository.record(
        memberId: memberId,
        amountMinor: 150000,
        method: PaymentMethod.cash,
        membershipId: membershipId,
      );

      expect((await db.paymentDao.byId(id))!.membershipId, membershipId);
    });
  });

  group('revenue', () {
    test('sums paid payments in the range', () async {
      await pay(150000, paidAt: DateTime(2026, 3, 5));
      await pay(50000, paidAt: DateTime(2026, 3, 20));

      final total = await repository.revenueInRange(
        from: DateTime(2026, 3, 1),
        to: DateTime(2026, 3, 31),
      );

      expect(total, 200000);
    });

    test('excludes pending payments', () async {
      // Pending is money not yet received; counting it would overstate income.
      await pay(150000, paidAt: DateTime(2026, 3, 5));
      await pay(999999, paidAt: DateTime(2026, 3, 6), pending: true);

      final total = await repository.revenueInRange(
        from: DateTime(2026, 3, 1),
        to: DateTime(2026, 3, 31),
      );

      expect(total, 150000);
    });

    test('excludes payments outside the range', () async {
      await pay(150000, paidAt: DateTime(2026, 2, 28));
      await pay(150000, paidAt: DateTime(2026, 4, 1));

      final total = await repository.revenueInRange(
        from: DateTime(2026, 3, 1),
        to: DateTime(2026, 3, 31),
      );

      expect(total, 0);
    });

    test('excludes voided payments', () async {
      final id = await pay(150000, paidAt: DateTime(2026, 3, 5));
      await repository.voidPayment(id);

      final total = await repository.revenueInRange(
        from: DateTime(2026, 3, 1),
        to: DateTime(2026, 3, 31),
      );

      expect(total, 0);
    });

    test('is zero, not null, when there are no payments', () async {
      expect(
        await repository.revenueInRange(
          from: DateTime(2026, 3, 1),
          to: DateTime(2026, 3, 31),
        ),
        0,
      );
    });

    test('splits revenue by method', () async {
      await pay(100000, method: PaymentMethod.cash, paidAt: DateTime(2026, 3, 2));
      await pay(50000, method: PaymentMethod.cash, paidAt: DateTime(2026, 3, 3));
      await pay(75000, method: PaymentMethod.upi, paidAt: DateTime(2026, 3, 4));
      await pay(
        20000,
        method: PaymentMethod.upi,
        paidAt: DateTime(2026, 3, 5),
        pending: true,
      );

      final totals = await repository.revenueByMethod(
        from: DateTime(2026, 3, 1),
        to: DateTime(2026, 3, 31),
      );

      expect(totals[PaymentMethod.cash], 150000);
      expect(totals[PaymentMethod.upi], 75000, reason: 'pending excluded');
      expect(totals[PaymentMethod.bankTransfer], isNull);
    });

    test('by-method totals reconcile with the overall total', () async {
      for (final method in PaymentMethod.values) {
        await pay(10000, method: method, paidAt: DateTime(2026, 3, 10));
      }

      final range = (from: DateTime(2026, 3, 1), to: DateTime(2026, 3, 31));
      final totals = await repository.revenueByMethod(
        from: range.from,
        to: range.to,
      );
      final overall = await repository.revenueInRange(
        from: range.from,
        to: range.to,
      );

      expect(totals.values.fold(0, (a, b) => a + b), overall);
    });
  });

  group('voiding', () {
    test('soft-deletes rather than erasing', () async {
      // A wrong payment is a correction with an audit trail, not something
      // that should vanish from the books.
      final id = await pay(150000);
      await repository.voidPayment(id);

      expect(await repository.historyFor(memberId), isEmpty);

      final raw = await db.select(db.payments).get();
      expect(raw.single.isDeleted, isTrue);
      expect(raw.single.isDirty, isTrue, reason: 'the void must sync');
    });
  });

  group('receipts', () {
    test('a payment without a receipt is not queued for upload', () async {
      await pay(150000);
      expect(await repository.awaitingReceiptUpload(), isEmpty);
    });

    test('attaching a URL clears the pending-upload state', () async {
      // Simulates what sync does once the file reaches Storage.
      final id = await db.paymentDao.record(
        memberId: memberId,
        amountMinor: 150000,
        method: PaymentMethod.cash,
        receiptLocalPath: '/tmp/receipt.jpg',
      );

      expect(await repository.awaitingReceiptUpload(), hasLength(1));

      await db.paymentDao.attachReceiptUrl(id, 'https://storage/r.jpg');

      expect(await repository.awaitingReceiptUpload(), isEmpty);
      final payment = await db.paymentDao.byId(id);
      expect(payment!.receiptUrl, 'https://storage/r.jpg');
      expect(
        payment.receiptLocalPath,
        isNull,
        reason: 'the local copy is released once uploaded',
      );
    });
  });

  group('history', () {
    test('is newest first', () async {
      await pay(100, paidAt: DateTime(2026, 1, 1));
      await pay(200, paidAt: DateTime(2026, 3, 1));
      await pay(300, paidAt: DateTime(2026, 2, 1));

      final history = await repository.historyFor(memberId);
      expect(
        history.map((p) => p.amountMinor),
        [200, 300, 100],
      );
    });

    test('is scoped to the member', () async {
      final other = await db.profileDao.createMember(fullName: 'Other');
      await pay(150000);
      await repository.record(
        memberId: other,
        amountMinor: 999,
        method: PaymentMethod.cash,
      );

      final history = await repository.historyFor(memberId);
      expect(history, hasLength(1));
      expect(history.single.amountMinor, 150000);
    });
  });

  group('currentMonthRange', () {
    test('covers the whole month', () {
      final range = currentMonthRange(DateTime(2026, 3, 15, 13, 30));

      expect(range.from, DateTime(2026, 3, 1));
      expect(range.to.month, 3);
      expect(range.to.day, 31);
    });

    test('handles February and year boundaries', () {
      final feb = currentMonthRange(DateTime(2026, 2, 10));
      expect(feb.to.day, 28);

      final dec = currentMonthRange(DateTime(2026, 12, 10));
      expect(dec.from, DateTime(2026, 12, 1));
      expect(dec.to.day, 31);
      expect(dec.to.year, 2026);
    });

    test('includes a payment made on the last day of the month', () async {
      // An exclusive end bound would silently drop month-end takings.
      await pay(150000, paidAt: DateTime(2026, 3, 31, 22, 0));

      final range = currentMonthRange(DateTime(2026, 3, 15));
      final total = await repository.revenueInRange(
        from: range.from,
        to: range.to,
      );

      expect(total, 150000);
    });

    test('includes a payment made at the first instant of the month',
        () async {
      await pay(50000, paidAt: DateTime(2026, 3, 1));

      final range = currentMonthRange(DateTime(2026, 3, 15));
      final total = await repository.revenueInRange(
        from: range.from,
        to: range.to,
      );

      expect(total, 50000);
    });
  });

  group('applyPayment (brain.md §6.5)', () {
    late InvoiceRepository invoices;
    late String invoiceId;

    setUp(() async {
      invoices = InvoiceRepository(db);
      invoiceId = await invoices.createAdHocCharge(
        memberId: memberId,
        description: 'Fee',
        amountMinor: 100000,
      );
    });

    test('settles an invoice through the payment repository', () async {
      final paymentId = await repository.applyPayment(
        invoiceId: invoiceId,
        amountMinor: 100000,
        method: PaymentMethod.cash,
      );

      expect((await db.paymentDao.byId(paymentId))!.invoiceId, invoiceId);
      expect((await invoices.byId(invoiceId))!.status, 'paid');
    });

    test('markPaid on an invoiced payment updates the invoice balance',
        () async {
      final paymentId = await repository.applyPayment(
        invoiceId: invoiceId,
        amountMinor: 100000,
        method: PaymentMethod.cash,
        pending: true,
      );

      await repository.markPaid(paymentId);

      expect((await db.paymentDao.byId(paymentId))!.status, 'paid');
      expect((await invoices.byId(invoiceId))!.status, 'paid');
    });

    test('voidPayment on an invoiced payment reverses the invoice balance',
        () async {
      final paymentId = await repository.applyPayment(
        invoiceId: invoiceId,
        amountMinor: 100000,
        method: PaymentMethod.cash,
      );

      await repository.voidPayment(paymentId);

      expect((await invoices.byId(invoiceId))!.status, 'unpaid');
      expect((await invoices.byId(invoiceId))!.amountPaidMinor, 0);
    });

    test('a free-floating payment (no invoice) still voids the old way',
        () async {
      final id = await pay(150000);
      await repository.voidPayment(id);

      final raw = await db.select(db.payments).get();
      expect(raw.single.isDeleted, isTrue);
    });
  });
}
