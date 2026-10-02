import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/local/database.dart';
import '../../../shared/providers/database_provider.dart';
import '../data/invoice_repository.dart';

final invoiceRepositoryProvider = Provider<InvoiceRepository>(
  (ref) => InvoiceRepository(ref.watch(databaseProvider)),
);

/// A single invoice, for the payment/charge screens.
final invoiceByIdProvider = FutureProvider.family<Invoice?, String>(
  (ref, id) => ref.watch(invoiceRepositoryProvider).byId(id),
);

/// A member's outstanding balance in paise (0 when fully settled).
final memberBalanceProvider = FutureProvider.family<int, String>(
  (ref, memberId) => ref.watch(invoiceRepositoryProvider).balanceFor(memberId),
);

/// System-wide outstanding balance, for a dashboard tile.
final totalOutstandingProvider = FutureProvider<int>(
  (ref) => ref.watch(invoiceRepositoryProvider).totalOutstanding(),
);

/// Open invoices system-wide, most overdue first — the dues screen.
final outstandingInvoicesProvider = StreamProvider<List<Invoice>>(
  (ref) => ref.watch(invoiceRepositoryProvider).watchOutstanding(),
);

/// A member's open invoices — used to decide whether "Record payment" should
/// go straight to an existing invoice or offer to create a charge first.
final memberOutstandingInvoicesProvider =
    StreamProvider.family<List<Invoice>, String>(
      (ref, memberId) => ref
          .watch(invoiceRepositoryProvider)
          .watchOutstanding(memberId: memberId),
    );

/// Outstanding invoices past their due date.
final overdueInvoicesProvider = FutureProvider<List<Invoice>>(
  (ref) => ref.watch(invoiceRepositoryProvider).overdue(),
);

/// A member's full invoice history, any status, newest first.
final invoiceHistoryProvider = StreamProvider.family<List<Invoice>, String>(
  (ref, memberId) =>
      ref.watch(invoiceRepositoryProvider).watchHistoryFor(memberId),
);
