import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/utils/money.dart';
import '../../auth/providers/auth_providers.dart';
import '../../members/providers/member_providers.dart';
import '../data/payment_repository.dart';
import '../providers/invoice_providers.dart';
import '../providers/payment_providers.dart';
import '../widgets/receipt_preview.dart';

/// Records a manual payment (brain.md §6.5 — no gateway in v1).
///
/// When [invoiceId] is given, the payment settles that invoice: the amount
/// field is capped at the remaining balance and supports paying it off in
/// installments. Without one, this falls back to the legacy free-floating
/// record, kept for payments that predate invoicing.
class RecordPaymentScreen extends ConsumerStatefulWidget {
  const RecordPaymentScreen({
    required this.memberId,
    required this.memberName,
    this.invoiceId,
    this.suggestedAmountMinor,
    this.membershipId,
    super.key,
  });

  final String memberId;
  final String memberName;

  /// The invoice this payment settles. When null, the payment is recorded
  /// free-floating (the legacy pre-invoicing behaviour).
  final String? invoiceId;

  /// Prefilled amount when there is no invoice to read a balance from.
  final int? suggestedAmountMinor;
  final String? membershipId;

  @override
  ConsumerState<RecordPaymentScreen> createState() =>
      _RecordPaymentScreenState();
}

class _RecordPaymentScreenState extends ConsumerState<RecordPaymentScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _notesController = TextEditingController();

  PaymentMethod _method = PaymentMethod.cash;
  DateTime _paidAt = DateTime.now();
  bool _pending = false;
  String? _receiptPath;
  bool _saving = false;
  bool _prefilled = false;

  @override
  void dispose() {
    _amountController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  /// Fills the amount field with the suggested/remaining amount once, the
  /// first time it becomes known — an invoice's balance loads asynchronously,
  /// while a plain suggestion is available immediately.
  void _prefillOnce(int amountMinor) {
    if (_prefilled) return;
    _prefilled = true;
    _amountController.text = Money.toInput(amountMinor);
  }

  Future<void> _pickReceipt(ImageSource source) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: source,
      // Receipts only need to be legible, not archival. Capping the size keeps
      // the upload small on a weak gym connection.
      maxWidth: 1600,
      imageQuality: 80,
    );

    if (picked == null || !mounted) return;
    setState(() => _receiptPath = picked.path);
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _paidAt,
      firstDate: DateTime(now.year - 2),
      // Payments cannot be dated in the future: this records money already
      // received.
      lastDate: now,
      helpText: 'Payment date',
    );

    if (picked != null) setState(() => _paidAt = picked);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final amountMinor = Money.parse(_amountController.text);
    if (amountMinor == null) return;

    setState(() => _saving = true);

    final session = ref.read(currentSessionProvider);
    final notes = _notesController.text.trim();
    final invoiceId = widget.invoiceId;

    try {
      if (invoiceId != null) {
        await ref.read(paymentRepositoryProvider).applyPayment(
          invoiceId: invoiceId,
          amountMinor: amountMinor,
          method: _method,
          paidAt: _paidAt,
          notes: notes.isEmpty ? null : notes,
          recordedBy: session?.userId,
          receiptSourcePath: _receiptPath,
          pending: _pending,
        );
        ref.invalidate(invoiceByIdProvider(invoiceId));
        ref.invalidate(invoiceHistoryProvider(widget.memberId));
        ref.invalidate(outstandingInvoicesProvider);
        ref.invalidate(memberOutstandingInvoicesProvider(widget.memberId));
      } else {
        await ref.read(paymentRepositoryProvider).record(
          memberId: widget.memberId,
          amountMinor: amountMinor,
          method: _method,
          membershipId: widget.membershipId,
          paidAt: _paidAt,
          notes: notes.isEmpty ? null : notes,
          recordedBy: session?.userId,
          receiptSourcePath: _receiptPath,
          pending: _pending,
        );
      }
    } on StateError catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
      return;
    }

    ref.invalidate(pendingPaymentsProvider);
    ref.invalidate(memberSummaryProvider(widget.memberId));
    ref.invalidate(memberBalanceProvider(widget.memberId));

    if (!mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${Money.format(amountMinor)} recorded for ${widget.memberName}',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final invoiceId = widget.invoiceId;

    if (invoiceId == null) {
      if (widget.suggestedAmountMinor != null) {
        _prefillOnce(widget.suggestedAmountMinor!);
      }
      return _buildForm(context, theme, remainingMinor: null);
    }

    final invoice = ref.watch(invoiceByIdProvider(invoiceId));
    return invoice.when(
      loading: () => Scaffold(
        appBar: AppBar(title: const Text('Record payment')),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => Scaffold(
        appBar: AppBar(title: const Text('Record payment')),
        body: Center(child: Text('Could not load invoice: $error')),
      ),
      data: (value) {
        if (value == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Record payment')),
            body: const Center(child: Text('This invoice no longer exists.')),
          );
        }
        final remaining = value.totalMinor - value.amountPaidMinor;
        _prefillOnce(remaining);
        return _buildForm(
          context,
          theme,
          remainingMinor: remaining,
          invoiceDescription: value.description,
        );
      },
    );
  }

  Widget _buildForm(
    BuildContext context,
    ThemeData theme, {
    required int? remainingMinor,
    String? invoiceDescription,
  }) {
    return Scaffold(
      appBar: AppBar(title: const Text('Record payment')),
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
                      subtitle: Text(invoiceDescription ?? 'Paying member'),
                      trailing: remainingMinor == null
                          ? null
                          : Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  'Balance due',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: theme.colorScheme.outline,
                                  ),
                                ),
                                Text(
                                  Money.format(remainingMinor),
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  TextFormField(
                    controller: _amountController,
                    decoration: InputDecoration(
                      labelText: 'Amount *',
                      prefixIcon: const Icon(Icons.currency_rupee),
                      helperText: remainingMinor == null
                          ? null
                          : 'Pay in full or part — the balance carries over',
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    enabled: !_saving,
                    validator: (value) {
                      final parsed = Money.parse(value ?? '');
                      if (parsed == null) return 'Enter a valid amount';
                      if (parsed == 0) return 'Amount must be more than zero';
                      if (!_pending &&
                          remainingMinor != null &&
                          parsed > remainingMinor) {
                        return 'Cannot exceed the balance due '
                            '(${Money.format(remainingMinor)})';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 24),

                  Text('Method', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final method in PaymentMethod.values)
                        ChoiceChip(
                          label: Text(method.label),
                          selected: _method == method,
                          onSelected: _saving
                              ? null
                              : (_) => setState(() => _method = method),
                        ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  InkWell(
                    onTap: _saving ? null : _pickDate,
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Payment date',
                        prefixIcon: Icon(Icons.event_outlined),
                      ),
                      child: Text(DateFormat.yMMMd().format(_paidAt)),
                    ),
                  ),
                  const SizedBox(height: 16),

                  if (PaymentRepository.supportsReceipts)
                    ReceiptPreview(
                      path: _receiptPath,
                      enabled: !_saving,
                      onCapture: () => _pickReceipt(ImageSource.camera),
                      onPick: () => _pickReceipt(ImageSource.gallery),
                      onRemove: () => setState(() => _receiptPath = null),
                    )
                  else
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            Icon(
                              Icons.photo_camera_outlined,
                              size: 20,
                              color: theme.colorScheme.outline,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Receipt photos need the Android app.',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.outline,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: 16),

                  TextFormField(
                    controller: _notesController,
                    decoration: const InputDecoration(
                      labelText: 'Notes',
                      prefixIcon: Icon(Icons.notes_outlined),
                      hintText: 'Reference number, part payment…',
                    ),
                    maxLines: 2,
                    enabled: !_saving,
                  ),
                  const SizedBox(height: 8),

                  SwitchListTile(
                    value: _pending,
                    onChanged: _saving
                        ? null
                        : (value) => setState(() => _pending = value),
                    title: const Text('Mark as pending'),
                    subtitle: const Text(
                      'Money not received yet — excluded from revenue',
                    ),
                    contentPadding: EdgeInsets.zero,
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
                        : const Text('Record payment'),
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
