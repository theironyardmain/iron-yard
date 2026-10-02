import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../data/sync/sync_controller.dart';
import '../providers/sync_providers.dart';

/// Sync state in the app bar (brain.md §10.7).
///
/// Shows pending work and when the device last synced, so staff can tell
/// whether what they are looking at is current.
class SyncIndicator extends ConsumerWidget {
  const SyncIndicator({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(syncStatusProvider).valueOrNull;
    final pending = ref.watch(pendingChangesProvider).valueOrNull ?? 0;
    final theme = Theme.of(context);

    final isSyncing = status?.isSyncing ?? false;

    return IconButton(
      tooltip: 'Sync',
      onPressed: isSyncing
          ? null
          : () => _syncNow(context, ref),
      icon: Badge(
        isLabelVisible: pending > 0,
        label: Text('$pending'),
        child: isSyncing
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(
                pending > 0 ? Icons.cloud_upload_outlined : Icons.cloud_done_outlined,
                color: pending > 0 ? theme.colorScheme.tertiary : null,
              ),
      ),
    );
  }

  Future<void> _syncNow(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final report = await runSyncThenReceipts(
      controller: ref.read(syncControllerProvider),
      uploader: ref.read(receiptUploaderProvider),
      trigger: SyncTrigger.manual,
    );

    if (report == null || !context.mounted) return;

    final text = switch (report) {
      _ when report.hasFailures =>
        'Sync incomplete — ${report.failures.length} '
            '${report.failures.length == 1 ? 'section' : 'sections'} failed',
      _ when report.hasRejections =>
        '${report.rejected.length} '
            '${report.rejected.length == 1 ? 'change was' : 'changes were'} '
            'refused by the server',
      _ when report.pushed == 0 && report.pulled == 0 => 'Already up to date',
      _ =>
        'Synced — ${report.pushed} sent, ${report.pulled} received',
    };

    messenger.showSnackBar(
      SnackBar(
        content: Text(text),
        action: report.hasRejections
            ? SnackBarAction(
                label: 'Details',
                onPressed: () => _showRejections(context, ref),
              )
            : null,
      ),
    );
  }

  void _showRejections(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => const _RejectionSheet(),
    );
  }
}

/// Explains changes the server refused (brain.md §10.6).
class _RejectionSheet extends ConsumerWidget {
  const _RejectionSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final report = ref.watch(syncStatusProvider).valueOrNull?.lastReport;
    final rejected = report?.rejected ?? const [];

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Refused changes', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              // These will never succeed on retry, so say what happened rather
              // than leaving them spinning in the queue.
              'These could not be saved to the server and will not be retried.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
            const SizedBox(height: 16),
            for (final item in rejected)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  Icons.error_outline,
                  color: theme.colorScheme.error,
                ),
                title: Text(item.reason.message),
                subtitle: Text(item.table.replaceAll('_', ' ')),
              ),
          ],
        ),
      ),
    );
  }
}

/// A line of text for the "last synced" timestamp.
class LastSyncedLabel extends ConsumerWidget {
  const LastSyncedLabel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(syncStatusProvider).valueOrNull;
    final theme = Theme.of(context);

    final lastSynced = status?.lastSyncedAt;
    final text = lastSynced == null
        ? 'Not synced yet'
        : 'Last synced ${_relative(lastSynced)}';

    return Text(
      text,
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.outline,
      ),
    );
  }

  static String _relative(DateTime at) {
    final difference = DateTime.now().difference(at);

    if (difference.inMinutes < 1) return 'just now';
    if (difference.inMinutes < 60) return '${difference.inMinutes}m ago';
    if (difference.inHours < 24) return '${difference.inHours}h ago';
    return DateFormat.yMMMd().format(at);
  }
}
