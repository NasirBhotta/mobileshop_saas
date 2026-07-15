import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'addon_providers.dart';

class TenantAddonsSection extends ConsumerWidget {
  final String tenantId;
  const TenantAddonsSection({required this.tenantId, super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final assignments = ref.watch(tenantAddonsProvider(tenantId)),
        usage = ref.watch(tenantUsageProvider(tenantId));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Add-ons & usage',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
            FilledButton.icon(
              onPressed: () => _assign(context, ref),
              icon: const Icon(Icons.add),
              label: const Text('Assign add-on'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        assignments.when(
          loading: () => const LinearProgressIndicator(),
          error: (e, _) => Text('Could not load add-ons: $e'),
          data:
              (items) => Card(
                child: Column(
                  children:
                      items.isEmpty
                          ? [
                            const ListTile(title: Text('No add-ons assigned.')),
                          ]
                          : items
                              .map(
                                (a) => ListTile(
                                  title: Text('${a.name} × ${a.quantity}'),
                                  subtitle: Text(
                                    '${a.status} • ${_date(a.startsAt)} to ${_date(a.expiresAt)}',
                                  ),
                                  trailing: IconButton(
                                    tooltip: 'Remove',
                                    onPressed:
                                        a.status == 'removed'
                                            ? null
                                            : () => ref
                                                .read(
                                                  addonMutationProvider
                                                      .notifier,
                                                )
                                                .run(
                                                  (r) => r.remove(a.id),
                                                  tenantId: tenantId,
                                                ),
                                    icon: const Icon(Icons.delete_outline),
                                  ),
                                ),
                              )
                              .toList(),
                ),
              ),
        ),
        const SizedBox(height: 20),
        Text('Limit usage', style: Theme.of(context).textTheme.titleLarge),
        usage.when(
          loading: () => const LinearProgressIndicator(),
          error: (e, _) => Text('Could not load usage: $e'),
          data:
              (items) => Card(
                child: Column(
                  children:
                      items.isEmpty
                          ? [
                            const ListTile(
                              title: Text('No usage metrics reported.'),
                            ),
                          ]
                          : items
                              .map(
                                (u) => ListTile(
                                  leading: Icon(
                                    u.warning == 'exceeded'
                                        ? Icons.error
                                        : u.warning == 'approaching'
                                        ? Icons.warning
                                        : Icons.check_circle,
                                    color:
                                        u.warning == 'exceeded'
                                            ? Colors.red
                                            : u.warning == 'approaching'
                                            ? Colors.orange
                                            : Colors.green,
                                  ),
                                  title: Text(u.key),
                                  subtitle: LinearProgressIndicator(
                                    value:
                                        u.effective <= 0 || u.effective == -1
                                            ? 0
                                            : (u.percent / 100).clamp(0, 1),
                                  ),
                                  trailing: Text(
                                    u.effective == -1
                                        ? '${u.used} / unlimited'
                                        : '${u.used} / ${u.effective}\n${u.percent.toStringAsFixed(0)}%',
                                  ),
                                ),
                              )
                              .toList(),
                ),
              ),
        ),
      ],
    );
  }

  Future<void> _assign(BuildContext context, WidgetRef ref) async {
    final addons = await ref.read(addonsProvider.future);
    if (!context.mounted) return;
    String? selected;
    String status = 'active';
    final quantity = TextEditingController(text: '1');
    DateTime start = DateTime.now();
    DateTime? expiry;
    final ok = await showDialog<bool>(
      context: context,
      builder:
          (c) => StatefulBuilder(
            builder:
                (c, setState) => AlertDialog(
                  title: const Text('Assign add-on'),
                  content: SizedBox(
                    width: 440,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        DropdownButtonFormField<String>(
                          decoration: const InputDecoration(
                            labelText: 'Add-on',
                          ),
                          items:
                              addons
                                  .where((a) => a.isActive)
                                  .map(
                                    (a) => DropdownMenuItem(
                                      value: a.id,
                                      child: Text(a.name),
                                    ),
                                  )
                                  .toList(),
                          onChanged: (v) => setState(() => selected = v),
                        ),
                        TextField(
                          controller: quantity,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Quantity',
                          ),
                        ),
                        DropdownButtonFormField(
                          initialValue: status,
                          items:
                              ['scheduled', 'active', 'expired']
                                  .map(
                                    (v) => DropdownMenuItem(
                                      value: v,
                                      child: Text(v),
                                    ),
                                  )
                                  .toList(),
                          onChanged: (v) => setState(() => status = v!),
                          decoration: const InputDecoration(
                            labelText: 'Status',
                          ),
                        ),
                        ListTile(
                          title: Text('Starts ${_date(start)}'),
                          onTap: () async {
                            final d = await showDatePicker(
                              context: c,
                              initialDate: start,
                              firstDate: DateTime(2020),
                              lastDate: DateTime(2100),
                            );
                            if (d != null) setState(() => start = d);
                          },
                        ),
                        ListTile(
                          title: Text('Expires ${_date(expiry)}'),
                          onTap: () async {
                            final d = await showDatePicker(
                              context: c,
                              initialDate:
                                  expiry ?? start.add(const Duration(days: 30)),
                              firstDate: start.add(const Duration(days: 1)),
                              lastDate: DateTime(2100),
                            );
                            if (d != null) setState(() => expiry = d);
                          },
                        ),
                      ],
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(c, false),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      onPressed:
                          selected == null
                              ? null
                              : () => Navigator.pop(c, true),
                      child: const Text('Assign'),
                    ),
                  ],
                ),
          ),
    );
    if (ok == true && selected != null) {
      await ref
          .read(addonMutationProvider.notifier)
          .run(
            (r) => r.assign(
              tenantId: tenantId,
              addonId: selected!,
              quantity: int.tryParse(quantity.text) ?? 1,
              startsAt: start,
              expiresAt: expiry,
              status: status,
            ),
            tenantId: tenantId,
          );
    }
    quantity.dispose();
  }
}

String _date(DateTime? d) =>
    d == null
        ? 'no expiry'
        : '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
