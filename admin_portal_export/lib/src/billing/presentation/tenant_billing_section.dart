import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/tenant_billing.dart';
import 'billing_providers.dart';

class TenantBillingSection extends ConsumerWidget {
  final String tenantId;
  const TenantBillingSection({required this.tenantId, super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(billingMutationProvider, (previous, next) {
      if (previous is! AsyncLoading<void>) return;
      final message =
          next.hasError
              ? 'Billing action failed: ${next.error}'
              : 'Billing updated successfully.';
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
    });
    final summary = ref.watch(billingSummaryProvider(tenantId));
    final invoices = ref.watch(billingInvoicesProvider(tenantId));
    final payments = ref.watch(billingPaymentsProvider(tenantId));
    final plans = ref.watch(billingPlansProvider);
    final busy = ref.watch(billingMutationProvider).isLoading;
    final openInvoices =
        invoices.asData?.value
            .where((invoice) => invoice.status == 'open')
            .toList() ??
        const <BillingInvoice>[];
    final pendingInvoiceIds =
        payments.asData?.value
            .where((payment) => payment.status == 'recorded')
            .map((payment) => payment.invoiceId)
            .toSet() ??
        const <String?>{};
    final payableInvoices =
        openInvoices
            .where((invoice) => !pendingInvoiceIds.contains(invoice.id))
            .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Billing & subscription',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
            OutlinedButton.icon(
              onPressed:
                  busy ||
                          openInvoices.isNotEmpty ||
                          plans.asData?.value.isEmpty != false
                      ? null
                      : () => _createInvoice(context, ref, plans.asData!.value),
              icon: const Icon(Icons.receipt_long),
              label: const Text('Create invoice'),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed:
                  busy || payableInvoices.isEmpty
                      ? null
                      : () => _record(context, ref, payableInvoices),
              icon: const Icon(Icons.add_card),
              label: const Text('Record payment'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        summary.when(
          loading: () => const LinearProgressIndicator(),
          error: (e, _) => Text('Could not load billing: $e'),
          data:
              (s) =>
                  s == null
                      ? const Card(
                        child: ListTile(title: Text('No active subscription')),
                      )
                      : Card(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Wrap(
                                spacing: 32,
                                runSpacing: 16,
                                children: [
                                  _Value('Plan', s.plan),
                                  _Value('Status', s.status),
                                  _Value('Billing cycle', s.billingCycle),
                                  _Value(
                                    'Trial',
                                    _range(s.trialStartsAt, s.trialEndsAt),
                                  ),
                                  _Value('Renewal', _date(s.renewalDate)),
                                  _Value('Grace ends', _date(s.graceEndsAt)),
                                  _Value(
                                    'Outstanding',
                                    '${s.currency} ${s.outstandingAmount.toStringAsFixed(2)}',
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children:
                                    _validActions(s.status)
                                        .map(
                                          (a) => OutlinedButton(
                                            onPressed:
                                                busy
                                                    ? null
                                                    : () => _action(
                                                      context,
                                                      ref,
                                                      a,
                                                    ),
                                            child: Text(a.replaceAll('_', ' ')),
                                          ),
                                        )
                                        .toList(),
                              ),
                            ],
                          ),
                        ),
                      ),
        ),
        const SizedBox(height: 20),
        Text('Invoices', style: Theme.of(context).textTheme.titleLarge),
        _asyncList(
          invoices,
          (i) => ListTile(
            title: Text(i.number),
            subtitle: Text(
              '${i.planName ?? 'Legacy invoice'} • ${i.billingCycle ?? '—'} • ${_date(i.issuedAt)} • ${i.status}',
            ),
            trailing: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('${i.currency} ${i.amount.toStringAsFixed(2)}'),
                if (i.status == 'open')
                  IconButton(
                    tooltip: 'Void invoice',
                    onPressed:
                        busy ? null : () => _voidInvoice(context, ref, i),
                    icon: const Icon(Icons.block),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        Text('Payment history', style: Theme.of(context).textTheme.titleLarge),
        _asyncList(
          payments,
          (p) => ListTile(
            title: Text('${p.currency} ${p.amount.toStringAsFixed(2)}'),
            subtitle: Text('${p.method} • ${p.reference} • ${_date(p.paidAt)}'),
            trailing:
                p.status == 'recorded'
                    ? Wrap(
                      children: [
                        IconButton(
                          tooltip: 'Verify',
                          onPressed:
                              busy
                                  ? null
                                  : () => _verify(context, ref, p.id, true),
                          icon: const Icon(Icons.check),
                        ),
                        IconButton(
                          tooltip: 'Reject',
                          onPressed:
                              busy
                                  ? null
                                  : () => _verify(context, ref, p.id, false),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    )
                    : Chip(label: Text(p.status)),
          ),
        ),
      ],
    );
  }

  Widget _asyncList<T>(AsyncValue<List<T>> value, Widget Function(T) row) =>
      value.when(
        loading: () => const LinearProgressIndicator(),
        error: (e, _) => Text('Could not load records: $e'),
        data:
            (items) => Card(
              child: Column(
                children:
                    items.isEmpty
                        ? [const ListTile(title: Text('No records.'))]
                        : items.map(row).toList(),
              ),
            ),
      );
  Future<void> _verify(
    BuildContext context,
    WidgetRef ref,
    String id,
    bool ok,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: Text(ok ? 'Verify payment?' : 'Reject payment?'),
            content: Text(
              ok
                  ? 'This will mark the invoice paid and activate its package.'
                  : 'The invoice will remain open for another payment.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(ok ? 'Verify & activate' : 'Reject'),
              ),
            ],
          ),
    );
    if (confirmed != true) return;
    await ref
        .read(billingMutationProvider.notifier)
        .run(tenantId, (repository) => repository.verify(id, ok));
  }

  Future<void> _voidInvoice(
    BuildContext context,
    WidgetRef ref,
    BillingInvoice invoice,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: const Text('Void invoice?'),
            content: Text('${invoice.number} will no longer accept a payment.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Void'),
              ),
            ],
          ),
    );
    if (confirmed != true) return;
    await ref
        .read(billingMutationProvider.notifier)
        .run(tenantId, (repository) => repository.voidInvoice(invoice.id));
  }

  Future<void> _action(
    BuildContext context,
    WidgetRef ref,
    String action,
  ) async {
    DateTime? until;
    if (['trial_start', 'trial_extend', 'renew', 'grace'].contains(action)) {
      until = await showDatePicker(
        context: context,
        initialDate: DateTime.now().add(const Duration(days: 30)),
        firstDate: DateTime.now(),
        lastDate: DateTime.now().add(const Duration(days: 3650)),
      );
      if (until == null) return;
      until = DateTime(until.year, until.month, until.day, 23, 59, 59, 999);
    }
    await ref
        .read(billingMutationProvider.notifier)
        .run(
          tenantId,
          (r) => r.manage(
            tenantId: tenantId,
            action: action,
            until: until,
            reason: 'Platform admin action',
          ),
        );
  }

  Future<void> _record(
    BuildContext context,
    WidgetRef ref,
    List<BillingInvoice> openInvoices,
  ) async {
    var invoice = openInvoices.first;
    final amount = TextEditingController(
          text: invoice.amount.toStringAsFixed(2),
        ),
        method = TextEditingController(),
        reference = TextEditingController();
    final key = GlobalKey<FormState>();
    final ok = await showDialog<bool>(
      context: context,
      builder:
          (c) => StatefulBuilder(
            builder:
                (context, setState) => AlertDialog(
                  title: const Text('Record manual payment'),
                  content: SizedBox(
                    width: 420,
                    child: Form(
                      key: key,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          DropdownButtonFormField<BillingInvoice>(
                            initialValue: invoice,
                            decoration: const InputDecoration(
                              labelText: 'Open invoice',
                            ),
                            items: [
                              for (final item in openInvoices)
                                DropdownMenuItem(
                                  value: item,
                                  child: Text(
                                    '${item.number} • ${item.planName ?? 'Package'} • ${item.currency} ${item.amount.toStringAsFixed(2)}',
                                  ),
                                ),
                            ],
                            onChanged: (value) {
                              if (value == null) return;
                              setState(() {
                                invoice = value;
                                amount.text = value.amount.toStringAsFixed(2);
                              });
                            },
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: amount,
                            readOnly: true,
                            decoration: const InputDecoration(
                              labelText: 'Amount (PKR)',
                            ),
                            validator:
                                (v) =>
                                    (double.tryParse(v ?? '') ?? 0) > 0
                                        ? null
                                        : 'Enter a positive amount',
                          ),
                          TextFormField(
                            controller: method,
                            decoration: const InputDecoration(
                              labelText: 'Method',
                            ),
                            validator:
                                (v) =>
                                    (v ?? '').trim().isEmpty
                                        ? 'Required'
                                        : null,
                          ),
                          TextFormField(
                            controller: reference,
                            decoration: const InputDecoration(
                              labelText: 'Unique reference',
                            ),
                            validator:
                                (v) =>
                                    (v ?? '').trim().isEmpty
                                        ? 'Required'
                                        : null,
                          ),
                        ],
                      ),
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(c, false),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      onPressed: () {
                        if (key.currentState!.validate()) {
                          Navigator.pop(c, true);
                        }
                      },
                      child: const Text('Record'),
                    ),
                  ],
                ),
          ),
    );
    if (ok == true) {
      await ref
          .read(billingMutationProvider.notifier)
          .run(
            tenantId,
            (r) => r.record(
              tenantId: tenantId,
              invoiceId: invoice.id,
              amount: double.parse(amount.text),
              method: method.text.trim(),
              reference: reference.text.trim(),
              paidAt: DateTime.now(),
            ),
          );
    }
    amount.dispose();
    method.dispose();
    reference.dispose();
  }

  Future<void> _createInvoice(
    BuildContext context,
    WidgetRef ref,
    List<BillingPlan> plans,
  ) async {
    final draft = await showDialog<_InvoiceDraft>(
      context: context,
      builder: (_) => _InvoiceDialog(plans: plans),
    );
    if (draft == null) return;
    await ref
        .read(billingMutationProvider.notifier)
        .run(
          tenantId,
          (repository) => repository.createInvoice(
            tenantId: tenantId,
            planId: draft.planId,
            billingCycle: draft.billingCycle,
            originalAmount: draft.originalAmount,
            discountAmount: draft.discountAmount,
            dueAt: draft.dueAt,
            note: draft.note,
          ),
        );
  }
}

typedef _InvoiceDraft =
    ({
      String planId,
      String billingCycle,
      double originalAmount,
      double discountAmount,
      DateTime? dueAt,
      String? note,
    });

class _InvoiceDialog extends StatefulWidget {
  final List<BillingPlan> plans;
  const _InvoiceDialog({required this.plans});

  @override
  State<_InvoiceDialog> createState() => _InvoiceDialogState();
}

class _InvoiceDialogState extends State<_InvoiceDialog> {
  final key = GlobalKey<FormState>();
  final amount = TextEditingController();
  final discount = TextEditingController(text: '0');
  final note = TextEditingController();
  late BillingPlan plan;
  String cycle = 'monthly';
  DateTime? dueAt;

  @override
  void initState() {
    super.initState();
    plan = widget.plans.first;
    _suggestAmount();
  }

  void _suggestAmount() {
    final monthly = plan.monthlyPrice;
    if (monthly != null) {
      amount.text = (cycle == 'annual' ? monthly * 12 : monthly)
          .toStringAsFixed(2);
    }
  }

  @override
  void dispose() {
    amount.dispose();
    discount.dispose();
    note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Create package invoice'),
      content: SizedBox(
        width: 440,
        child: Form(
          key: key,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<BillingPlan>(
                  initialValue: plan,
                  decoration: const InputDecoration(labelText: 'Package'),
                  items: [
                    for (final item in widget.plans)
                      DropdownMenuItem(value: item, child: Text(item.name)),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() {
                      plan = value;
                      _suggestAmount();
                    });
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: cycle,
                  decoration: const InputDecoration(labelText: 'Billing cycle'),
                  items: const [
                    DropdownMenuItem(value: 'monthly', child: Text('Monthly')),
                    DropdownMenuItem(value: 'annual', child: Text('Annual')),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() {
                      cycle = value;
                      _suggestAmount();
                    });
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: amount,
                  decoration: const InputDecoration(
                    labelText: 'Original amount (PKR)',
                  ),
                  validator:
                      (value) =>
                          (double.tryParse(value ?? '') ?? 0) > 0
                              ? null
                              : 'Enter a positive amount',
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: discount,
                  decoration: const InputDecoration(
                    labelText: 'Discount (PKR)',
                  ),
                  validator: (value) {
                    final original = double.tryParse(amount.text) ?? 0;
                    final reduction = double.tryParse(value ?? '') ?? -1;
                    return reduction >= 0 && reduction < original
                        ? null
                        : 'Discount must be less than amount';
                  },
                ),
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Due date'),
                  subtitle: Text(_date(dueAt)),
                  trailing: TextButton(
                    onPressed: _pickDueDate,
                    child: const Text('Select'),
                  ),
                ),
                TextFormField(
                  controller: note,
                  decoration: const InputDecoration(labelText: 'Note optional'),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Create')),
      ],
    );
  }

  Future<void> _pickDueDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 7)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (selected == null) return;
    setState(() {
      dueAt = DateTime(
        selected.year,
        selected.month,
        selected.day,
        23,
        59,
        59,
        999,
      );
    });
  }

  void _submit() {
    if (!key.currentState!.validate()) return;
    Navigator.pop(context, (
      planId: plan.id,
      billingCycle: cycle,
      originalAmount: double.parse(amount.text),
      discountAmount: double.parse(discount.text),
      dueAt: dueAt,
      note: note.text.trim().isEmpty ? null : note.text.trim(),
    ));
  }
}

List<String> _validActions(String value) {
  return switch (value.toLowerCase()) {
    'pending_activation' => const ['trial_start', 'activate', 'suspend'],
    'trialing' => const ['trial_extend', 'trial_end', 'activate', 'suspend'],
    'trial_expired' => const ['trial_extend', 'activate', 'suspend'],
    'active' => const ['renew', 'grace', 'cancel', 'suspend'],
    'grace_period' => const ['renew', 'activate', 'cancel', 'suspend'],
    'cancelled' => const ['trial_start', 'activate', 'renew', 'suspend'],
    'suspended' => const ['activate'],
    _ => const ['activate', 'suspend'],
  };
}

class _Value extends StatelessWidget {
  final String label, value;
  const _Value(this.label, this.value);
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 180,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelMedium),
        Text(value),
      ],
    ),
  );
}

String _date(DateTime? d) =>
    d == null
        ? '—'
        : '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
String _range(DateTime? a, DateTime? b) =>
    a == null && b == null ? '—' : '${_date(a)} – ${_date(b)}';
