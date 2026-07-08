import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobileshop_saas/features/suppliers/presentation/providers/procurement_provider.dart';

import '../../data/models/procurement_models.dart';

class SuppliersScreen extends ConsumerWidget {
  const SuppliersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final suppliersAsync = ref.watch(suppliersProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Suppliers'),
        actions: [
          IconButton(
            onPressed:
                () =>
                    ref.read(procurementSyncControllerProvider.notifier).sync(),
            icon: const Icon(Icons.sync),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.go('/suppliers/new'),
        icon: const Icon(Icons.add),
        label: const Text('Add Supplier'),
      ),
      body: suppliersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(e.toString())),
        data: (suppliers) {
          if (suppliers.isEmpty) {
            return Center(
              child: FilledButton.icon(
                onPressed: () => context.go('/suppliers/new'),
                icon: const Icon(Icons.add),
                label: const Text('Add First Supplier'),
              ),
            );
          }

          return LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 800;

              if (isWide) {
                return GridView.builder(
                  padding: const EdgeInsets.all(16),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 420,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 1.55,
                  ),
                  itemCount: suppliers.length,
                  itemBuilder: (_, index) {
                    return _SupplierCard(supplier: suppliers[index]);
                  },
                );
              }

              return ListView.separated(
                padding: const EdgeInsets.all(12),
                itemCount: suppliers.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (_, index) {
                  return _SupplierCard(supplier: suppliers[index]);
                },
              );
            },
          );
        },
      ),
    );
  }
}

class _SupplierCard extends ConsumerWidget {
  final SupplierModel supplier;

  const _SupplierCard({required this.supplier});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              supplier.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            if (supplier.contactPerson != null)
              Text('Contact: ${supplier.contactPerson}'),
            if (supplier.phone != null) Text('Phone: ${supplier.phone}'),
            if (supplier.paymentTerms != null)
              Text('Terms: ${supplier.paymentTerms}'),
            const Spacer(),
            Text(
              'Payable: Rs ${supplier.outstandingBalance.toStringAsFixed(0)}',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _showPaymentDialog(context, ref, supplier),
                    child: const Text('Payment'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    onPressed:
                        () =>
                            context.go('/purchase-orders/new', extra: supplier),
                    child: const Text('New PO'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showPaymentDialog(
    BuildContext context,
    WidgetRef ref,
    SupplierModel supplier,
  ) {
    final amountController = TextEditingController();
    final methodController = TextEditingController(text: 'Cash');
    final noteController = TextEditingController();

    showDialog(
      context: context,
      builder: (_) {
        return AlertDialog(
          title: const Text('Record Supplier Payment'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: amountController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(labelText: 'Amount'),
              ),
              TextField(
                controller: methodController,
                decoration: const InputDecoration(labelText: 'Method'),
              ),
              TextField(
                controller: noteController,
                decoration: const InputDecoration(labelText: 'Note optional'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                final amount =
                    double.tryParse(amountController.text.trim()) ?? 0;

                final ok = await ref
                    .read(supplierPaymentControllerProvider.notifier)
                    .recordPayment(
                      supplier: supplier,
                      amount: amount,
                      method: methodController.text,
                      note: noteController.text,
                    );

                if (!context.mounted) return;

                if (ok) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Payment recorded')),
                  );
                }
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }
}
