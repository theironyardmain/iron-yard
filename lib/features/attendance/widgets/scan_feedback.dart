import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/scan_result.dart';

/// Shows what happened after a scan (brain.md §6.4).
///
/// Colour and icon differ per outcome so staff can read the result at a glance
/// across a busy desk, without reading the text.
class ScanFeedback extends StatelessWidget {
  const ScanFeedback({
    required this.outcome,
    required this.onDismiss,
    super.key,
  });

  final ScanOutcome outcome;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final (icon, title, detail, colour) = switch (outcome) {
      ScanAccepted(:final name, :final expiresOn, :final upgraded) => (
        Icons.check_circle,
        name,
        upgraded
            // The member self-reported earlier today; the staff scan replaces
            // it as the verified record (brain.md §6.7).
            ? 'Checked in — replaces their self-reported entry'
            : (outcome as ScanAccepted).warnsAboutExpiry && expiresOn != null
            ? 'Checked in — expires ${DateFormat.yMMMd().format(expiresOn)}'
            : 'Checked in',
        Colors.green,
      ),

      ScanAlreadyCheckedIn(:final name, :final checkedInAt) => (
        Icons.info,
        name,
        checkedInAt == null
            ? 'Already checked in today'
            : 'Already checked in at '
                  '${DateFormat.jm().format(checkedInAt)}',
        scheme.tertiary,
      ),

      ScanExpired(:final name, :final expiredOn) => (
        Icons.warning_amber_rounded,
        name,
        expiredOn == null
            ? 'No active plan — visit recorded'
            : 'Expired ${DateFormat.yMMMd().format(expiredOn)} — '
                  'visit recorded',
        Colors.orange,
      ),

      ScanDeactivated(:final name) => (
        Icons.person_off,
        name,
        'This member is deactivated',
        scheme.error,
      ),

      ScanUnknownMember(:final scannedName) => (
        Icons.sync_problem,
        scannedName.isEmpty ? 'Unknown member' : scannedName,
        'Not on this device yet — sync and try again',
        scheme.error,
      ),

      ScanNotACard() => (
        Icons.qr_code_scanner,
        'Not a membership card',
        'Scan a member\'s Iron Yard card',
        scheme.outline,
      ),
    };

    return Material(
      color: scheme.surface,
      elevation: 8,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: colour.withValues(alpha: 0.15),
                    child: Icon(icon, color: colour),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          detail,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colour,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: onDismiss,
                child: const Text('Scan next'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
