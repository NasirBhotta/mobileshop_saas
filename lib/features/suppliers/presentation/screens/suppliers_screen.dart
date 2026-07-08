import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobileshop_saas/features/suppliers/presentation/providers/procurement_provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../data/models/procurement_models.dart';

class SuppliersScreen extends ConsumerWidget {
  const SuppliersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const _SuppliersBody();
  }
}

class _SuppliersBody extends ConsumerWidget {
  const _SuppliersBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final suppliersAsync = ref.watch(suppliersProvider);
    final syncState = ref.watch(procurementSyncControllerProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final syncButton = IconButton(
                    tooltip: 'Sync',
                    onPressed:
                        syncState.isLoading
                            ? null
                            : () async {
                              await ref
                                  .read(
                                    procurementSyncControllerProvider.notifier,
                                  )
                                  .sync();
                            },
                    icon:
                        syncState.isLoading
                            ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                            : const Icon(Icons.sync_rounded),
                    color: AppColors.textSecondary,
                  );
                  final purchaseOrdersButton = OutlinedButton.icon(
                    onPressed:
                        syncState.isLoading
                            ? null
                            : () => context.go('/purchase-orders'),
                    icon: const Icon(Icons.receipt_long_rounded, size: 18),
                    label: const Text('POs'),
                  );
                  final addButton = FilledButton.icon(
                    onPressed:
                        syncState.isLoading
                            ? null
                            : () => context.go('/suppliers/new'),
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('Add'),
                  );

                  if (constraints.maxWidth < 390) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            const Expanded(child: _SuppliersTitle()),
                            syncButton,
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(child: purchaseOrdersButton),
                            const SizedBox(width: 8),
                            Expanded(child: addButton),
                          ],
                        ),
                      ],
                    );
                  }

                  return Row(
                    children: [
                      const Expanded(child: _SuppliersTitle()),
                      syncButton,
                      const SizedBox(width: 8),
                      purchaseOrdersButton,
                      const SizedBox(width: 8),
                      addButton,
                    ],
                  );
                },
              ),
            ),
            Expanded(
              child: suppliersAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error:
                    (error, _) => _SupplierErrorView(
                      message: error.toString(),
                      onRetry: () => ref.invalidate(suppliersProvider),
                    ),
                data: (suppliers) {
                  if (suppliers.isEmpty) {
                    return _EmptySuppliersView(
                      onCreate: () => context.go('/suppliers/new'),
                    );
                  }

                  return RefreshIndicator(
                    onRefresh: () async {
                      await ref
                          .read(procurementSyncControllerProvider.notifier)
                          .sync();
                      ref.invalidate(suppliersProvider);
                    },
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final isWide = constraints.maxWidth >= 800;
                        final textScale = MediaQuery.textScalerOf(
                          context,
                        ).scale(1.0).clamp(1.0, 1.3);
                        final gridCardExtent = 226.0 * textScale;

                        if (isWide) {
                          return GridView.builder(
                            padding: const EdgeInsets.all(16),
                            gridDelegate:
                                SliverGridDelegateWithMaxCrossAxisExtent(
                                  maxCrossAxisExtent: 420,
                                  mainAxisSpacing: 12,
                                  crossAxisSpacing: 12,
                                  mainAxisExtent: gridCardExtent,
                                ),
                            itemCount: suppliers.length,
                            itemBuilder: (_, index) {
                              return _SupplierCard(
                                supplier: suppliers[index],
                                compact: false,
                              );
                            },
                          );
                        }

                        return ListView.separated(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.all(12),
                          itemCount: suppliers.length,
                          separatorBuilder:
                              (_, _) => const SizedBox(height: 10),
                          itemBuilder: (_, index) {
                            return _SupplierCard(
                              supplier: suppliers[index],
                              compact: true,
                            );
                          },
                        );
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SuppliersTitle extends StatelessWidget {
  const _SuppliersTitle();

  @override
  Widget build(BuildContext context) {
    return const Text(
      'Suppliers',
      style: TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.bold,
        color: AppColors.textPrimary,
      ),
    );
  }
}

class _EmptySuppliersView extends StatelessWidget {
  final VoidCallback onCreate;

  const _EmptySuppliersView({required this.onCreate});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.local_shipping_outlined,
                size: 56,
                color: AppColors.textSecondary,
              ),
              const SizedBox(height: 12),
              Text(
                'No Suppliers',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              const Text(
                'Abhi koi supplier add nahi hua.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: onCreate,
                icon: const Icon(Icons.add_rounded),
                label: const Text('Add First Supplier'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SupplierErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _SupplierErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline_rounded,
                size: 52,
                color: AppColors.error,
              ),
              const SizedBox(height: 12),
              Text(
                'Suppliers load nahi ho sake',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SupplierCard extends ConsumerWidget {
  final SupplierModel supplier;
  final bool compact;

  const _SupplierCard({required this.supplier, required this.compact});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              supplier.name,
              maxLines: compact ? 2 : 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            _SupplierDetailLine(
              label: 'Contact',
              value: supplier.contactPerson,
            ),
            _SupplierDetailLine(label: 'Phone', value: supplier.phone),
            _SupplierDetailLine(label: 'Terms', value: supplier.paymentTerms),
            SizedBox(height: compact ? 12 : 18),
            Text(
              'Payable: Rs ${supplier.outstandingBalance.toStringAsFixed(0)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            _SupplierCardActions(
              compact: compact,
              onPayment: () => _showPaymentDialog(context, ref, supplier),
              onNewPo:
                  () => context.go('/purchase-orders/new', extra: supplier),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showPaymentDialog(
    BuildContext context,
    WidgetRef ref,
    SupplierModel supplier,
  ) async {
    final amountController = TextEditingController();
    final methodController = TextEditingController(text: 'Cash');
    final noteController = TextEditingController();

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
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
              onPressed: () => Navigator.of(dialogContext).pop(),
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
                  Navigator.of(dialogContext).pop();
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

    amountController.dispose();
    methodController.dispose();
    noteController.dispose();
  }
}

class _SupplierDetailLine extends StatelessWidget {
  final String label;
  final String? value;

  const _SupplierDetailLine({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final text = value?.trim();
    if (text == null || text.isEmpty) {
      return const SizedBox.shrink();
    }

    return Text('$label: $text', maxLines: 1, overflow: TextOverflow.ellipsis);
  }
}

class _SupplierCardActions extends StatelessWidget {
  final bool compact;
  final VoidCallback onPayment;
  final VoidCallback onNewPo;

  const _SupplierCardActions({
    required this.compact,
    required this.onPayment,
    required this.onNewPo,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final stackButtons = compact || constraints.maxWidth < 320;

        final paymentButton = OutlinedButton(
          onPressed: onPayment,
          child: const Text('Payment', overflow: TextOverflow.ellipsis),
        );
        final poButton = FilledButton(
          onPressed: onNewPo,
          child: const Text('New PO', overflow: TextOverflow.ellipsis),
        );

        if (stackButtons) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [paymentButton, const SizedBox(height: 8), poButton],
          );
        }

        return Row(
          children: [
            Expanded(child: paymentButton),
            const SizedBox(width: 8),
            Expanded(child: poButton),
          ],
        );
      },
    );
  }
}
