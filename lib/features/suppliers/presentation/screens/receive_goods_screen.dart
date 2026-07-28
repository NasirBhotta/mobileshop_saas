import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobileshop_saas/features/inventory/data/models/product_model.dart';
import 'package:mobileshop_saas/features/inventory/presentation/providers/inventory_provider.dart';
import 'package:mobileshop_saas/features/suppliers/presentation/providers/procurement_provider.dart';
import '../../data/models/procurement_models.dart';
import '../../domain/supplier_accounting_contract.dart';

class ReceiveGoodsScreen extends ConsumerStatefulWidget {
  final PurchaseOrderModel po;

  const ReceiveGoodsScreen({super.key, required this.po});

  @override
  ConsumerState<ReceiveGoodsScreen> createState() => _ReceiveGoodsScreenState();
}

class _ReceiveGoodsScreenState extends ConsumerState<ReceiveGoodsScreen> {
  final _note = TextEditingController();
  final Map<String, TextEditingController> _qty = {};
  final Map<String, TextEditingController> _cost = {};
  final Map<String, bool> _updateCost = {};
  final Map<String, String?> _resolvedProduct = {};

  @override
  void initState() {
    super.initState();

    for (final item in widget.po.items) {
      _qty[item.id] = TextEditingController();
      _cost[item.id] = TextEditingController(
        text: (item.actualUnitCost ?? item.negotiatedUnitCost).toStringAsFixed(
          0,
        ),
      );
      _updateCost[item.id] = false;
    }
  }

  @override
  void dispose() {
    _note.dispose();
    for (final c in _qty.values) {
      c.dispose();
    }
    for (final c in _cost.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(receiveGoodsControllerProvider);
    final saving = state.isLoading;
    final products =
        ref.watch(productsProvider).value ?? const <ProductModel>[];

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Back to purchase orders',
          onPressed: saving ? null : () => context.go('/purchase-orders'),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: Text('Receive ${widget.po.poNo}'),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 950),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                TextField(
                  controller: _note,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Receipt note optional',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                for (final item in widget.po.items)
                  _ReceiveItemCard(
                    item: item,
                    qtyController: _qty[item.id]!,
                    costController: _cost[item.id]!,
                    updateCost: _updateCost[item.id] ?? false,
                    products: products,
                    resolvedProductId: _resolvedProduct[item.id],
                    onResolvedProductChanged:
                        (value) =>
                            setState(() => _resolvedProduct[item.id] = value),
                    onUpdateCostChanged: (v) {
                      setState(() => _updateCost[item.id] = v);
                    },
                  ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: saving ? null : _submit,
                  icon:
                      saving
                          ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                          : const Icon(Icons.inventory_2_outlined),
                  label: Text(saving ? 'Receiving...' : 'Receive Goods'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    final inputs = <GoodsReceiptItemInput>[];

    for (final item in widget.po.items) {
      final q = int.tryParse(_qty[item.id]!.text.trim()) ?? 0;
      final c = double.tryParse(_cost[item.id]!.text.trim()) ?? -1;

      if (q == 0) continue;

      if (q < 0 || q > item.remainingQuantity) {
        _msg('Invalid quantity for ${item.productName}');
        return;
      }

      if (c < 0) {
        _msg('Invalid cost for ${item.productName}');
        return;
      }

      inputs.add(
        GoodsReceiptItemInput(
          purchaseOrderItemId: item.id,
          receivedQuantity: q,
          actualUnitCost: c,
          updateProductCost: _updateCost[item.id] ?? false,
          resolvedProductId: _resolvedProduct[item.id],
        ),
      );
    }

    if (inputs.isEmpty) {
      _msg('Enter received quantity');
      return;
    }

    final ok = await ref
        .read(receiveGoodsControllerProvider.notifier)
        .receive(po: widget.po, note: _note.text, inputs: inputs);

    if (!mounted) return;

    if (!ok) {
      final error =
          ref.read(receiveGoodsControllerProvider).asError?.error.toString();
      _msg(error ?? 'Goods not received');
      return;
    }

    context.go('/purchase-orders');
  }

  void _msg(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }
}

class _ReceiveItemCard extends StatelessWidget {
  final PurchaseOrderItemModel item;
  final TextEditingController qtyController;
  final TextEditingController costController;
  final bool updateCost;
  final List<ProductModel> products;
  final String? resolvedProductId;
  final ValueChanged<String?> onResolvedProductChanged;
  final ValueChanged<bool> onUpdateCostChanged;

  const _ReceiveItemCard({
    required this.item,
    required this.qtyController,
    required this.costController,
    required this.updateCost,
    required this.products,
    required this.resolvedProductId,
    required this.onResolvedProductChanged,
    required this.onUpdateCostChanged,
  });

  @override
  Widget build(BuildContext context) {
    final remaining = item.remainingQuantity;

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              item.productName,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              'Ordered: ${item.orderedQuantity} | Received: ${item.receivedQuantity} | Remaining: $remaining',
            ),
            const SizedBox(height: 4),
            Text(
              item.productResolution.label,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            if (item.productResolution ==
                PurchaseProductResolution.resolveOnReceipt) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: resolvedProductId,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Add received stock to',
                  border: OutlineInputBorder(),
                ),
                items:
                    products
                        .map(
                          (product) => DropdownMenuItem(
                            value: product.id,
                            child: Text(
                              '${product.name} (${product.sku ?? 'No SKU'})',
                            ),
                          ),
                        )
                        .toList(),
                onChanged: remaining > 0 ? onResolvedProductChanged : null,
              ),
            ],
            if (item.productResolution == PurchaseProductResolution.directUse)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'This increases supplier payable without adding inventory.',
                ),
              ),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (_, constraints) {
                final wide = constraints.maxWidth >= 650;
                final fields = [
                  TextField(
                    controller: qtyController,
                    enabled: remaining > 0,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Receive Qty',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  TextField(
                    controller: costController,
                    enabled: remaining > 0,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Actual Unit Cost',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ];

                if (wide) {
                  return Row(
                    children: [
                      Expanded(child: fields[0]),
                      const SizedBox(width: 12),
                      Expanded(child: fields[1]),
                    ],
                  );
                }

                return Column(
                  children: [fields[0], const SizedBox(height: 12), fields[1]],
                );
              },
            ),
            if (item.productResolution != PurchaseProductResolution.directUse)
              CheckboxListTile(
                value: updateCost,
                onChanged:
                    remaining > 0
                        ? (v) => onUpdateCostChanged(v ?? false)
                        : null,
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'Update product cost price with this actual cost',
                ),
                subtitle: const Text(
                  'Cost price will not change unless this is checked.',
                ),
              ),
          ],
        ),
      ),
    );
  }
}
