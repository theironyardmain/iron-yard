import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/money.dart';
import '../providers/payment_providers.dart';
import '../widgets/payment_tile.dart';
import 'record_payment_screen.dart';

/// One member's payment history (brain.md §6.2, §6.5).
class MemberPaymentsScreen extends ConsumerWidget {
  const MemberPaymentsScreen({
    required this.memberId,
    required this.memberName,
    this.canRecord = true,
    super.key,
  });

  final String memberId;
  final String memberName;

  /// Members view their own history but never record payments (brain.md §6.5).
  final bool canRecord;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final payments = ref.watch(paymentHistoryProvider(memberId));
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(memberName)),
      body: payments.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Could not load: $error')),
        data: (list) {
          if (list.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.receipt_long_outlined,
                      size: 48,
                      color: theme.colorScheme.outline,
                    ),
                    const SizedBox(height: 16),
                    Text('No payments yet', style: theme.textTheme.titleMedium),
                  ],
                ),
              ),
            );
          }

          final total = list
              .where((p) => p.status == 'paid')
              .fold(0, (sum, p) => sum + p.amountMinor);

          return Column(
            children: [
              Card(
                margin: const EdgeInsets.all(12),
                child: ListTile(
                  leading: const Icon(Icons.summarize_outlined),
                  title: const Text('Total paid'),
                  trailing: Text(
                    Money.format(total),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: list.length,
                  itemBuilder: (context, index) => PaymentTile(
                    payment: list[index],
                    memberName: memberName,
                    showDate: true,
                  ),
                ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: canRecord
          ? FloatingActionButton.extended(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => RecordPaymentScreen(
                    memberId: memberId,
                    memberName: memberName,
                  ),
                ),
              ),
              icon: const Icon(Icons.add),
              label: const Text('Record'),
            )
          : null,
    );
  }
}
