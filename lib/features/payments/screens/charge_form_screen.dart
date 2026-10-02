import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/utils/money.dart';
import '../../auth/providers/auth_providers.dart';
import '../../members/providers/member_providers.dart';
import '../providers/invoice_providers.dart';
import 'record_payment_screen.dart';

/// Creates an ad-hoc charge — a registration fee, a PT add-on, or a manual
/// late fee (brain.md §6.5). Any of these is just an invoice not tied to a
/// plan renewal; there is no separate late-fee mechanism.
class ChargeFormScreen extends ConsumerStatefulWidget {
  const ChargeFormScreen({
    required this.memberId,
    required this.memberName,
    super.key,
  });

  final String memberId;
  final String memberName;

  @override
  ConsumerState<ChargeFormScreen> createState() => _ChargeFormScreenState();
}

class _ChargeFormScreenState extends ConsumerState<ChargeFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _descriptionController = TextEditingController();
  final _amountController = TextEditingController();
  final _discountController = TextEditingController();

  DiscountKind? _discountKind;
  DateTime? _dueDate;
  bool _saving = false;

  @override
  void dispose() {
    _descriptionController.dispose();
    _amountController.dispose();
    _discountController.dispose();
    super.dispose();
  }

  int get _subtotalMinor => Money.parse(_amountController.text) ?? 0;

  int get _discountMinor {
    final kind = _discountKind;
    final value = int.tryParse(_discountController.text.trim());
    if (kind == null || value == null) return 0;
    final resolved = switch (kind) {
      DiscountKind.flat => Money.parse(_discountController.text) ?? 0,
      DiscountKind.percent => (_subtotalMinor * value / 100).round(),
    };
    return resolved.clamp(0, _subtotalMinor);
  }

  Future<void> _pickDueDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueDate ?? now,
      firstDate: now.subtract(const Duration(days: 1)),
      lastDate: DateTime(now.year + 2),
      helpText: 'Due date',
    );
    if (picked != null) setState(() => _dueDate = picked);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final amountMinor = Money.parse(_amountController.text);
    if (amountMinor == null) return;

    setState(() => _saving = true);

    final session = ref.read(currentSessionProvider);
    final description = _descriptionController.text.trim();

    final invoiceId = await ref
        .read(invoiceRepositoryProvider)
        .createAdHocCharge(
          memberId: widget.memberId,
          description: description,
          amountMinor: amountMinor,
          dueDate: _dueDate,
          createdBy: session?.userId,
        );

    final kind = _discountKind;
    if (kind != null && _discountController.text.trim().isNotEmpty) {
      final rawValue = kind == DiscountKind.percent
          ? int.tryParse(_discountController.text.trim())
          : Money.parse(_discountController.text);
      if (rawValue != null && rawValue > 0) {
        await ref
            .read(invoiceRepositoryProvider)
            .applyDiscount(
              invoiceId: invoiceId,
              discountKind: kind,
              discountValue: rawValue,
            );
      }
    }

    ref.invalidate(invoiceHistoryProvider(widget.memberId));
    ref.invalidate(outstandingInvoicesProvider);
    ref.invalidate(memberOutstandingInvoicesProvider(widget.memberId));
    ref.invalidate(memberBalanceProvider(widget.memberId));
    ref.invalidate(memberSummaryProvider(widget.memberId));

    if (!mounted) return;

    // Offer to record a payment against the new charge immediately — the
    // common case (registration fee paid on the spot) shouldn't need a
    // separate trip back into the member's invoice list.
    final recordNow = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Charge created'),
        content: Text('Record a payment for "$description" now?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Not yet'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Record payment'),
          ),
        ],
      ),
    );

    if (!mounted) return;
    Navigator.of(context).pop();

    if (recordNow == true && mounted) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => RecordPaymentScreen(
            memberId: widget.memberId,
            memberName: widget.memberName,
            invoiceId: invoiceId,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtotal = _subtotalMinor;
    final discount = _discountMinor;
    final total = (subtotal - discount).clamp(0, subtotal);

    return Scaffold(
      appBar: AppBar(title: const Text('Add charge')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.person_outline),
                      title: Text(widget.memberName),
                      subtitle: const Text('Charged member'),
                    ),
                  ),
                  const SizedBox(height: 16),

                  TextFormField(
                    controller: _descriptionController,
                    decoration: const InputDecoration(
                      labelText: 'Description *',
                      prefixIcon: Icon(Icons.notes_outlined),
                      hintText: 'Registration fee, PT session, late fee…',
                    ),
                    enabled: !_saving,
                    validator: (value) => (value == null || value.trim().isEmpty)
                        ? 'Enter a description'
                        : null,
                  ),
                  const SizedBox(height: 16),

                  TextFormField(
                    controller: _amountController,
                    decoration: const InputDecoration(
                      labelText: 'Amount *',
                      prefixIcon: Icon(Icons.currency_rupee),
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    enabled: !_saving,
                    onChanged: (_) => setState(() {}),
                    validator: (value) {
                      final parsed = Money.parse(value ?? '');
                      if (parsed == null) return 'Enter a valid amount';
                      if (parsed == 0) return 'Amount must be more than zero';
                      return null;
                    },
                  ),
                  const SizedBox(height: 24),

                  Text('Discount (optional)', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      ChoiceChip(
                        label: const Text('None'),
                        selected: _discountKind == null,
                        onSelected: _saving
                            ? null
                            : (_) => setState(() {
                                _discountKind = null;
                                _discountController.clear();
                              }),
                      ),
                      ChoiceChip(
                        label: const Text('Flat amount'),
                        selected: _discountKind == DiscountKind.flat,
                        onSelected: _saving
                            ? null
                            : (_) => setState(() {
                                _discountKind = DiscountKind.flat;
                              }),
                      ),
                      ChoiceChip(
                        label: const Text('Percent'),
                        selected: _discountKind == DiscountKind.percent,
                        onSelected: _saving
                            ? null
                            : (_) => setState(() {
                                _discountKind = DiscountKind.percent;
                              }),
                      ),
                    ],
                  ),
                  if (_discountKind != null) ...[
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _discountController,
                      decoration: InputDecoration(
                        labelText: _discountKind == DiscountKind.percent
                            ? 'Discount %'
                            : 'Discount amount',
                        prefixIcon: Icon(
                          _discountKind == DiscountKind.percent
                              ? Icons.percent
                              : Icons.currency_rupee,
                        ),
                      ),
                      keyboardType: _discountKind == DiscountKind.percent
                          ? TextInputType.number
                          : const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                      enabled: !_saving,
                      onChanged: (_) => setState(() {}),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) return null;
                        if (_discountKind == DiscountKind.percent) {
                          final pct = int.tryParse(value.trim());
                          if (pct == null || pct < 0 || pct > 100) {
                            return 'Enter 0-100';
                          }
                        } else if (Money.parse(value) == null) {
                          return 'Enter a valid amount';
                        }
                        return null;
                      },
                    ),
                  ],

                  if (subtotal > 0 && discount > 0) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.secondaryContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Total after discount',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSecondaryContainer,
                            ),
                          ),
                          Text(
                            Money.format(total),
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: theme.colorScheme.onSecondaryContainer,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 16),
                  InkWell(
                    onTap: _saving ? null : _pickDueDate,
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Due date (optional)',
                        prefixIcon: Icon(Icons.event_outlined),
                      ),
                      child: Text(
                        _dueDate == null
                            ? 'No due date'
                            : '${_dueDate!.year}-${_dueDate!.month.toString().padLeft(2, '0')}-${_dueDate!.day.toString().padLeft(2, '0')}',
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Add charge'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
