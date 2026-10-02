import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/utils/money.dart';
import '../../../data/local/database.dart';

/// One payment row (brain.md §6.5).
class PaymentTile extends StatelessWidget {
  const PaymentTile({
    required this.payment,
    this.memberName,
    this.showDate = false,
    this.onTap,
    super.key,
  });

  final Payment payment;

  /// Resolved separately by the caller; null while still loading.
  final String? memberName;

  /// Show the date in the subtitle, for lists not already grouped by day.
  final bool showDate;

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final method = PaymentMethod.fromString(payment.method);
    final isPending = payment.status == 'pending';

    final subtitleParts = <String>[
      if (showDate) DateFormat.yMMMd().format(payment.paidAt),
      method?.label ?? payment.method,
      if (payment.notes?.isNotEmpty == true) payment.notes!,
    ];

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: isPending
            ? theme.colorScheme.surfaceContainerHighest
            : theme.colorScheme.primaryContainer,
        child: Icon(
          _iconFor(method),
          size: 20,
          color: isPending
              ? theme.colorScheme.outline
              : theme.colorScheme.onPrimaryContainer,
        ),
      ),
      title: Text(memberName ?? '…'),
      subtitle: Text(
        subtitleParts.join(' · '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            Money.format(payment.amountMinor),
            style: theme.textTheme.bodyLarge?.copyWith(
              fontWeight: FontWeight.w600,
              // A pending amount is struck through so it never reads as
              // money already received.
              decoration: isPending ? TextDecoration.lineThrough : null,
              color: isPending ? theme.colorScheme.outline : null,
            ),
          ),
          if (isPending)
            Text(
              'Pending',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.tertiary,
              ),
            )
          else if (payment.receiptLocalPath != null)
            Tooltip(
              message: 'Receipt not uploaded yet',
              child: Icon(
                Icons.cloud_upload_outlined,
                size: 14,
                color: theme.colorScheme.outline,
              ),
            ),
        ],
      ),
      onTap: onTap,
    );
  }

  static IconData _iconFor(PaymentMethod? method) => switch (method) {
    PaymentMethod.cash => Icons.payments_outlined,
    PaymentMethod.bankTransfer => Icons.account_balance_outlined,
    PaymentMethod.upi => Icons.qr_code,
    PaymentMethod.external => Icons.receipt_long_outlined,
    null => Icons.help_outline,
  };
}
