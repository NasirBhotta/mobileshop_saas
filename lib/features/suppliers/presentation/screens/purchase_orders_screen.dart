import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobileshop_saas/features/suppliers/presentation/providers/procurement_provider.dart';
import 'package:mobileshop_saas/features/accounts/data/models/account_models.dart';
import 'package:mobileshop_saas/features/accounts/presentation/providers/accounts_provider.dart';

import '../../../../core/entitlements/entitlement_provider.dart';
import '../../data/models/procurement_models.dart';

class PurchaseOrdersScreen extends ConsumerWidget {
  const PurchaseOrdersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ordersAsync = ref.watch(purchaseOrdersProvider);
    final suppliers =
        ref.watch(suppliersProvider).value ?? const <SupplierModel>[];
    final selectedStatus = ref.watch(selectedPOStatusProvider);
    final syncState = ref.watch(procurementSyncControllerProvider);
    final canCreate =
        ref
            .watch(
              compatibleFeatureEntitlementProvider(
                'procurement.purchase_orders',
              ),
            )
            .value !=
        false;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Back to suppliers',
          onPressed: () => context.go('/suppliers'),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: const Text('Purchase Orders'),
        actions: [
          IconButton(
            onPressed:
                syncState.isLoading
                    ? null
                    : () =>
                        ref
                            .read(procurementSyncControllerProvider.notifier)
                            .sync(),
            icon:
                syncState.isLoading
                    ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                    : const Icon(Icons.sync),
          ),
        ],
      ),
      floatingActionButton:
          canCreate
              ? FloatingActionButton.extended(
                onPressed: () => context.go('/purchase-orders/new'),
                icon: const Icon(Icons.add),
                label: const Text('New PO'),
              )
              : null,
      body: Column(
        children: [
          SizedBox(
            height: 56,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.all(10),
              children: [
                _chip(ref, selectedStatus, null, 'All'),
                for (final status in PurchaseOrderStatus.values)
                  _chip(ref, selectedStatus, status, status.label),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ordersAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text(e.toString())),
              data: (orders) {
                if (orders.isEmpty) {
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
                                child: Center(
                                  child: FilledButton.icon(
                                    onPressed:
                                        () =>
                                            context.go('/purchase-orders/new'),
                                    icon: const Icon(Icons.add),
                                    label: const Text('Create Purchase Order'),
                                  ),
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
                              .read(procurementSyncControllerProvider.notifier)
                              .sync(),
                  child: _SupplierGroupedPurchaseOrders(
                    orders: orders,
                    suppliers: suppliers,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(
    WidgetRef ref,
    PurchaseOrderStatus? selected,
    PurchaseOrderStatus? status,
    String label,
  ) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        selected: selected == status,
        label: Text(label),
        onSelected: (_) {
          ref.read(selectedPOStatusProvider.notifier).state = status;
        },
      ),
    );
  }
}

class _SupplierGroupedPurchaseOrders extends StatelessWidget {
  final List<PurchaseOrderModel> orders;
  final List<SupplierModel> suppliers;

  const _SupplierGroupedPurchaseOrders({
    required this.orders,
    required this.suppliers,
  });

  @override
  Widget build(BuildContext context) {
    final supplierById = {
      for (final supplier in suppliers) supplier.id: supplier,
    };
    final grouped = <String, List<PurchaseOrderModel>>{};
    for (final order in orders) {
      grouped.putIfAbsent(order.supplierId, () => []).add(order);
    }
    final supplierIds =
        grouped.keys.toList()..sort((a, b) {
          final aName = supplierById[a]?.name ?? 'Unknown supplier';
          final bName = supplierById[b]?.name ?? 'Unknown supplier';
          return aName.toLowerCase().compareTo(bName.toLowerCase());
        });

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 850;
        final cardWidth =
            wide ? ((constraints.maxWidth - 44) / 2).clamp(340.0, 430.0) : null;
        return ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            for (final supplierId in supplierIds) ...[
              Row(
                children: [
                  const Icon(Icons.local_shipping_outlined, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      supplierById[supplierId]?.name ?? 'Unknown supplier',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Text('${grouped[supplierId]!.length} PO(s)'),
                ],
              ),
              const SizedBox(height: 10),
              if (wide)
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (final order in grouped[supplierId]!)
                      SizedBox(
                        width: cardWidth,
                        height: 250,
                        child: _POCard(po: order),
                      ),
                  ],
                )
              else
                for (
                  var index = 0;
                  index < grouped[supplierId]!.length;
                  index++
                ) ...[
                  _POCard(po: grouped[supplierId]![index]),
                  if (index < grouped[supplierId]!.length - 1)
                    const SizedBox(height: 10),
                ],
              const SizedBox(height: 24),
            ],
          ],
        );
      },
    );
  }
}

class _POCard extends ConsumerWidget {
  final PurchaseOrderModel po;

  const _POCard({required this.po});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final goodsReceiptsEnabled =
        ref
            .watch(
              compatibleFeatureEntitlementProvider(
                'procurement.goods_receipts',
              ),
            )
            .value !=
        false;
    final canSend = po.status == PurchaseOrderStatus.draft;
    final canReceive =
        po.status == PurchaseOrderStatus.sent ||
        po.status == PurchaseOrderStatus.partiallyReceived ||
        po.status == PurchaseOrderStatus.draft;

    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _showPODetails(context, ref, po),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      po.poNo,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Chip(label: Text(po.status.label)),
                ],
              ),
              Text('Items: ${po.items.length}'),
              Text('Expected: Rs ${po.totalExpectedCost.toStringAsFixed(0)}'),
              Text('Received: Rs ${po.totalReceivedCost.toStringAsFixed(0)}'),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (canSend)
                    OutlinedButton(
                      onPressed: () async {
                        await ref
                            .read(purchaseOrderControllerProvider.notifier)
                            .markSent(po);
                      },
                      child: const Text('Send'),
                    ),
                  if (canReceive && goodsReceiptsEnabled)
                    FilledButton(
                      onPressed:
                          () =>
                              context.go('/purchase-orders/receive', extra: po),
                      child: const Text('Receive'),
                    ),
                  if (po.status != PurchaseOrderStatus.cancelled)
                    OutlinedButton.icon(
                      onPressed: () => _showPOReversalDialog(context, ref, po),
                      icon: Icon(
                        po.totalReceivedCost > 0
                            ? Icons.assignment_return_rounded
                            : Icons.cancel_outlined,
                      ),
                      label: Text(
                        po.totalReceivedCost > 0
                            ? 'Return to Supplier'
                            : 'Cancel PO',
                      ),
                    ),
                  OutlinedButton(
                    onPressed:
                        () =>
                            context.push('/purchase-orders/export', extra: po),
                    child: const Text('Export'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> _showPODetails(
  BuildContext context,
  WidgetRef ref,
  PurchaseOrderModel po,
) {
  final details = () async {
    final suppliers = await ref.read(suppliersProvider.future);
    final supplier = suppliers.firstWhere(
      (item) => item.id == po.supplierId,
      orElse:
          () => SupplierModel(
            id: po.supplierId,
            tenantId: po.tenantId,
            branchId: po.branchId,
            name: 'Supplier',
          ),
    );
    final overview = await ref.read(supplierOverviewProvider(supplier).future);
    return (supplier: supplier, overview: overview);
  }();

  return showDialog<void>(
    context: context,
    builder:
        (dialogContext) => Dialog(
          insetPadding: const EdgeInsets.all(16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680, maxHeight: 720),
            child: FutureBuilder<
              ({SupplierModel supplier, SupplierOverviewModel overview})
            >(
              future: details,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const SizedBox(
                    height: 240,
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                if (snapshot.hasError) {
                  return Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          snapshot.error.toString(),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: () => Navigator.pop(dialogContext),
                          child: const Text('Close'),
                        ),
                      ],
                    ),
                  );
                }

                final data = snapshot.requireData;
                final paid = data.overview.paidForOrder(po.id);
                final payable = data.overview.payableForOrder(po);
                final unreceived = (po.totalExpectedCost - po.totalReceivedCost)
                    .clamp(0, double.infinity);
                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 20, 12, 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  po.poNo,
                                  style:
                                      Theme.of(context).textTheme.headlineSmall,
                                ),
                                Text(
                                  '${data.supplier.name} • ${po.status.label}',
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: 'Close',
                            onPressed: () => Navigator.pop(dialogContext),
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.all(20),
                        children: [
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              _POAmountTile(
                                label: 'Order total',
                                value: po.totalExpectedCost,
                              ),
                              _POAmountTile(
                                label: 'Goods received',
                                value: po.totalReceivedCost,
                              ),
                              _POAmountTile(label: 'Paid', value: paid),
                              _POAmountTile(
                                label: 'Payment pending',
                                value: payable,
                              ),
                              _POAmountTile(
                                label: 'Goods pending',
                                value: unreceived,
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          Text(
                            'Items',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 8),
                          for (final item in po.items)
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(item.productName),
                              subtitle: Text(
                                'Ordered ${item.orderedQuantity} • '
                                'Received ${item.receivedQuantity} • '
                                'Unit cost Rs ${item.negotiatedUnitCost.toStringAsFixed(0)}',
                              ),
                              trailing: Text(
                                'Rs ${item.lineTotal.toStringAsFixed(0)}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          if (po.notes?.trim().isNotEmpty == true) ...[
                            const Divider(),
                            Text('Notes: ${po.notes}'),
                          ],
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
  );
}

class _POAmountTile extends StatelessWidget {
  final String label;
  final num value;

  const _POAmountTile({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 190,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label),
          const SizedBox(height: 4),
          Text(
            'Rs ${value.toStringAsFixed(0)}',
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
          ),
        ],
      ),
    );
  }
}

Future<void> _showPOReversalDialog(
  BuildContext context,
  WidgetRef ref,
  PurchaseOrderModel po,
) async {
  final received = po.totalReceivedCost > 0;
  final reason = TextEditingController();
  var resolution = received ? 'supplier_credit' : 'unreceived_cancel';
  String? accountId;
  String? error;
  var saving = false;
  final accounts =
      received
          ? (await ref.read(accountsProvider.future))
              .where(
                (account) =>
                    account.isActive && account.branchId == po.branchId,
              )
              .toList()
          : const <AccountModel>[];
  if (!context.mounted) {
    reason.dispose();
    return;
  }
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder:
        (dialogContext) => StatefulBuilder(
          builder:
              (context, setDialogState) => AlertDialog(
                title: Text(
                  received ? 'Return PO to supplier' : 'Cancel purchase order',
                ),
                content: SizedBox(
                  width: 520,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        received
                            ? 'Received value: Rs '
                                '${po.totalReceivedCost.toStringAsFixed(0)}. '
                                'Stock, supplier payable and created products '
                                'will be safely reversed.'
                            : 'No goods were received. This only cancels the PO.',
                      ),
                      if (received) ...[
                        const SizedBox(height: 12),
                        SegmentedButton<String>(
                          segments: const [
                            ButtonSegment(
                              value: 'supplier_credit',
                              label: Text('Supplier Credit'),
                            ),
                            ButtonSegment(
                              value: 'supplier_refund',
                              label: Text('Money Refunded'),
                            ),
                          ],
                          selected: {resolution},
                          onSelectionChanged:
                              saving
                                  ? null
                                  : (values) => setDialogState(() {
                                    resolution = values.first;
                                    accountId = null;
                                    error = null;
                                  }),
                        ),
                        if (resolution == 'supplier_refund') ...[
                          const SizedBox(height: 12),
                          DropdownButtonFormField<String>(
                            initialValue: accountId,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Refund received in account / wallet',
                              border: OutlineInputBorder(),
                            ),
                            items:
                                accounts
                                    .map(
                                      (account) => DropdownMenuItem(
                                        value: account.id,
                                        child: Text(account.name),
                                      ),
                                    )
                                    .toList(),
                            onChanged:
                                saving
                                    ? null
                                    : (value) =>
                                        setDialogState(() => accountId = value),
                          ),
                        ],
                      ],
                      const SizedBox(height: 12),
                      TextField(
                        controller: reason,
                        enabled: !saving,
                        maxLines: 2,
                        decoration: const InputDecoration(
                          labelText: 'Reason required',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      if (error != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed:
                        saving ? null : () => Navigator.pop(dialogContext),
                    child: const Text('Back'),
                  ),
                  FilledButton(
                    onPressed:
                        saving
                            ? null
                            : () async {
                              if (reason.text.trim().isEmpty) {
                                setDialogState(
                                  () => error = 'Return reason is required.',
                                );
                                return;
                              }
                              if (resolution == 'supplier_refund' &&
                                  accountId == null) {
                                setDialogState(
                                  () => error = 'Select refund account.',
                                );
                                return;
                              }
                              setDialogState(() {
                                saving = true;
                                error = null;
                              });
                              final ok = await ref
                                  .read(
                                    purchaseOrderControllerProvider.notifier,
                                  )
                                  .reversePO(
                                    po: po,
                                    resolution: resolution,
                                    reason: reason.text,
                                    recoveryAccountId: accountId,
                                  );
                              if (!dialogContext.mounted) return;
                              if (ok) {
                                Navigator.pop(dialogContext);
                                return;
                              }
                              final raw =
                                  ref
                                      .read(purchaseOrderControllerProvider)
                                      .asError
                                      ?.error
                                      .toString() ??
                                  '';
                              setDialogState(() {
                                saving = false;
                                error = _poReversalError(raw);
                              });
                            },
                    child:
                        saving
                            ? const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                ),
                                SizedBox(width: 8),
                                Text('Reversing...'),
                              ],
                            )
                            : Text(received ? 'Reverse Safely' : 'Cancel PO'),
                  ),
                ],
              ),
        ),
  );
  reason.dispose();
}

String _poReversalError(String raw) {
  final value = raw.toLowerCase();
  if (value.contains('pgrst202') ||
      value.contains('reverse_purchase_order_v2') &&
          (value.contains('schema cache') || value.contains('not found'))) {
    return 'PO reversal database migration remote Supabase par apply nahi hui.';
  }
  if (value.contains('not allowed') ||
      value.contains('permission') ||
      value.contains('42501')) {
    return 'Aap ke paas is PO ko cancel/return karne ki permission nahi hai.';
  }
  if (value.contains('sold, transferred, or consumed')) {
    return 'Some received stock has already been sold, transferred or used.';
  }
  if (value.contains('already reversed') ||
      value.contains('already cancelled')) {
    return 'This purchase order is already cancelled/reversed.';
  }
  if (value.contains('network') || value.contains('connection')) {
    return 'Network unavailable. No reversal was applied; retry online.';
  }
  if (value.contains('timeout')) {
    return 'Request timeout ho gayi. Refresh karke PO status check karein.';
  }
  final backendMessage = _safeBackendMessage(raw);
  if (backendMessage != null) {
    return '$backendMessage No partial changes were applied.';
  }
  return 'PO could not be reversed. No partial changes were applied. '
      'Please verify the remote database migration.';
}

String? _safeBackendMessage(String raw) {
  var message = raw.trim();
  if (message.isEmpty) return null;
  const postgrestPrefix = 'PostgrestException(message: ';
  if (message.startsWith(postgrestPrefix)) {
    message = message.substring(postgrestPrefix.length);
    message = message.split(', code:').first.trim();
  } else if (message.startsWith('Exception: ')) {
    message = message.substring('Exception: '.length).trim();
  }
  if (message.isEmpty || message.length > 180) return null;
  // Do not expose SQL/detail payloads or stack-like implementation data.
  final normalized = message.toLowerCase();
  if (normalized.contains('select ') ||
      normalized.contains('insert ') ||
      normalized.contains('update ') ||
      normalized.contains('details:') ||
      normalized.contains('stack trace')) {
    return null;
  }
  return message.endsWith('.') ? message : '$message.';
}
