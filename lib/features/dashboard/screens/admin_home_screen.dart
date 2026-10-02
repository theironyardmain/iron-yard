import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/utils/money.dart';
import '../../../data/sync/sync_controller.dart';
import '../../../shared/providers/sync_providers.dart';
import '../../../shared/widgets/sync_indicator.dart';
import '../../feedback/screens/feedback_inbox_screen.dart';
import '../../members/screens/member_detail_screen.dart';
import '../../trainers/screens/trainer_list_screen.dart';
import '../data/dashboard_repository.dart';
import '../providers/dashboard_providers.dart';
import 'reports_screen.dart';

/// Admin home — today's figures at a glance (brain.md §6.3).
///
/// Every number comes from the local cache, so this opens offline.
class AdminHomeScreen extends ConsumerWidget {
  const AdminHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(dashboardSummaryProvider);

    return RefreshIndicator(
      onRefresh: () async {
        await runSyncThenReceipts(
          controller: ref.read(syncControllerProvider),
          uploader: ref.read(receiptUploaderProvider),
          trigger: SyncTrigger.manual,
        );
        ref.invalidate(needsAttentionProvider);
      },
      child: summary.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => ListView(
          children: [
            Padding(
              padding: const EdgeInsets.all(32),
              child: Text('Could not load the dashboard: $error'),
            ),
          ],
        ),
        data: (data) => _DashboardBody(data: data),
      ),
    );
  }
}

class _DashboardBody extends ConsumerWidget {
  const _DashboardBody({required this.data});

  final DashboardSummary data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 4, 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                DateFormat.yMMMEd().format(DateTime.now()),
                style: theme.textTheme.titleMedium,
              ),
              const LastSyncedLabel(),
            ],
          ),
        ),

        Row(
          children: [
            Expanded(
              child: _StatTile(
                icon: Icons.qr_code_scanner,
                label: 'Checked in today',
                value: '${data.todayAttendance}',
                // Self-reports are shown apart, never folded in. Owner
                // decision 2026-09-21: staff scans are the official record
                // (brain.md §6.7).
                footnote: data.unverifiedToday == 0
                    ? null
                    : '+${data.unverifiedToday} self-reported',
                colour: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _StatTile(
                icon: Icons.people,
                label: 'Active members',
                value: '${data.activeMembers}',
                colour: theme.colorScheme.primary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

        Row(
          children: [
            Expanded(
              child: _StatTile(
                icon: Icons.trending_up,
                label: 'This month',
                value: Money.format(data.monthRevenueMinor),
                footnote: data.pendingPayments == 0
                    ? null
                    : '${data.pendingPayments} pending',
                colour: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _StatTile(
                icon: Icons.event,
                label: 'Upcoming classes',
                value: '${data.upcomingClasses}',
                colour: theme.colorScheme.primary,
              ),
            ),
          ],
        ),

        if (data.needsAttention > 0) ...[
          const SizedBox(height: 16),
          _NeedsAttentionCard(data: data),
        ],

        const SizedBox(height: 16),
        const _AttendanceTrendCard(),

        const SizedBox(height: 16),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.forum_outlined),
                title: const Text('Member messages'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const FeedbackInboxScreen(),
                  ),
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.sports_outlined),
                title: const Text('Trainers'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const TrainerListScreen(isAdmin: true),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Card(
          child: ListTile(
            leading: const Icon(Icons.assessment_outlined),
            title: const Text('Reports & export'),
            subtitle: const Text('Revenue, attendance, CSV export'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const ReportsScreen()),
            ),
          ),
        ),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.colour,
    this.footnote,
  });

  final IconData icon;
  final String label;
  final String value;
  final String? footnote;
  final Color colour;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: colour),
            const SizedBox(height: 10),
            Text(
              value,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
            if (footnote != null)
              Text(
                footnote!,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.tertiary,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Members whose membership is lapsing or lapsed — the actionable list.
class _NeedsAttentionCard extends ConsumerWidget {
  const _NeedsAttentionCard({required this.data});

  final DashboardSummary data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final members = ref.watch(needsAttentionProvider);

    return Card(
      color: theme.colorScheme.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.notification_important_outlined,
                  size: 20,
                  color: theme.colorScheme.onTertiaryContainer,
                ),
                const SizedBox(width: 8),
                Text(
                  data.expired == 0
                      ? '${data.expiringSoon} expiring soon'
                      : '${data.expiringSoon} expiring, ${data.expired} expired',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.onTertiaryContainer,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            members.when(
              loading: () => const LinearProgressIndicator(),
              error: (error, _) => Text('$error'),
              data: (list) => Column(
                children: [
                  for (final item in list.take(5))
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(item.member.fullName),
                      subtitle: Text(
                        'Expires '
                        '${DateFormat.MMMd().format(item.membership.endDate)}',
                      ),
                      trailing: const Icon(Icons.chevron_right, size: 18),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              MemberDetailScreen(memberId: item.member.id),
                        ),
                      ),
                    ),
                  if (list.length > 5)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        'and ${list.length - 5} more',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onTertiaryContainer,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A simple bar strip of the last two weeks' attendance.
class _AttendanceTrendCard extends ConsumerWidget {
  const _AttendanceTrendCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final trend = ref.watch(attendanceTrendProvider);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Attendance', style: theme.textTheme.titleSmall),
            Text(
              'Last 14 days',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
            const SizedBox(height: 16),

            trend.when(
              loading: () => const SizedBox(
                height: 80,
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (error, _) => Text('$error'),
              data: (points) => _TrendBars(points: points),
            ),
          ],
        ),
      ),
    );
  }
}

class _TrendBars extends StatelessWidget {
  const _TrendBars({required this.points});

  final List<AttendancePoint> points;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final peak = points.fold(
      1,
      (max, p) => p.verified > max ? p.verified : max,
    );

    return SizedBox(
      height: 96,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final point in points)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      point.verified == 0 ? '' : '${point.verified}',
                      style: theme.textTheme.labelSmall,
                    ),
                    const SizedBox(height: 2),
                    Container(
                      height: (point.verified / peak * 56).clamp(2, 56),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      DateFormat.E().format(point.day).substring(0, 1),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
