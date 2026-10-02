import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/money.dart';
import '../../../data/local/database.dart';
import '../../../shared/providers/database_provider.dart';
import '../providers/membership_providers.dart';
import 'plan_form_screen.dart';

/// Manage membership plans (brain.md §6.3).
class PlanListScreen extends ConsumerWidget {
  const PlanListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plans = ref.watch(allPlansProvider);

    return Scaffold(
      body: plans.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Could not load plans: $error')),
        data: (list) {
          if (list.isEmpty) return const _EmptyPlans();

          final active = list.where((p) => p.isActive).toList();
          final retired = list.where((p) => !p.isActive).toList();

          return ListView(
            padding: const EdgeInsets.only(bottom: 88),
            children: [
              for (final plan in active) _PlanTile(plan: plan),
              if (retired.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
                  child: Text(
                    'Retired',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: Theme.of(context).colorScheme.outline,
                    ),
                  ),
                ),
                for (final plan in retired) _PlanTile(plan: plan),
              ],
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const PlanFormScreen()),
        ),
        icon: const Icon(Icons.add),
        label: const Text('New plan'),
      ),
    );
  }
}

class _PlanTile extends ConsumerWidget {
  const _PlanTile({required this.plan});

  final MembershipPlan plan;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final usage = ref.watch(planUsageProvider(plan.id));

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        title: Text(
          plan.name,
          style: plan.isActive
              ? null
              : TextStyle(color: theme.colorScheme.outline),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
              '${Money.format(plan.priceMinor)} · '
              '${formatDuration(plan.durationDays)}',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: plan.isActive ? theme.colorScheme.primary : null,
              ),
            ),
            if (plan.description?.isNotEmpty == true) ...[
              const SizedBox(height: 4),
              Text(plan.description!, style: theme.textTheme.bodySmall),
            ],
            usage.maybeWhen(
              data: (count) => count == 0
                  ? const SizedBox.shrink()
                  : Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        count == 1 ? '1 member' : '$count memberships',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.outline,
                        ),
                      ),
                    ),
              orElse: () => const SizedBox.shrink(),
            ),
          ],
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (value) async {
            switch (value) {
              case 'edit':
                await Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => PlanFormScreen(plan: plan),
                  ),
                );
                ref.invalidate(allPlansProvider);
              case 'toggle':
                await _confirmToggle(context, ref);
            }
          },
          itemBuilder: (context) => [
            const PopupMenuItem(value: 'edit', child: Text('Edit')),
            PopupMenuItem(
              value: 'toggle',
              child: Text(plan.isActive ? 'Retire plan' : 'Restore plan'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmToggle(BuildContext context, WidgetRef ref) async {
    final retiring = plan.isActive;
    final count = await ref.read(planUsageProvider(plan.id).future);

    if (!context.mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(retiring ? 'Retire this plan?' : 'Restore this plan?'),
        content: Text(
          retiring
              // Say what does *not* happen — staff otherwise assume retiring a
              // plan cancels the memberships on it.
              ? '${plan.name} will no longer be offered to new members.\n\n'
                    '${count == 0 ? 'No members are on this plan.' : count == 1 ? 'The 1 existing membership on it keeps its expiry date.' : 'The $count existing memberships on it keep their expiry dates.'}'
              : '${plan.name} will be offered to new members again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(retiring ? 'Retire' : 'Restore'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    await ref
        .read(membershipDaoProvider)
        .setPlanActive(plan.id, isActive: !plan.isActive);
    ref.invalidate(allPlansProvider);
  }
}

class _EmptyPlans extends StatelessWidget {
  const _EmptyPlans();

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
              Icons.card_membership_outlined,
              size: 48,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text('No plans yet', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Create a plan before assigning memberships.',
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
