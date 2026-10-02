import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_constants.dart';
import '../../../data/local/database.dart';
import '../providers/attendance_providers.dart';

/// A member's visit history (brain.md §6.2, §6.3).
///
/// Self-reported entries are marked distinctly: they are the member's own
/// record, not staff-verified (brain.md §6.7).
class AttendanceHistoryScreen extends ConsumerWidget {
  const AttendanceHistoryScreen({
    required this.memberId,
    this.title = 'Attendance',
    super.key,
  });

  final String memberId;
  final String title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(attendanceHistoryProvider(memberId));

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: history.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Could not load: $error')),
        data: (records) =>
            records.isEmpty ? const _Empty() : _HistoryList(records: records),
      ),
    );
  }
}

class _HistoryList extends StatelessWidget {
  const _HistoryList({required this.records});

  final List<AttendanceData> records;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Group by month so a long history stays scannable.
    final grouped = <String, List<AttendanceData>>{};
    for (final record in records) {
      final key = DateFormat.yMMMM().format(record.attendanceDate);
      grouped.putIfAbsent(key, () => []).add(record);
    }

    return ListView(
      children: [
        for (final entry in grouped.entries) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(entry.key, style: theme.textTheme.titleSmall),
                Text(
                  entry.value.length == 1
                      ? '1 visit'
                      : '${entry.value.length} visits',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              ],
            ),
          ),
          for (final record in entry.value) _VisitTile(record: record),
        ],
      ],
    );
  }
}

class _VisitTile extends StatelessWidget {
  const _VisitTile({required this.record});

  final AttendanceData record;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isSelfReported =
        record.source == AttendanceSource.selfReported.wireValue;

    return ListTile(
      dense: true,
      leading: Icon(
        isSelfReported ? Icons.edit_calendar_outlined : Icons.qr_code_2,
        color: isSelfReported
            ? theme.colorScheme.outline
            : theme.colorScheme.primary,
      ),
      title: Text(DateFormat.yMMMEd().format(record.attendanceDate)),
      subtitle: Text(_timeRange(record) ?? '—'),
      trailing: isSelfReported
          ? Tooltip(
              message: 'Self-reported by the member, not staff-verified',
              child: Chip(
                label: const Text('Self'),
                labelStyle: theme.textTheme.labelSmall,
                visualDensity: VisualDensity.compact,
                side: BorderSide(color: theme.colorScheme.outlineVariant),
              ),
            )
          : null,
    );
  }

  static String? _timeRange(AttendanceData record) {
    final start = record.checkInAt;
    if (start == null) return null;

    final startText = DateFormat.jm().format(start);
    final end = record.checkOutAt;
    return end == null
        ? startText
        : '$startText – ${DateFormat.jm().format(end)}';
  }
}

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
              Icons.event_busy_outlined,
              size: 48,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text('No visits yet', style: theme.textTheme.titleMedium),
          ],
        ),
      ),
    );
  }
}
