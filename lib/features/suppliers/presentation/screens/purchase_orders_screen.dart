import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobileshop_saas/features/suppliers/presentation/providers/procurement_provider.dart';

import '../../../../core/entitlements/entitlement_provider.dart';
import '../../data/models/procurement_models.dart';

class PurchaseOrdersScreen extends ConsumerWidget {
  const PurchaseOrdersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ordersAsync = ref.watch(purchaseOrdersProvider);
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
                  child: LayoutBuilder(
                    builder: (_, constraints) {
                      final isWide = constraints.maxWidth >= 850;

                      if (isWide) {
                        return GridView.builder(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.all(16),
                          gridDelegate:
                              const SliverGridDelegateWithMaxCrossAxisExtent(
                                maxCrossAxisExtent: 430,
                                mainAxisSpacing: 12,
                                crossAxisSpacing: 12,
                                childAspectRatio: 1.45,
                              ),
                          itemCount: orders.length,
                          itemBuilder: (_, i) => _POCard(po: orders[i]),
                        );
                      }

                      return ListView.separated(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.all(12),
                        itemCount: orders.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (_, i) => _POCard(po: orders[i]),
                      );
                    },
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
                        () => context.go('/purchase-orders/receive', extra: po),
                    child: const Text('Receive'),
                  ),
                OutlinedButton(
                  onPressed:
                      () => context.push('/purchase-orders/export', extra: po),
                  child: const Text('Export'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
