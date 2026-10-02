import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/utils/body_metrics.dart';
import '../../../core/utils/money.dart';
import '../../../data/local/daos/membership_dao.dart';
import '../models/member_summary.dart';
import '../providers/member_providers.dart';
import '../../attendance/screens/attendance_history_screen.dart';
import '../../memberships/widgets/assign_plan_sheet.dart';
import '../../payments/providers/invoice_providers.dart';
import '../../payments/screens/charge_form_screen.dart';
import '../../payments/screens/member_payments_screen.dart';
import '../../payments/screens/record_payment_screen.dart';
import '../../plans/screens/my_plans_screen.dart';
import '../../plans/widgets/assign_plan_sheet.dart';
import '../widgets/emergency_contact_sheet.dart';
import '../widgets/member_status_chip.dart';
import 'member_form_screen.dart';

/// Full member profile — details, membership, and emergency contact
/// (brain.md §6.3).
///
/// Attendance and payment history are added by their own phases.
class MemberDetailScreen extends ConsumerWidget {
  const MemberDetailScreen({required this.memberId, super.key});

  final String memberId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(memberSummaryProvider(memberId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Member'),
        actions: [
          summary.maybeWhen(
            data: (member) => member == null
                ? const SizedBox.shrink()
                : Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit_outlined),
                        tooltip: 'Edit',
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) =>
                                MemberFormScreen(member: member.profile),
                          ),
                        ),
                      ),
                      _MemberMenu(member: member),
                    ],
                  ),
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      ),
      body: summary.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Could not load member: $error')),
        data: (member) => member == null
            ? const Center(child: Text('This member no longer exists.'))
            : _MemberBody(member: member),
      ),
    );
  }
}

class _MemberMenu extends ConsumerWidget {
  const _MemberMenu({required this.member});

  final MemberSummary member;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<String>(
      onSelected: (value) async {
        if (value == 'toggle-active') {
          await _confirmToggleActive(context, ref);
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'toggle-active',
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              member.isActive
                  ? Icons.person_off_outlined
                  : Icons.person_add_alt,
            ),
            title: Text(member.isActive ? 'Deactivate' : 'Reactivate'),
          ),
        ),
      ],
    );
  }

  Future<void> _confirmToggleActive(BuildContext context, WidgetRef ref) async {
    final deactivating = member.isActive;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          deactivating ? 'Deactivate member?' : 'Reactivate member?',
        ),
        content: Text(
          deactivating
              // Deactivation is reversible and preserves history, so say so —
              // otherwise staff avoid a safe action fearing data loss.
              ? '${member.fullName} will no longer be able to check in. '
                    'Their attendance and payment history is kept, and you can '
                    'reactivate them at any time.'
              : '${member.fullName} will be able to check in again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(deactivating ? 'Deactivate' : 'Reactivate'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    await ref
        .read(memberRepositoryProvider)
        .setActive(member.id, isActive: !member.isActive);

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          deactivating ? 'Member deactivated' : 'Member reactivated',
        ),
      ),
    );
  }
}

class _MemberBody extends ConsumerWidget {
  const _MemberBody({required this.member});

  final MemberSummary member;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final contact = ref.watch(emergencyContactProvider(member.id));

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Center(
          child: Column(
            children: [
              CircleAvatar(
                radius: 40,
                child: Text(
                  _initials(member.fullName),
                  style: theme.textTheme.headlineSmall,
                ),
              ),
              const SizedBox(height: 12),
              Text(member.fullName, style: theme.textTheme.titleLarge),
              const SizedBox(height: 8),
              MemberStatusChip(
                status: member.status,
                daysRemaining: member.daysRemaining,
                isDeactivated: !member.isActive,
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        _Section(
          title: 'Membership',
          action: TextButton.icon(
            onPressed: () => showAssignPlanSheet(
              context: context,
              memberId: member.id,
              memberName: member.fullName,
            ),
            icon: const Icon(Icons.add, size: 18),
            label: Text(member.membership == null ? 'Assign' : 'Renew'),
          ),
          children: [
            if (member.membership == null)
              const _Row(
                icon: Icons.card_membership_outlined,
                label: 'Plan',
                value: 'No plan assigned',
              )
            else ...[
              _Row(
                icon: Icons.event_available_outlined,
                label: 'Started',
                value: DateFormat.yMMMd().format(member.membership!.startDate),
              ),
              _Row(
                icon: Icons.event_busy_outlined,
                label: 'Expires',
                value: DateFormat.yMMMd().format(member.membership!.endDate),
                emphasis: member.status == MembershipStatus.expired ||
                    member.status == MembershipStatus.expiringSoon,
              ),
            ],
            Consumer(
              builder: (context, ref, _) {
                final balance = ref.watch(memberBalanceProvider(member.id));
                return balance.when(
                  loading: () => const SizedBox.shrink(),
                  error: (_, _) => const SizedBox.shrink(),
                  data: (amountMinor) => amountMinor <= 0
                      ? const SizedBox.shrink()
                      : _Row(
                          icon: Icons.request_quote_outlined,
                          label: 'Balance due',
                          value: Money.format(amountMinor),
                          emphasis: true,
                        ),
                );
              },
            ),
          ],
        ),

        _Section(
          title: 'Contact',
          children: [
            _Row(
              icon: Icons.phone_outlined,
              label: 'Phone',
              value: member.phone ?? '—',
            ),
            _Row(
              icon: Icons.mail_outline,
              label: 'Email',
              value: member.email ?? '—',
            ),
            _Row(
              icon: Icons.home_outlined,
              label: 'Address',
              value: member.profile.address ?? '—',
            ),
          ],
        ),

        _Section(
          title: 'Details',
          children: [
            _Row(
              icon: Icons.cake_outlined,
              label: 'Date of birth',
              value: member.profile.dateOfBirth == null
                  ? '—'
                  : DateFormat.yMMMd().format(member.profile.dateOfBirth!),
            ),
            _Row(
              icon: Icons.wc_outlined,
              label: 'Gender',
              value: member.profile.gender ?? '—',
            ),
            _Row(
              icon: Icons.height_outlined,
              label: 'Height',
              value: member.profile.heightCm == null
                  ? '—'
                  : '${member.profile.heightCm} cm',
            ),
            _Row(
              icon: Icons.monitor_weight_outlined,
              label: 'Weight',
              value: member.profile.weightKg == null
                  ? '—'
                  : '${member.profile.weightKg} kg',
            ),
            Builder(
              builder: (context) {
                final bmi = BodyMetrics.bmi(
                  weightKg: member.profile.weightKg,
                  heightCm: member.profile.heightCm,
                );
                if (bmi == null) return const SizedBox.shrink();
                return _Row(
                  icon: Icons.monitor_heart_outlined,
                  label: 'BMI',
                  value:
                      '${bmi.toStringAsFixed(1)} (${BodyMetrics.bmiCategory(bmi)})',
                );
              },
            ),
            _Row(
              icon: Icons.event_outlined,
              label: 'Joined',
              value: member.profile.joinedAt == null
                  ? '—'
                  : DateFormat.yMMMd().format(member.profile.joinedAt!),
            ),
          ],
        ),

        _Section(
          title: 'Emergency contact',
          // Stored on this device only and never synced (brain.md §6.2).
          subtitle: 'Stored on this device only',
          action: TextButton.icon(
            onPressed: () => showEmergencyContactSheet(
              context: context,
              ref: ref,
              memberId: member.id,
              existing: contact.valueOrNull,
            ),
            icon: const Icon(Icons.edit_outlined, size: 18),
            label: Text(contact.valueOrNull == null ? 'Add' : 'Edit'),
          ),
          children: [
            contact.when(
              loading: () => const _Row(
                icon: Icons.contact_emergency_outlined,
                label: 'Contact',
                value: 'Loading…',
              ),
              error: (e, _) => _Row(
                icon: Icons.error_outline,
                label: 'Contact',
                value: 'Could not load ($e)',
              ),
              data: (value) => value == null
                  ? const _Row(
                      icon: Icons.contact_emergency_outlined,
                      label: 'Contact',
                      value: 'Not set',
                    )
                  : Column(
                      children: [
                        _Row(
                          icon: Icons.contact_emergency_outlined,
                          label: value.relationship ?? 'Contact',
                          value: value.name,
                        ),
                        _Row(
                          icon: Icons.phone_in_talk_outlined,
                          label: 'Phone',
                          value: value.phone,
                        ),
                      ],
                    ),
            ),
          ],
        ),

        if (member.profile.notes?.isNotEmpty == true)
          _Section(
            title: 'Staff notes',
            subtitle: 'Not shown to the member',
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Text(
                  member.profile.notes!,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ],
          ),

        const SizedBox(height: 8),
        Card(
          child: ListTile(
            leading: const Icon(Icons.history_outlined),
            title: const Text('Attendance history'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => AttendanceHistoryScreen(
                  memberId: member.id,
                  title: member.fullName,
                ),
              ),
            ),
          ),
        ),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.receipt_long_outlined),
                title: const Text('Invoices'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => Scaffold(
                      appBar: AppBar(title: Text(member.fullName)),
                      body: _MemberInvoiceList(memberId: member.id),
                    ),
                  ),
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.payments_outlined),
                title: const Text('Payment history'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => MemberPaymentsScreen(
                      memberId: member.id,
                      memberName: member.fullName,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.fitness_center_outlined),
                title: const Text('Training plans'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => Scaffold(
                      appBar: AppBar(title: Text(member.fullName)),
                      body: MyPlansScreen(memberId: member.id),
                    ),
                  ),
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.all(8),
                child: Row(
                  children: [
                    Expanded(
                      child: TextButton.icon(
                        onPressed: () => showAssignTemplateSheet(
                          context: context,
                          memberId: member.id,
                          memberName: member.fullName,
                          kind: PlanKind.workout,
                        ),
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('Workout'),
                      ),
                    ),
                    Expanded(
                      child: TextButton.icon(
                        onPressed: () => showAssignTemplateSheet(
                          context: context,
                          memberId: member.id,
                          memberName: member.fullName,
                          kind: PlanKind.diet,
                        ),
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('Diet'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Consumer(
                builder: (context, ref, _) {
                  final outstanding = ref.watch(
                    memberOutstandingInvoicesProvider(member.id),
                  );
                  return FilledButton.icon(
                    onPressed: () async {
                      final invoices = outstanding.valueOrNull;
                      final invoiceId = (invoices != null && invoices.isNotEmpty)
                          ? invoices.first.id
                          : null;
                      await Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => RecordPaymentScreen(
                            memberId: member.id,
                            memberName: member.fullName,
                            invoiceId: invoiceId,
                            membershipId: member.membership?.id,
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('Record payment'),
                  );
                },
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ChargeFormScreen(
                    memberId: member.id,
                    memberName: member.fullName,
                  ),
                ),
              ),
              icon: const Icon(Icons.request_quote_outlined),
              label: const Text('Add charge'),
            ),
          ],
        ),
      ],
    );
  }

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.children,
    this.subtitle,
    this.action,
  });

  final String title;
  final String? subtitle;
  final Widget? action;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: theme.textTheme.titleSmall),
                        if (subtitle != null)
                          Text(
                            subtitle!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.outline,
                            ),
                          ),
                      ],
                    ),
                  ),
                  ?action,
                ],
              ),
            ),
            ...children,
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

/// A member's invoices, any status — plan charges and ad-hoc fees alike.
class _MemberInvoiceList extends ConsumerWidget {
  const _MemberInvoiceList({required this.memberId});

  final String memberId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final invoices = ref.watch(invoiceHistoryProvider(memberId));
    final theme = Theme.of(context);

    return invoices.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(child: Text('Could not load: $error')),
      data: (list) {
        if (list.isEmpty) {
          return Center(
            child: Text('No invoices yet', style: theme.textTheme.titleMedium),
          );
        }
        return ListView.builder(
          itemCount: list.length,
          itemBuilder: (context, index) {
            final invoice = list[index];
            final remaining = invoice.totalMinor - invoice.amountPaidMinor;
            return ListTile(
              leading: CircleAvatar(
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
                child: Icon(
                  invoice.status == 'paid'
                      ? Icons.check_circle_outline
                      : invoice.status == 'void'
                      ? Icons.block_outlined
                      : Icons.receipt_long_outlined,
                  size: 20,
                  color: theme.colorScheme.outline,
                ),
              ),
              title: Text(invoice.description ?? 'Charge'),
              subtitle: Text(
                InvoiceStatus.fromString(invoice.status)?.label ??
                    invoice.status,
              ),
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    Money.format(invoice.totalMinor),
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (invoice.status == 'unpaid' || invoice.status == 'partial')
                    Text(
                      '${Money.format(remaining)} due',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.icon,
    required this.label,
    required this.value,
    this.emphasis = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.outline),
          const SizedBox(width: 12),
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: emphasis ? FontWeight.w600 : null,
                color: emphasis ? theme.colorScheme.error : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
