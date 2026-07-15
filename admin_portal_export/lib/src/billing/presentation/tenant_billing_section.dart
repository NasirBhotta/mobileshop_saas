import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'billing_providers.dart';

class TenantBillingSection extends ConsumerWidget {
  final String tenantId;
  const TenantBillingSection({required this.tenantId, super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(billingSummaryProvider(tenantId));
    final invoices = ref.watch(billingInvoicesProvider(tenantId));
    final payments = ref.watch(billingPaymentsProvider(tenantId));
    final busy = ref.watch(billingMutationProvider).isLoading;
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
              onPressed: busy ? null : () => _record(context, ref),
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
                                    [
                                          'trial_start',
                                          'trial_extend',
                                          'trial_end',
                                          'activate',
                                          'cancel',
                                          'renew',
                                          'suspend',
                                          'grace',
                                        ]
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
            subtitle: Text('${_date(i.issuedAt)} • ${i.status}'),
            trailing: Text('${i.currency} ${i.amount.toStringAsFixed(2)}'),
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
                              busy ? null : () => _verify(ref, p.id, true),
                          icon: const Icon(Icons.check),
                        ),
                        IconButton(
                          tooltip: 'Reject',
                          onPressed:
                              busy ? null : () => _verify(ref, p.id, false),
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
  Future<void> _verify(WidgetRef ref, String id, bool ok) => ref
      .read(billingMutationProvider.notifier)
      .run(tenantId, (r) => r.verify(id, ok));
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

  Future<void> _record(BuildContext context, WidgetRef ref) async {
    final amount = TextEditingController(),
        method = TextEditingController(),
        reference = TextEditingController();
    final key = GlobalKey<FormState>();
    final ok = await showDialog<bool>(
      context: context,
      builder:
          (c) => AlertDialog(
            title: const Text('Record manual payment'),
            content: SizedBox(
              width: 420,
              child: Form(
                key: key,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: amount,
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
                      decoration: const InputDecoration(labelText: 'Method'),
                      validator:
                          (v) => (v ?? '').trim().isEmpty ? 'Required' : null,
                    ),
                    TextFormField(
                      controller: reference,
                      decoration: const InputDecoration(
                        labelText: 'Unique reference',
                      ),
                      validator:
                          (v) => (v ?? '').trim().isEmpty ? 'Required' : null,
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
                  if (key.currentState!.validate()) Navigator.pop(c, true);
                },
                child: const Text('Record'),
              ),
            ],
          ),
    );
    if (ok == true) {
      await ref
          .read(billingMutationProvider.notifier)
          .run(
            tenantId,
            (r) => r.record(
              tenantId: tenantId,
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
