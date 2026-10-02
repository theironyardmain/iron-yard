import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/utils/money.dart';
import '../../../data/local/database.dart';
import '../../../shared/providers/database_provider.dart';
import '../providers/invoice_providers.dart';
import 'record_payment_screen.dart';

/// Outstanding balances across all members — the dues report (brain.md
/// §6.5). Tapping an invoice jumps straight into recording a payment for it.
class DuesScreen extends ConsumerStatefulWidget {
  const DuesScreen({super.key});

  @override
  ConsumerState<DuesScreen> createState() => _DuesScreenState();
}

class _DuesScreenState extends ConsumerState<DuesScreen> {
  bool _overdueOnly = false;

  @override
  Widget build(BuildContext context) {
    final invoices = ref.watch(outstandingInvoicesProvider);
    final total = ref.watch(totalOutstandingProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Outstanding balances')),
      body: Column(
        children: [
          Card(
            margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(
                    Icons.request_quote_outlined,
                    color: theme.colorScheme.error,
                    size: 32,
                  ),
                  const SizedBox(width: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Total outstanding',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.outline,
                        ),
                      ),
                      Text(
                        total.maybeWhen(
                          data: Money.format,
                          orElse: () => '—',
                        ),
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                FilterChip(
                  label: const Text('Overdue only'),
                  selected: _overdueOnly,
                  onSelected: (value) => setState(() => _overdueOnly = value),
                ),
              ],
            ),
          ),
          Expanded(
            child: invoices.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) =>
                  Center(child: Text('Could not load dues: $error')),
              data: (list) {
                final today = DateTime.now();
                final filtered = _overdueOnly
                    ? list
                          .where(
                            (i) =>
                                i.dueDate != null && i.dueDate!.isBefore(today),
                          )
                          .toList()
                    : list;

                if (filtered.isEmpty) {
                  return _Empty(overdueOnly: _overdueOnly);
                }

                return ListView.builder(
                  itemCount: filtered.length,
                  itemBuilder: (context, index) =>
                      _InvoiceTile(invoice: filtered[index]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _InvoiceTile extends ConsumerWidget {
  const _InvoiceTile({required this.invoice});

  final Invoice invoice;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final profile = ref.watch(_memberNameProvider(invoice.memberId));
    final remaining = invoice.totalMinor - invoice.amountPaidMinor;
    final isOverdue =
        invoice.dueDate != null && invoice.dueDate!.isBefore(DateTime.now());

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: isOverdue
            ? theme.colorScheme.errorContainer
            : theme.colorScheme.surfaceContainerHighest,
        child: Icon(
          isOverdue ? Icons.warning_amber_outlined : Icons.receipt_long_outlined,
          size: 20,
          color: isOverdue
              ? theme.colorScheme.onErrorContainer
              : theme.colorScheme.outline,
        ),
      ),
      title: Text(profile.valueOrNull ?? '…'),
      subtitle: Text(
        [
          invoice.description ?? 'Charge',
          if (invoice.dueDate != null)
            'Due ${DateFormat.yMMMd().format(invoice.dueDate!)}',
          if (invoice.status == 'partial')
            '${Money.format(invoice.amountPaidMinor)} paid',
        ].join(' · '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Text(
        Money.format(remaining),
        style: theme.textTheme.bodyLarge?.copyWith(
          fontWeight: FontWeight.w600,
          color: isOverdue ? theme.colorScheme.error : null,
        ),
      ),
      onTap: () async {
        final memberName = profile.valueOrNull ?? 'Member';
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => RecordPaymentScreen(
              memberId: invoice.memberId,
              memberName: memberName,
              invoiceId: invoice.id,
            ),
          ),
        );
      },
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
  const _Empty({required this.overdueOnly});

  final bool overdueOnly;

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
              Icons.check_circle_outline,
              size: 48,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              overdueOnly ? 'No overdue balances' : 'No outstanding balances',
              style: theme.textTheme.titleMedium,
            ),
          ],
        ),
      ),
    );
  }
}
