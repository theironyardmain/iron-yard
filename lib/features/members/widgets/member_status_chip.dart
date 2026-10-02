import 'package:flutter/material.dart';

import '../../../data/local/daos/membership_dao.dart';

/// Colour-coded membership status (brain.md §6.3).
///
/// Deactivation takes precedence over membership state: a deactivated member
/// with a valid plan must not read as "Active".
class MemberStatusChip extends StatelessWidget {
  const MemberStatusChip({
    required this.status,
    this.daysRemaining,
    this.isDeactivated = false,
    super.key,
  });

  final MembershipStatus status;
  final int? daysRemaining;
  final bool isDeactivated;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final (label, background, foreground) = isDeactivated
        ? ('Deactivated', scheme.surfaceContainerHighest, scheme.outline)
        : switch (status) {
            MembershipStatus.active => (
              'Active',
              scheme.primaryContainer,
              scheme.onPrimaryContainer,
            ),
            MembershipStatus.expiringSoon => (
              _expiringLabel(),
              scheme.tertiaryContainer,
              scheme.onTertiaryContainer,
            ),
            MembershipStatus.expired => (
              'Expired',
              scheme.errorContainer,
              scheme.onErrorContainer,
            ),
            MembershipStatus.cancelled => (
              'Cancelled',
              scheme.surfaceContainerHighest,
              scheme.outline,
            ),
            MembershipStatus.none => (
              'No plan',
              scheme.surfaceContainerHighest,
              scheme.onSurfaceVariant,
            ),
          };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: foreground,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  String _expiringLabel() {
    final days = daysRemaining;
    if (days == null) return 'Expiring';
    if (days <= 0) return 'Expires today';
    if (days == 1) return '1 day left';
    return '$days days left';
  }
}
