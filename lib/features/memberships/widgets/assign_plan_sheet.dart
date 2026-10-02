import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/utils/money.dart';
import '../../../data/local/database.dart';
import '../../../shared/providers/database_provider.dart';
import '../../members/providers/member_providers.dart';
import '../../payments/providers/invoice_providers.dart';
import '../providers/membership_providers.dart';

/// Assigns a plan to a member, or renews their current one (brain.md §6.3).
Future<void> showAssignPlanSheet({
  required BuildContext context,
  required String memberId,
  required String memberName,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: _AssignPlanForm(memberId: memberId, memberName: memberName),
    ),
  );
}

class _AssignPlanForm extends ConsumerStatefulWidget {
  const _AssignPlanForm({required this.memberId, required this.memberName});

  final String memberId;
  final String memberName;

  @override
  ConsumerState<_AssignPlanForm> createState() => _AssignPlanFormState();
}

class _AssignPlanFormState extends ConsumerState<_AssignPlanForm> {
  String? _selectedPlanId;
  bool _saving = false;
  Membership? _current;
  bool _loadedCurrent = false;

  @override
  void initState() {
    super.initState();
    _loadCurrent();
  }

  Future<void> _loadCurrent() async {
    final current = await ref
        .read(membershipDaoProvider)
        .currentFor(widget.memberId);
    if (!mounted) return;
    setState(() {
      _current = current;
      _loadedCurrent = true;
    });
  }

  /// Whether this would extend an unexpired membership rather than start fresh.
  bool get _isRenewal {
    final current = _current;
    if (current == null || current.status != 'active') return false;
    final end = DateTime(
      current.endDate.year,
      current.endDate.month,
      current.endDate.day,
    );
    final today = DateTime.now();
    return !end.isBefore(DateTime(today.year, today.month, today.day));
  }

  Future<void> _assign() async {
    final planId = _selectedPlanId;
    if (planId == null) return;

    setState(() => _saving = true);

    // renew() continues from the current expiry when one is still running, so
    // a member renewing early keeps their remaining days. It also creates the
    // invoice charging for this term (brain.md §6.5).
    await ref
        .read(membershipRepositoryProvider)
        .renew(memberId: widget.memberId, planId: planId);

    ref.invalidate(membershipHistoryProvider(widget.memberId));
    ref.invalidate(memberSummaryProvider(widget.memberId));
    ref.invalidate(expiringMembershipsProvider);
    ref.invalidate(memberBalanceProvider(widget.memberId));
    ref.invalidate(memberOutstandingInvoicesProvider(widget.memberId));

    if (!mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _isRenewal
              ? '${widget.memberName} renewed — an invoice was created'
              : 'Plan assigned to ${widget.memberName} — an invoice was created',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final plans = ref.watch(activePlansProvider);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _isRenewal ? 'Renew membership' : 'Assign a plan',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            widget.memberName,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),

          if (_loadedCurrent && _isRenewal) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.secondaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 20,
                    color: theme.colorScheme.onSecondaryContainer,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Current membership runs to '
                      '${DateFormat.yMMMd().format(_current!.endDate)}. '
                      'The new term starts the day after, so no days are lost.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSecondaryContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 20),

          plans.when(
            loading: () => const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(),
              ),
            ),
            error: (error, _) => Text('Could not load plans: $error'),
            data: (list) {
              if (list.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Column(
                    children: [
                      Icon(
                        Icons.card_membership_outlined,
                        size: 40,
                        color: theme.colorScheme.outline,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'No active plans',
                        style: theme.textTheme.titleSmall,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Create a plan first, under Plans.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.outline,
                        ),
                      ),
                    ],
                  ),
                );
              }

              return RadioGroup<String>(
                groupValue: _selectedPlanId,
                onChanged: (value) {
                  if (_saving) return;
                  setState(() => _selectedPlanId = value);
                },
                child: Column(
                  children: [
                    for (final plan in list)
                      RadioListTile<String>(
                        value: plan.id,
                        enabled: !_saving,
                        title: Text(plan.name),
                        subtitle: Text(
                          '${Money.format(plan.priceMinor)} · '
                          '${formatDuration(plan.durationDays)}',
                        ),
                        secondary: _selectedPlanId == plan.id
                            ? _ExpiryPreview(
                                plan: plan,
                                current: _isRenewal ? _current : null,
                              )
                            : null,
                      ),
                  ],
                ),
              );
            },
          ),

          const SizedBox(height: 16),
          FilledButton(
            onPressed: (_saving || _selectedPlanId == null) ? null : _assign,
            child: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(_isRenewal ? 'Renew' : 'Assign plan'),
          ),
        ],
      ),
    );
  }
}

/// Shows the expiry date the selected plan would produce.
class _ExpiryPreview extends StatelessWidget {
  const _ExpiryPreview({required this.plan, this.current});

  final MembershipPlan plan;
  final Membership? current;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Mirrors MembershipDao.renew: continue from the current expiry when one
    // is still running, otherwise start today.
    final today = DateTime.now();
    var start = DateTime(today.year, today.month, today.day);

    final currentEnd = current?.endDate;
    if (currentEnd != null) {
      final end = DateTime(currentEnd.year, currentEnd.month, currentEnd.day);
      if (!end.isBefore(start)) {
        start = DateTime(end.year, end.month, end.day + 1);
      }
    }

    final expiry = DateTime(
      start.year,
      start.month,
      start.day + plan.durationDays,
    );

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          'Until',
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.outline,
          ),
        ),
        Text(
          DateFormat.yMMMd().format(expiry),
          style: theme.textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
