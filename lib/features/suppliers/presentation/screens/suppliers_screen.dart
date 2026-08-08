import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobileshop_saas/features/suppliers/presentation/providers/procurement_provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/entitlements/entitlement_provider.dart';
import '../../data/models/procurement_models.dart';
import '../../../accounts/data/models/account_models.dart';
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
                        final gridCardExtent = 382.0 * textScale;

                        if (isWide) {
                          return GridView.builder(
                            padding: const EdgeInsets.all(16),
                            gridDelegate:
                                SliverGridDelegateWithMaxCrossAxisExtent(
                                  maxCrossAxisExtent: 480,
                                  mainAxisSpacing: 20,
                                  crossAxisSpacing: 20,
                                  mainAxisExtent: gridCardExtent,
                                ),
                            itemCount: suppliers.length,
                            itemBuilder: (_, index) {
                              return _SupplierCard(supplier: suppliers[index]);
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
                            return _SupplierCard(supplier: suppliers[index]);
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

  const _SupplierCard({required this.supplier});

  @override
  ConsumerState<_SupplierCard> createState() => _SupplierCardState();
}

class _SupplierCardState extends ConsumerState<_SupplierCard> {
  bool _openingPayment = false;

  @override
  Widget build(BuildContext context) {
    final supplier = widget.supplier;
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
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor:
                      Theme.of(context).colorScheme.primaryContainer,
                  foregroundColor:
                      Theme.of(context).colorScheme.onPrimaryContainer,
                  child: Text(
                    supplier.name.trim().isEmpty
                        ? 'S'
                        : supplier.name.trim()[0].toUpperCase(),
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 18,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        supplier.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        supplier.contactPerson?.trim().isNotEmpty == true
                            ? supplier.contactPerson!
                            : 'Supplier account',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color:
                        supplier.isActive
                            ? const Color(0xffe7f6ef)
                            : const Color(0xfff3f4f4),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    supplier.isActive ? 'Active' : 'Inactive',
                    style: TextStyle(
                      color:
                          supplier.isActive
                              ? AppColors.success
                              : AppColors.textSecondary,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 14,
              runSpacing: 9,
              children: [
                _SupplierInfo(
                  icon: Icons.phone_outlined,
                  value: supplier.phone,
                  fallback: 'No phone',
                ),
                _SupplierInfo(
                  icon: Icons.location_on_outlined,
                  value: supplier.city,
                  fallback: 'No city',
                ),
                _SupplierInfo(
                  icon: Icons.event_note_outlined,
                  value: supplier.paymentTerms,
                  fallback: 'No payment terms',
                ),
              ],
            ),
            const SizedBox(height: 18),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color:
                    supplier.outstandingBalance > 0
                        ? const Color(0xfffff6e6)
                        : const Color(0xffeaf7f1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(
                    supplier.outstandingBalance > 0
                        ? Icons.account_balance_wallet_outlined
                        : Icons.check_circle_outline_rounded,
                    size: 20,
                    color:
                        supplier.outstandingBalance > 0
                            ? const Color(0xffa76300)
                            : AppColors.success,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          supplier.outstandingBalance > 0
                              ? 'Outstanding payable'
                              : 'Account settled',
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                        Text(
                          'Rs ${supplier.outstandingBalance.toStringAsFixed(0)}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 18,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _SupplierCardActions(
              onHistory: () => showSupplierHistoryDialog(context, supplier),
              onAnalytics:
                  () => context.push('/suppliers/analytics', extra: supplier),
              onViewProducts:
                  () => context.go(
                    Uri(
                      path: '/inventory',
                      queryParameters: {'supplierId': supplier.id},
                    ).toString(),
                  ),
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
            AccountModel? selectedAccount;
            for (final account in compatible) {
              if (account.id == effectiveAccountId) {
                selectedAccount = account;
                break;
              }
            }
            final selectedOrder = payableOrders.firstWhere(
              (order) => order.id == purchaseOrderId,
            );
            final pending = overview.payableForOrder(selectedOrder);
            final availableBalance = selectedAccount?.currentBalance ?? 0;
            final maximumSendable =
                pending < availableBalance ? pending : availableBalance;
            final enteredAmount =
                double.tryParse(amountController.text.trim()) ?? 0;
            final amountExceedsBalance =
                selectedAccount != null &&
                enteredAmount > availableBalance + 0.01;
            final amountIsValid =
                enteredAmount > 0 &&
                enteredAmount <= pending + 0.01 &&
                !amountExceedsBalance;

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
                              selectedAccount == null
                                  ? 'Select paying account first.'
                                  : 'Maximum Rs ${maximumSendable.toStringAsFixed(0)} '
                                      '(account balance Rs '
                                      '${availableBalance.toStringAsFixed(0)})',
                          errorText:
                              amountExceedsBalance
                                  ? 'Insufficient balance. Available Rs '
                                      '${availableBalance.toStringAsFixed(0)}.'
                                  : enteredAmount > pending + 0.01
                                  ? 'Amount exceeds PO pending Rs '
                                      '${pending.toStringAsFixed(0)}.'
                                  : null,
                          border: const OutlineInputBorder(),
                        ),
                        onChanged: (_) => setDialogState(() {}),
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
                                submitting ||
                                        effectiveAccountId == null ||
                                        !amountIsValid
                                    ? null
                                    : () async {
                                      final amount =
                                          double.tryParse(
                                            amountController.text.trim(),
                                          ) ??
                                          0;
                                      if (amount <= 0 ||
                                          amount > pending + 0.01 ||
                                          amount > availableBalance + 0.01) {
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              'Enter amount between Rs 1 and '
                                              'Rs ${maximumSendable.toStringAsFixed(0)}',
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

class _SupplierInfo extends StatelessWidget {
  final IconData icon;
  final String? value;
  final String fallback;

  const _SupplierInfo({
    required this.icon,
    required this.value,
    required this.fallback,
  });

  @override
  Widget build(BuildContext context) {
    final text = value?.trim();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(width: 1),
        Icon(icon, size: 16, color: AppColors.textSecondary),
        const SizedBox(width: 5),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 145),
          child: Text(
            text == null || text.isEmpty ? fallback : text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
            ),
          ),
        ),
      ],
    );
  }
}

class _SupplierCardActions extends StatelessWidget {
  final VoidCallback onHistory;
  final VoidCallback onAnalytics;
  final VoidCallback onViewProducts;
  final VoidCallback? onPayment;
  final bool paymentLoading;
  final VoidCallback? onNewPo;

  const _SupplierCardActions({
    required this.onHistory,
    required this.onAnalytics,
    required this.onViewProducts,
    required this.onPayment,
    this.paymentLoading = false,
    required this.onNewPo,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final stackButtons = constraints.maxWidth < 260;

        final buttons = <Widget>[
          OutlinedButton.icon(
            onPressed: onAnalytics,
            icon: const Icon(Icons.query_stats_rounded, size: 17),
            label: const Text('Analytics', overflow: TextOverflow.ellipsis),
          ),
          OutlinedButton.icon(
            onPressed: onViewProducts,
            icon: const Icon(Icons.inventory_2_outlined, size: 17),
            label: const Text('Products', overflow: TextOverflow.ellipsis),
          ),
          OutlinedButton.icon(
            onPressed: onHistory,
            icon: const Icon(Icons.history_rounded, size: 17),
            label: const Text('History', overflow: TextOverflow.ellipsis),
          ),
          if (onPayment != null || paymentLoading)
            OutlinedButton.icon(
              onPressed: paymentLoading ? null : onPayment,
              icon:
                  paymentLoading
                      ? const SizedBox.shrink()
                      : const Icon(Icons.payments_outlined, size: 17),
              label:
                  paymentLoading
                      ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                      : const Text('Payment', overflow: TextOverflow.ellipsis),
            ),
          if (onNewPo != null)
            FilledButton.icon(
              onPressed: onNewPo,
              icon: const Icon(Icons.add_rounded, size: 17),
              label: const Text('New PO', overflow: TextOverflow.ellipsis),
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

        final buttonWidth = (constraints.maxWidth - 8) / 2;
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final button in buttons)
              SizedBox(width: buttonWidth, height: 42, child: button),
          ],
        );
      },
    );
  }
}
