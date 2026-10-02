import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/utils/money.dart';
import '../../../data/local/database.dart';
import '../../../shared/providers/database_provider.dart';
import '../providers/invoice_providers.dart';
import '../providers/payment_providers.dart';
import '../widgets/payment_tile.dart';
import 'dues_screen.dart';

/// All recorded payments, with this month's revenue (brain.md §6.5).
class PaymentListScreen extends ConsumerWidget {
  const PaymentListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final payments = ref.watch(allPaymentsProvider);
    final range = currentMonthRange();
    final revenue = ref.watch(revenueProvider(range));
    final outstanding = ref.watch(totalOutstandingProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Payments'),
        actions: [
          IconButton(
            icon: const Icon(Icons.request_quote_outlined),
            tooltip: 'Outstanding balances',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const DuesScreen()),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          _RevenueHeader(revenue: revenue, range: range, outstanding: outstanding),
          Expanded(
            child: payments.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) =>
                  Center(child: Text('Could not load payments: $error')),
              data: (list) =>
                  list.isEmpty ? const _Empty() : _PaymentList(payments: list),
            ),
          ),
        ],
      ),
    );
  }
}

class _RevenueHeader extends StatelessWidget {
  const _RevenueHeader({
    required this.revenue,
    required this.range,
    required this.outstanding,
  });

  final AsyncValue<int> revenue;
  final DateRange range;
  final AsyncValue<int> outstanding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              Icons.trending_up,
              color: theme.colorScheme.primary,
              size: 32,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    DateFormat.yMMMM().format(range.from),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                  Text(
                    revenue.maybeWhen(
                      data: Money.format,
                      orElse: () => '—',
                    ),
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  'Outstanding',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
                Text(
                  outstanding.maybeWhen(
                    data: Money.format,
                    orElse: () => '—',
                  ),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.error,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PaymentList extends ConsumerWidget {
  const _PaymentList({required this.payments});

  final List<Payment> payments;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    // Group by day so a busy month stays readable.
    final grouped = <String, List<Payment>>{};
    for (final payment in payments) {
      final key = DateFormat.yMMMd().format(payment.paidAt);
      grouped.putIfAbsent(key, () => []).add(payment);
    }

    return ListView(
      children: [
        for (final entry in grouped.entries) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(entry.key, style: theme.textTheme.titleSmall),
                Text(
                  Money.format(
                    entry.value
                        .where((p) => p.status == 'paid')
                        .fold(0, (sum, p) => sum + p.amountMinor),
                  ),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              ],
            ),
          ),
          for (final payment in entry.value)
            _NamedPaymentTile(payment: payment),
        ],
      ],
    );
  }
}

/// A payment row that resolves the member's name from the local cache.
class _NamedPaymentTile extends ConsumerWidget {
  const _NamedPaymentTile({required this.payment});

  final Payment payment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(_memberNameProvider(payment.memberId));

    return PaymentTile(
      payment: payment,
      memberName: profile.valueOrNull,
    );
  }
}

final _memberNameProvider = FutureProvider.family<String?, String>((
  ref,
  memberId,
) async {
  final profile = await ref.watch(profileDaoProvider).byId(memberId);
  return profile?.fullName;
});

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.payments_outlined,
              size: 48,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text('No payments yet', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Record a payment from a member\'s profile.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
