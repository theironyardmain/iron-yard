import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../data/local/database.dart';
import '../../../shared/providers/database_provider.dart';
import '../data/payment_repository.dart';

final paymentRepositoryProvider = Provider<PaymentRepository>(
  (ref) => PaymentRepository(ref.watch(databaseProvider)),
);

/// All payments, newest first — the admin payments list.
final allPaymentsProvider = StreamProvider<List<Payment>>(
  (ref) => ref.watch(paymentRepositoryProvider).watchAll(),
);

/// One member's payment history.
final paymentHistoryProvider = StreamProvider.family<List<Payment>, String>(
  (ref, memberId) =>
      ref.watch(paymentRepositoryProvider).watchHistoryFor(memberId),
);

/// Payments still marked pending.
final pendingPaymentsProvider = FutureProvider<List<Payment>>(
  (ref) => ref.watch(paymentRepositoryProvider).pendingPayments(),
);

/// A date range for the revenue figures.
typedef DateRange = ({DateTime from, DateTime to});

/// This month, as the default reporting window.
DateRange currentMonthRange([DateTime? now]) {
  final today = now ?? DateTime.now();
  return (
    from: DateTime(today.year, today.month),
    to: DateTime(today.year, today.month + 1).subtract(
      const Duration(microseconds: 1),
    ),
  );
}

/// Revenue in a range, in paise.
final revenueProvider = FutureProvider.family<int, DateRange>(
  (ref, range) => ref
      .watch(paymentRepositoryProvider)
      .revenueInRange(from: range.from, to: range.to),
);

/// Revenue split by payment method.
final revenueByMethodProvider =
    FutureProvider.family<Map<PaymentMethod, int>, DateRange>(
      (ref, range) => ref
          .watch(paymentRepositoryProvider)
          .revenueByMethod(from: range.from, to: range.to),
    );

/// A single payment, for screens that need to resolve one by id (e.g. the
/// invoice history detail).
final paymentByIdProvider = FutureProvider.family<Payment?, String>(
  (ref, id) => ref.watch(paymentDaoProvider).byId(id),
);
