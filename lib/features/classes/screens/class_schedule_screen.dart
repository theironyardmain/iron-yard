import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_constants.dart';
import '../../../data/local/daos/class_dao.dart';
import '../../auth/providers/auth_providers.dart';
import '../providers/class_providers.dart';
import '../widgets/class_card.dart';
import 'class_form_screen.dart';

/// Weekly class schedule (brain.md §6.8).
///
/// Staff see management actions; members see booking.
class ClassScheduleScreen extends ConsumerStatefulWidget {
  const ClassScheduleScreen({super.key});

  @override
  ConsumerState<ClassScheduleScreen> createState() =>
      _ClassScheduleScreenState();
}

class _ClassScheduleScreenState extends ConsumerState<ClassScheduleScreen> {
  @override
  void initState() {
    super.initState();
    // Subscribed while the schedule is on screen, not app-wide, so the socket
    // stays closed when nobody is looking (brain.md §4).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        ref.read(classRealtimeProvider).subscribe();
      } catch (error) {
        // Realtime is an accelerator; sync still delivers the change.
        debugPrint('Class realtime unavailable: $error');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final schedule = ref.watch(weekScheduleProvider);
    final offset = ref.watch(weekOffsetProvider);
    final role = ref.watch(currentSessionProvider)?.role;
    final isStaff = role == UserRole.admin || role == UserRole.trainer;

    return Scaffold(
      body: Column(
        children: [
          _WeekSelector(offset: offset),
          const _RejectedBookingsBanner(),
          Expanded(
            child: schedule.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) =>
                  Center(child: Text('Could not load schedule: $error')),
              data: (list) => list.isEmpty
                  ? _Empty(isStaff: isStaff)
                  : _ScheduleList(classes: list, isStaff: isStaff),
            ),
          ),
        ],
      ),
      floatingActionButton: isStaff
          ? FloatingActionButton.extended(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const ClassFormScreen(),
                ),
              ),
              icon: const Icon(Icons.add),
              label: const Text('New class'),
            )
          : null,
    );
  }
}

class _WeekSelector extends ConsumerWidget {
  const _WeekSelector({required this.offset});

  final int offset;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final from = startOfWeek(offset);
    final to = from.add(const Duration(days: 6));

    final label = switch (offset) {
      0 => 'This week',
      1 => 'Next week',
      -1 => 'Last week',
      _ =>
        '${DateFormat.MMMd().format(from)} – ${DateFormat.MMMd().format(to)}',
    };

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            tooltip: 'Previous week',
            onPressed: () =>
                ref.read(weekOffsetProvider.notifier).state = offset - 1,
          ),
          Column(
            children: [
              Text(label, style: theme.textTheme.titleSmall),
              if (offset != 0)
                Text(
                  '${DateFormat.MMMd().format(from)} – '
                  '${DateFormat.MMMd().format(to)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            tooltip: 'Next week',
            onPressed: () =>
                ref.read(weekOffsetProvider.notifier).state = offset + 1,
          ),
        ],
      ),
    );
  }
}

/// Tells the member when a queued booking was refused on upload.
class _RejectedBookingsBanner extends ConsumerWidget {
  const _RejectedBookingsBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rejected = ref.watch(rejectedBookingsProvider).valueOrNull ?? const [];
    if (rejected.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            Icons.event_busy,
            size: 20,
            color: theme.colorScheme.onErrorContainer,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              rejected.length == 1
                  ? 'A booking could not be confirmed — the class filled up '
                        'before it synced.'
                  : '${rejected.length} bookings could not be confirmed.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onErrorContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScheduleList extends StatelessWidget {
  const _ScheduleList({required this.classes, required this.isStaff});

  final List<ClassWithBookings> classes;
  final bool isStaff;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Group by day so a full week stays readable.
    final byDay = <String, List<ClassWithBookings>>{};
    for (final item in classes) {
      final key = DateFormat.yMMMEd().format(item.gymClass.startsAt);
      byDay.putIfAbsent(key, () => []).add(item);
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 88),
      children: [
        for (final entry in byDay.entries) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
            child: Text(
              entry.key,
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
          ),
          for (final item in entry.value)
            ClassCard(item: item, isStaff: isStaff),
        ],
      ],
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.isStaff});

  final bool isStaff;

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
              Icons.event_outlined,
              size: 48,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text('No classes this week', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              isStaff
                  ? 'Add one with the button below.'
                  : 'Check another week, or ask at the desk.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
