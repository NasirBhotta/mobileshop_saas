import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobileshop_saas/features/suppliers/presentation/providers/procurement_provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/entitlements/entitlement_provider.dart';
import '../../data/models/procurement_models.dart';
import '../../../accounts/presentation/providers/accounts_provider.dart';
import '../../../pos/data/models/sale_payment_model.dart';
import '../../../pos/domain/pos_payment_account_policy.dart';
import '../widgets/supplier_history_dialog.dart';

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
    final purchaseOrdersEnabled =
        ref
            .watch(
              compatibleFeatureEntitlementProvider(
                'procurement.purchase_orders',
              ),
            )
            .value !=
        false;

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
                  final purchaseOrdersButton =
                      purchaseOrdersEnabled
                          ? OutlinedButton.icon(
                            onPressed:
                                syncState.isLoading
                                    ? null
                                    : () => context.go('/purchase-orders'),
                            icon: const Icon(
                              Icons.receipt_long_rounded,
                              size: 18,
                            ),
                            label: const Text('POs'),
                          )
                          : const SizedBox.shrink();
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
                    return RefreshIndicator(
                      onRefresh:
                          () =>
                              ref
                                  .read(
                                    procurementSyncControllerProvider.notifier,
                                  )
                                  .sync(),
                      child: LayoutBuilder(
                        builder:
                            (context, constraints) => ListView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              children: [
                                SizedBox(
                                  height: constraints.maxHeight,
                                  child: _EmptySuppliersView(
                                    onCreate:
                                        () => context.go('/suppliers/new'),
                                  ),
                                ),
                              ],
                            ),
                      ),
                    );
                  }

                  return RefreshIndicator(
                    onRefresh:
                        () =>
                            ref
                                .read(
                                  procurementSyncControllerProvider.notifier,
                                )
                                .sync(),
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

class _SupplierCard extends ConsumerStatefulWidget {
  final SupplierModel supplier;
  final bool compact;

  const _SupplierCard({required this.supplier, required this.compact});

  @override
  ConsumerState<_SupplierCard> createState() => _SupplierCardState();
}

class _SupplierCardState extends ConsumerState<_SupplierCard> {
  bool _openingPayment = false;

  @override
  Widget build(BuildContext context) {
    final supplier = widget.supplier;
    final compact = widget.compact;
    final paymentsEnabled =
        ref
            .watch(
              compatibleFeatureEntitlementProvider(
                'procurement.supplier_payments',
              ),
            )
            .value !=
        false;
    final purchaseOrdersEnabled =
        ref
            .watch(
              compatibleFeatureEntitlementProvider(
                'procurement.purchase_orders',
              ),
            )
            .value !=
        false;
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
              onHistory: () => showSupplierHistoryDialog(context, supplier),
              onPayment:
                  paymentsEnabled
                      ? _openingPayment
                          ? null
                          : () async {
                            setState(() => _openingPayment = true);
                            try {
                              await _showPaymentDialog(context, ref, supplier);
                            } finally {
                              if (mounted) {
                                setState(() => _openingPayment = false);
                              }
                            }
                          }
                      : null,
              paymentLoading: _openingPayment,
              onNewPo:
                  purchaseOrdersEnabled
                      ? () =>
                          context.go('/purchase-orders/new', extra: supplier)
                      : null,
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
    final overview = await ref.read(supplierOverviewProvider(supplier).future);
    final accounts = await ref.read(accountsProvider.future);
    if (!context.mounted) return;

    final payableOrders =
        overview.activeOrders
            .where((order) => overview.payableForOrder(order) > 0.01)
            .toList();
    if (payableOrders.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No received PO payment is pending.')),
      );
      return;
    }

    final amountController = TextEditingController();
    final noteController = TextEditingController();
    var method = PaymentMethod.cash;
    String? accountId;
    var purchaseOrderId = payableOrders.first.id;
    var submitting = false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final compatible = PosPaymentAccountPolicy.compatibleAccounts(
              method,
              accounts,
            );
            final effectiveAccountId =
                accountId ??
                PosPaymentAccountPolicy.suggestedAccount(
                  method,
                  compatible,
                )?.id;
            final selectedOrder = payableOrders.firstWhere(
              (order) => order.id == purchaseOrderId,
            );
            final pending = overview.payableForOrder(selectedOrder);

            return Dialog(
              insetPadding: const EdgeInsets.all(16),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Record Supplier Payment',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 20),
                      DropdownButtonFormField<String>(
                        initialValue: purchaseOrderId,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Purchase Order',
                          border: OutlineInputBorder(),
                        ),
                        items:
                            payableOrders
                                .map(
                                  (order) => DropdownMenuItem(
                                    value: order.id,
                                    child: Text(
                                      '${order.poNo} • Pending Rs '
                                      '${overview.payableForOrder(order).toStringAsFixed(0)}',
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                )
                                .toList(),
                        onChanged:
                            submitting
                                ? null
                                : (value) {
                                  if (value == null) return;
                                  setDialogState(() {
                                    purchaseOrderId = value;
                                    amountController.clear();
                                  });
                                },
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'PO total: Rs ${selectedOrder.totalExpectedCost.toStringAsFixed(0)}'
                        '  •  Received: Rs ${selectedOrder.totalReceivedCost.toStringAsFixed(0)}'
                        '  •  Paid: Rs ${overview.paidForOrder(selectedOrder.id).toStringAsFixed(0)}'
                        '  •  Pending: Rs ${pending.toStringAsFixed(0)}',
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: amountController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: InputDecoration(
                          labelText: 'Amount to send',
                          helperText:
                              'Maximum Rs ${pending.toStringAsFixed(0)}',
                          border: const OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<PaymentMethod>(
                        initialValue: method,
                        decoration: const InputDecoration(
                          labelText: 'Method',
                          border: OutlineInputBorder(),
                        ),
                        items:
                            PaymentMethod.values
                                .where((value) => value != PaymentMethod.credit)
                                .map(
                                  (value) => DropdownMenuItem(
                                    value: value,
                                    child: Text(value.label),
                                  ),
                                )
                                .toList(),
                        onChanged:
                            submitting
                                ? null
                                : (value) {
                                  if (value == null) return;
                                  setDialogState(() {
                                    method = value;
                                    accountId = null;
                                  });
                                },
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: effectiveAccountId,
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: 'Pay from account / wallet',
                          border: const OutlineInputBorder(),
                          helperText:
                              compatible.isEmpty
                                  ? 'No ${method.label} account is available.'
                                  : null,
                        ),
                        items:
                            compatible
                                .map(
                                  (account) => DropdownMenuItem(
                                    value: account.id,
                                    child: Text(
                                      '${account.name} • Rs ${account.currentBalance.toStringAsFixed(0)}',
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                )
                                .toList(),
                        onChanged:
                            submitting || compatible.isEmpty
                                ? null
                                : (value) =>
                                    setDialogState(() => accountId = value),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: noteController,
                        decoration: const InputDecoration(
                          labelText: 'Note optional',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed:
                                submitting
                                    ? null
                                    : () => Navigator.of(dialogContext).pop(),
                            child: const Text('Cancel'),
                          ),
                          const SizedBox(width: 8),
                          FilledButton(
                            onPressed:
                                submitting || effectiveAccountId == null
                                    ? null
                                    : () async {
                                      final amount =
                                          double.tryParse(
                                            amountController.text.trim(),
                                          ) ??
                                          0;
                                      if (amount <= 0 ||
                                          amount > pending + 0.01) {
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              'Enter amount between Rs 1 and '
                                              'Rs ${pending.toStringAsFixed(0)}',
                                            ),
                                          ),
                                        );
                                        return;
                                      }
                                      setDialogState(() => submitting = true);
                                      final ok = await ref
                                          .read(
                                            supplierPaymentControllerProvider
                                                .notifier,
                                          )
                                          .recordPayment(
                                            supplier: supplier,
                                            purchaseOrderId: purchaseOrderId,
                                            amount: amount,
                                            method: method.code,
                                            accountId: effectiveAccountId,
                                            note: noteController.text,
                                          );
                                      if (!context.mounted) return;
                                      if (ok) {
                                        Navigator.of(dialogContext).pop();
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          const SnackBar(
                                            content: Text('Payment recorded'),
                                          ),
                                        );
                                      } else {
                                        setDialogState(
                                          () => submitting = false,
                                        );
                                      }
                                    },
                            child:
                                submitting
                                    ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                    : const Text('Send Payment'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    amountController.dispose();
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
  final VoidCallback onHistory;
  final VoidCallback? onPayment;
  final bool paymentLoading;
  final VoidCallback? onNewPo;

  const _SupplierCardActions({
    required this.compact,
    required this.onHistory,
    required this.onPayment,
    this.paymentLoading = false,
    required this.onNewPo,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final stackButtons = compact || constraints.maxWidth < 320;

        final buttons = <Widget>[
          OutlinedButton(
            onPressed: onHistory,
            child: const Text('History', overflow: TextOverflow.ellipsis),
          ),
          if (onPayment != null || paymentLoading)
            OutlinedButton(
              onPressed: paymentLoading ? null : onPayment,
              child:
                  paymentLoading
                      ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                      : const Text('Payment', overflow: TextOverflow.ellipsis),
            ),
          if (onNewPo != null)
            FilledButton(
              onPressed: onNewPo,
              child: const Text('New PO', overflow: TextOverflow.ellipsis),
            ),
        ];
        if (buttons.isEmpty) return const SizedBox.shrink();

        if (stackButtons) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var index = 0; index < buttons.length; index++) ...[
                if (index > 0) const SizedBox(height: 8),
                buttons[index],
              ],
            ],
          );
        }

        return Row(
          children: [
            for (var index = 0; index < buttons.length; index++) ...[
              if (index > 0) const SizedBox(width: 8),
              Expanded(child: buttons[index]),
            ],
          ],
        );
      },
    );
  }
}
