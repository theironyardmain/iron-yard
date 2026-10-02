import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../data/local/daos/attendance_dao.dart';
import '../../auth/providers/auth_providers.dart';
import '../providers/checkin_providers.dart';

/// The lightweight "did you go to the gym?" form (brain.md §6.7).
///
/// Deliberately small: two times and a confirm. Anything longer and a member
/// stops bothering.
Future<bool> showCheckInSheet(BuildContext context) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (context) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: const _CheckInForm(),
    ),
  );

  return result ?? false;
}

class _CheckInForm extends ConsumerStatefulWidget {
  const _CheckInForm();

  @override
  ConsumerState<_CheckInForm> createState() => _CheckInFormState();
}

class _CheckInFormState extends ConsumerState<_CheckInForm> {
  late TimeOfDay _startedAt;
  TimeOfDay? _endedAt;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();

    // Both default to now. An "hour ago" default would be one tap less in the
    // common case, but just after midnight it silently files the session under
    // yesterday — the times are always interpreted as today's date.
    final now = DateTime.now();
    _startedAt = TimeOfDay(hour: now.hour, minute: now.minute);
    _endedAt = TimeOfDay(hour: now.hour, minute: now.minute);
  }

  Future<void> _pickTime({required bool isStart}) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: isStart ? _startedAt : (_endedAt ?? _startedAt),
      helpText: isStart ? 'Started at' : 'Finished at',
    );

    if (picked == null) return;
    setState(() {
      if (isStart) {
        _startedAt = picked;
      } else {
        _endedAt = picked;
      }
      _error = null;
    });
  }

  DateTime _toDateTime(TimeOfDay time) {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day, time.hour, time.minute);
  }

  Future<void> _save() async {
    final memberId = ref.read(currentSessionProvider)?.userId;
    if (memberId == null) return;

    final start = _toDateTime(_startedAt);
    final end = _endedAt == null ? null : _toDateTime(_endedAt!);

    if (end != null && !end.isAfter(start)) {
      setState(() => _error = 'Finish time must be after the start time.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    final result = await ref.read(checkInRepositoryProvider).logSession(
      memberId: memberId,
      startedAt: start,
      endedAt: end,
    );

    ref.invalidate(todaysCheckInProvider);

    if (!mounted) return;

    if (result == CheckInResult.duplicate) {
      // Most likely a staff scan already recorded today, which outranks this.
      setState(() {
        _saving = false;
        _error = 'Today is already recorded.';
      });
      return;
    }

    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Log your session', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            DateFormat.yMMMEd().format(DateTime.now()),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
          const SizedBox(height: 20),

          Row(
            children: [
              Expanded(
                child: _TimeField(
                  label: 'Started',
                  value: _startedAt,
                  enabled: !_saving,
                  onTap: () => _pickTime(isStart: true),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _TimeField(
                  label: 'Finished',
                  value: _endedAt,
                  enabled: !_saving,
                  onTap: () => _pickTime(isStart: false),
                  onClear: _endedAt == null
                      ? null
                      : () => setState(() => _endedAt = null),
                ),
              ),
            ],
          ),

          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ],

          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline,
                  size: 18,
                  color: theme.colorScheme.outline,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    // Say plainly what this is: the member should not think a
                    // self-report substitutes for being scanned in.
                    'This is your own record. Staff scans remain the gym\'s '
                    'official attendance.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Save session'),
          ),
        ],
      ),
    );
  }
}

class _TimeField extends StatelessWidget {
  const _TimeField({
    required this.label,
    required this.value,
    required this.enabled,
    required this.onTap,
    this.onClear,
  });

  final String label;
  final TimeOfDay? value;
  final bool enabled;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enabled ? onTap : null,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          suffixIcon: onClear == null
              ? null
              : IconButton(
                  icon: const Icon(Icons.clear, size: 18),
                  onPressed: enabled ? onClear : null,
                  tooltip: 'Clear',
                ),
        ),
        child: Text(value == null ? 'Not set' : value!.format(context)),
      ),
    );
  }
}
