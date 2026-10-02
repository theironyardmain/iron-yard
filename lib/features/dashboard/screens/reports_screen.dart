import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/utils/money.dart';
import '../data/csv_exporter.dart';
import '../data/export_share.dart';
import '../providers/dashboard_providers.dart';

/// Reports and CSV export (brain.md §6.3).
class ReportsScreen extends ConsumerWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reports')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: const [
          _RevenueCard(),
          SizedBox(height: 12),
          _ExportCard(),
        ],
      ),
    );
  }
}

class _RevenueCard extends ConsumerWidget {
  const _RevenueCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final trend = ref.watch(revenueTrendProvider);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Revenue', style: theme.textTheme.titleSmall),
            Text(
              'Last 6 months · paid only',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
            const SizedBox(height: 12),

            trend.when(
              loading: () => const Center(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: CircularProgressIndicator(),
                ),
              ),
              error: (error, _) => Text('$error'),
              data: (months) {
                final peak = months.fold(
                  1,
                  (max, m) => m.revenueMinor > max ? m.revenueMinor : max,
                );

                return Column(
                  children: [
                    for (final month in months)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 56,
                              child: Text(
                                DateFormat.MMM().format(month.month),
                                style: theme.textTheme.bodySmall,
                              ),
                            ),
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(
                                  value: month.revenueMinor / peak,
                                  minHeight: 18,
                                  backgroundColor:
                                      theme.colorScheme.surfaceContainerHighest,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            SizedBox(
                              width: 90,
                              child: Text(
                                Money.format(month.revenueMinor),
                                textAlign: TextAlign.right,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _ExportCard extends ConsumerStatefulWidget {
  const _ExportCard();

  @override
  ConsumerState<_ExportCard> createState() => _ExportCardState();
}

class _ExportCardState extends ConsumerState<_ExportCard> {
  ExportKind? _exporting;

  Future<void> _export(ExportKind kind) async {
    setState(() => _exporting = kind);

    final messenger = ScaffoldMessenger.of(context);

    try {
      final exporter = ref.read(csvExporterProvider);
      final csv = await exporter.build(kind);

      await ExportShare.share(
        csv: csv,
        fileName: exporter.fileNameFor(kind),
        subject: '${kind.label} export',
      );
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('Export failed: $error')),
      );
    } finally {
      if (mounted) setState(() => _exporting = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Export', style: theme.textTheme.titleSmall),
            Text(
              ExportShare.isSupported
                  ? 'CSV files you can open in a spreadsheet'
                  : 'Export needs the Android app',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
            const SizedBox(height: 8),

            for (final kind in ExportKind.values)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(_iconFor(kind)),
                title: Text(kind.label),
                subtitle: Text(_subtitleFor(kind)),
                trailing: _exporting == kind
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.download_outlined),
                enabled: ExportShare.isSupported && _exporting == null,
                onTap: ExportShare.isSupported ? () => _export(kind) : null,
              ),
          ],
        ),
      ),
    );
  }

  static IconData _iconFor(ExportKind kind) => switch (kind) {
    ExportKind.members => Icons.people_outline,
    ExportKind.payments => Icons.payments_outlined,
    ExportKind.attendance => Icons.qr_code_scanner,
  };

  static String _subtitleFor(ExportKind kind) => switch (kind) {
    ExportKind.members => 'All members with status and expiry',
    ExportKind.payments => 'Every recorded payment',
    ExportKind.attendance => 'Last 30 days of check-ins',
  };
}
