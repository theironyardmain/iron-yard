import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../data/local/daos/membership_dao.dart';
import '../data/qr_payload.dart';

/// The member's digital membership card (brain.md §6.2).
///
/// Generated on-device from cached data, so it renders with no connection —
/// the member can always show it at the desk.
class MemberQrCard extends StatelessWidget {
  const MemberQrCard({
    required this.payload,
    required this.status,
    this.expiresOn,
    super.key,
  });

  final QrPayload payload;
  final MembershipStatus status;
  final DateTime? expiresOn;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              payload.fullName,
              style: theme.textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),

            // The QR itself is always white-on-black regardless of theme:
            // scanners need the contrast, and inverting it in dark mode makes
            // some readers fail.
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: QrImageView(
                data: payload.encode(),
                version: QrVersions.auto,
                size: 220,
                backgroundColor: Colors.white,
                // Medium correction tolerates a scuffed screen without
                // inflating the code's density.
                errorCorrectionLevel: QrErrorCorrectLevel.M,
              ),
            ),

            const SizedBox(height: 16),
            _StatusLine(status: status, expiresOn: expiresOn, scheme: scheme),
            const SizedBox(height: 8),
            Text(
              'Show this at the desk',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.outline,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({
    required this.status,
    required this.scheme,
    this.expiresOn,
  });

  final MembershipStatus status;
  final ColorScheme scheme;
  final DateTime? expiresOn;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final (icon, label, colour) = switch (status) {
      MembershipStatus.active => (
        Icons.check_circle,
        expiresOn == null
            ? 'Active'
            : 'Active until ${DateFormat.yMMMd().format(expiresOn!)}',
        scheme.primary,
      ),
      MembershipStatus.expiringSoon => (
        Icons.warning_amber_rounded,
        expiresOn == null
            ? 'Expiring soon'
            : 'Expires ${DateFormat.yMMMd().format(expiresOn!)}',
        scheme.tertiary,
      ),
      MembershipStatus.expired => (
        Icons.error_outline,
        expiresOn == null
            ? 'Expired'
            : 'Expired ${DateFormat.yMMMd().format(expiresOn!)}',
        scheme.error,
      ),
      MembershipStatus.cancelled => (
        Icons.cancel_outlined,
        'Cancelled',
        scheme.error,
      ),
      MembershipStatus.none => (
        Icons.info_outline,
        'No active plan',
        scheme.outline,
      ),
    };

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 18, color: colour),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colour,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}
