import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../data/local/daos/class_dao.dart';
import '../../auth/providers/auth_providers.dart';
import '../providers/class_providers.dart';
import '../screens/class_form_screen.dart';

/// One class in the schedule, with the action appropriate to the viewer
/// (brain.md §6.8).
class ClassCard extends ConsumerWidget {
  const ClassCard({required this.item, required this.isStaff, super.key});

  final ClassWithBookings item;
  final bool isStaff;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final gymClass = item.gymClass;

    final timeRange =
        '${DateFormat.jm().format(gymClass.startsAt)} – '
        '${DateFormat.jm().format(gymClass.endsAt)}';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: item.isCancelled ? theme.colorScheme.surfaceContainerHighest : null,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        gymClass.name,
                        style: theme.textTheme.titleMedium?.copyWith(
                          decoration: item.isCancelled
                              ? TextDecoration.lineThrough
                              : null,
                          color: item.isCancelled
                              ? theme.colorScheme.outline
                              : null,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        gymClass.location?.isNotEmpty == true
                            ? '$timeRange · ${gymClass.location}'
                            : timeRange,
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                if (isStaff) _StaffMenu(item: item),
              ],
            ),

            if (gymClass.description?.isNotEmpty == true) ...[
              const SizedBox(height: 6),
              Text(gymClass.description!, style: theme.textTheme.bodySmall),
            ],

            const SizedBox(height: 10),
            Row(
              children: [
                _CapacityChip(item: item),
                const Spacer(),
                if (!isStaff) _BookingAction(item: item),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CapacityChip extends StatelessWidget {
  const _CapacityChip({required this.item});

  final ClassWithBookings item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final (label, colour) = item.isCancelled
        ? ('Cancelled', scheme.error)
        : item.isFull
        ? ('Full', scheme.error)
        : item.spacesLeft == 1
        ? ('1 space left', scheme.tertiary)
        : ('${item.spacesLeft} spaces', scheme.outline);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          item.isCancelled ? Icons.event_busy : Icons.people_outline,
          size: 16,
          color: colour,
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(color: colour),
        ),
        const SizedBox(width: 8),
        Text(
          '${item.bookedCount}/${item.gymClass.capacity}',
          style: theme.textTheme.labelSmall?.copyWith(color: scheme.outline),
        ),
      ],
    );
  }
}

class _BookingAction extends ConsumerStatefulWidget {
  const _BookingAction({required this.item});

  final ClassWithBookings item;

  @override
  ConsumerState<_BookingAction> createState() => _BookingActionState();
}

class _BookingActionState extends ConsumerState<_BookingAction> {
  bool _busy = false;

  Future<void> _book() async {
    final memberId = ref.read(currentSessionProvider)?.userId;
    if (memberId == null) return;

    setState(() => _busy = true);

    final result = await ref.read(classDaoProvider).book(
      classId: widget.item.gymClass.id,
      memberId: memberId,
    );

    ref.invalidate(weekScheduleProvider);

    if (!mounted) return;
    setState(() => _busy = false);

    final message = switch (result) {
      // Deliberately provisional: the server decides on upload, so promising
      // a confirmed place here would be a lie if the class filled up.
      BookingResult.booked => 'Booked — confirmed once synced',
      BookingResult.alreadyBooked => 'You are already booked',
      BookingResult.full => 'That class is full',
      BookingResult.cancelled => 'That class has been cancelled',
      BookingResult.past => 'That class has already started',
    };

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _cancel() async {
    final memberId = ref.read(currentSessionProvider)?.userId;
    if (memberId == null) return;

    setState(() => _busy = true);

    await ref.read(classDaoProvider).cancelBooking(
      classId: widget.item.gymClass.id,
      memberId: memberId,
    );

    ref.invalidate(weekScheduleProvider);

    if (!mounted) return;
    setState(() => _busy = false);

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Booking cancelled')));
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;

    if (item.isCancelled) return const SizedBox.shrink();

    if (_busy) {
      return const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }

    if (item.hasStarted) {
      return Text(
        item.isBookedByMe ? 'Attended' : 'Passed',
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: Theme.of(context).colorScheme.outline,
        ),
      );
    }

    if (item.isBookedByMe) {
      return TextButton.icon(
        onPressed: _cancel,
        icon: const Icon(Icons.check_circle, size: 18),
        label: const Text('Booked'),
      );
    }

    return FilledButton.tonal(
      onPressed: item.isFull ? null : _book,
      child: Text(item.isFull ? 'Full' : 'Book'),
    );
  }
}

class _StaffMenu extends ConsumerWidget {
  const _StaffMenu({required this.item});

  final ClassWithBookings item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<String>(
      onSelected: (value) async {
        final dao = ref.read(classDaoProvider);

        switch (value) {
          case 'edit':
            await Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => ClassFormScreen(gymClass: item.gymClass),
              ),
            );
          case 'cancel':
            await _confirmCancel(context, ref);
          case 'restore':
            await dao.restoreClass(item.gymClass.id);
        }

        ref.invalidate(weekScheduleProvider);
      },
      itemBuilder: (context) => [
        const PopupMenuItem(value: 'edit', child: Text('Edit')),
        if (item.isCancelled)
          const PopupMenuItem(value: 'restore', child: Text('Restore'))
        else
          const PopupMenuItem(value: 'cancel', child: Text('Cancel class')),
      ],
    );
  }

  Future<void> _confirmCancel(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel this class?'),
        content: Text(
          item.bookedCount == 0
              ? 'No one has booked this class.'
              // Bookings are kept so members see the cancellation rather than
              // finding the class silently gone.
              : '${item.bookedCount} '
                    '${item.bookedCount == 1 ? 'member has' : 'members have'} '
                    'booked. They keep their booking and will see the class '
                    'marked cancelled.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep it'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Cancel class'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    await ref.read(classDaoProvider).cancelClass(item.gymClass.id);
  }
}
