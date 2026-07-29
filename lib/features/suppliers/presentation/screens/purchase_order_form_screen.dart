import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobileshop_saas/features/inventory/presentation/providers/inventory_provider.dart';
import 'package:mobileshop_saas/features/suppliers/presentation/providers/procurement_provider.dart';
import 'package:uuid/uuid.dart';
import '../../data/models/procurement_models.dart';
import '../../domain/supplier_accounting_contract.dart';

class PurchaseOrderFormScreen extends ConsumerStatefulWidget {
  final SupplierModel? initialSupplier;

  const PurchaseOrderFormScreen({super.key, this.initialSupplier});

  @override
  ConsumerState<PurchaseOrderFormScreen> createState() =>
      _PurchaseOrderFormScreenState();
}

class _PurchaseOrderFormScreenState
    extends ConsumerState<PurchaseOrderFormScreen> {
  final _notes = TextEditingController();

  String? _supplierId;
  DateTime? _expectedDate;
  final List<_POItemDraft> _items = [];

  @override
  void initState() {
    super.initState();
    _supplierId = widget.initialSupplier?.id;
  }

  @override
  void dispose() {
    _notes.dispose();
    for (final item in _items) {
      item.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final suppliersAsync = ref.watch(suppliersProvider);
    final productsAsync = ref.watch(productsProvider);
    final state = ref.watch(purchaseOrderControllerProvider);
    final saving = state.isLoading;
    final backRoute =
        widget.initialSupplier == null ? '/purchase-orders' : '/suppliers';

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Back',
          onPressed: saving ? null : () => context.go(backRoute),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: const Text('Create Purchase Order'),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 950),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                suppliersAsync.when(
                  loading: () => const LinearProgressIndicator(),
                  error: (e, _) => Text(e.toString()),
                  data: (suppliers) {
                    return DropdownButtonFormField<String>(
                      initialValue: _supplierId,
                      decoration: const InputDecoration(
                        labelText: 'Supplier',
                        border: OutlineInputBorder(),
                      ),
                      items:
                          suppliers
                              .map(
                                (supplier) => DropdownMenuItem(
                                  value: supplier.id,
                                  child: Text(supplier.name),
                                ),
                              )
                              .toList(),
                      onChanged:
                          saving
                              ? null
                              : (v) => setState(() => _supplierId = v),
                    );
                  },
                ),
                const SizedBox(height: 12),
                InkWell(
                  onTap: saving ? null : _pickDate,
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Expected delivery optional',
                      border: OutlineInputBorder(),
                    ),
                    child: Text(
                      _expectedDate == null
                          ? 'Select date'
                          : '${_expectedDate!.day}-${_expectedDate!.month}-${_expectedDate!.year}',
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _notes,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Notes optional',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Items',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                productsAsync.when(
                  loading: () => const LinearProgressIndicator(),
                  error: (e, _) => Text(e.toString()),
                  data: (products) {
                    return Column(
                      children: [
                        for (int i = 0; i < _items.length; i++)
                          _POItemEditor(
                            draft: _items[i],
                            products: products,
                            onChanged: () => setState(() {}),
                            onRemove: () {
                              setState(() {
                                _items[i].dispose();
                                _items.removeAt(i);
                              });
                            },
                          ),
                        const SizedBox(height: 10),
                        OutlinedButton.icon(
                          onPressed:
                              saving
                                  ? null
                                  : () {
                                    setState(() {
                                      _items.add(_POItemDraft());
                                    });
                                  },
                          icon: const Icon(Icons.add),
                          label: const Text('Add Product'),
                        ),
                      ],
                    );
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
                          : const Icon(Icons.save),
                  label: Text(saving ? 'Saving...' : 'Create Draft PO'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _expectedDate ?? now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );

    if (picked != null) setState(() => _expectedDate = picked);
  }

  Future<void> _submit() async {
    if (_supplierId == null) {
      _message('Select supplier');
      return;
    }

    if (_items.isEmpty) {
      _message('Add at least one product');
      return;
    }

    final items = <PurchaseOrderItemModel>[];

    for (final draft in _items) {
      if (draft.resolution == PurchaseProductResolution.existingProduct &&
          draft.productId == null) {
        _message('Select an existing product in every linked row');
        return;
      }
      if (draft.resolution != PurchaseProductResolution.existingProduct &&
          draft.name.text.trim().isEmpty) {
        _message('Enter an item name in every unlinked row');
        return;
      }

      final qty = int.tryParse(draft.quantity.text.trim()) ?? 0;
      final cost = double.tryParse(draft.cost.text.trim()) ?? -1;

      if (qty <= 0 || cost < 0) {
        _message('Enter valid quantity and cost');
        return;
      }

      items.add(
        PurchaseOrderItemModel(
          id: const Uuid().v4(),
          tenantId: '',
          purchaseOrderId: '',
          productId: draft.productId,
          productResolution: draft.resolution,
          productDraft:
              draft.resolution == PurchaseProductResolution.createOnReceipt
                  ? {
                    'name': draft.name.text.trim(),
                    'sku':
                        draft.sku.text.trim().isEmpty
                            ? null
                            : draft.sku.text.trim(),
                    'sale_price':
                        double.tryParse(draft.salePrice.text.trim()) ?? 0,
                  }
                  : null,
          productName:
              draft.resolution == PurchaseProductResolution.existingProduct
                  ? draft.productName ?? ''
                  : draft.name.text.trim(),
          productSku: draft.productSku,
          orderedQuantity: qty,
          negotiatedUnitCost: cost,
          lineTotal: qty * cost,
        ),
      );
    }

    final po = await ref
        .read(purchaseOrderControllerProvider.notifier)
        .createPO(
          supplierId: _supplierId!,
          expectedDeliveryAt: _expectedDate,
          notes: _notes.text,
          items: items,
        );

    if (!mounted) return;

    if (po == null) {
      final error =
          ref.read(purchaseOrderControllerProvider).asError?.error.toString();
      _message(error ?? 'PO not created');
      return;
    }

    context.go('/purchase-orders');
  }

  void _message(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }
}

class _POItemEditor extends StatelessWidget {
  final _POItemDraft draft;
  final List<dynamic> products;
  final VoidCallback onRemove;
  final VoidCallback onChanged;

  const _POItemEditor({
    required this.draft,
    required this.products,
    required this.onRemove,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: LayoutBuilder(
          builder: (_, constraints) {
            final wide = constraints.maxWidth >= 720;

            final productFields = <Widget>[
              DropdownButtonFormField<PurchaseProductResolution>(
                initialValue: draft.resolution,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Item handling',
                  border: OutlineInputBorder(),
                ),
                items:
                    PurchaseProductResolution.values
                        .map(
                          (value) => DropdownMenuItem(
                            value: value,
                            child: Text(
                              value.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                onChanged: (value) {
                  if (value == null) return;
                  draft.resolution = value;
                  draft.productId = null;
                  onChanged();
                },
              ),
              if (draft.resolution == PurchaseProductResolution.existingProduct)
                DropdownButtonFormField<String>(
                  initialValue: draft.productId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Product',
                    border: OutlineInputBorder(),
                  ),
                  items:
                      products.map<DropdownMenuItem<String>>((product) {
                        return DropdownMenuItem<String>(
                          value: product.id as String,
                          child: Text(
                            '${product.name} (${product.sku ?? 'No SKU'})',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      }).toList(),
                  onChanged: (v) {
                    final product = products.firstWhere((p) => p.id == v);
                    draft.productId = product.id as String;
                    draft.productName = product.name as String;
                    draft.productSku = product.sku as String?;
                    onChanged();
                  },
                ),
              if (draft.resolution != PurchaseProductResolution.existingProduct)
                TextField(
                  controller: draft.name,
                  decoration: const InputDecoration(
                    labelText: 'Item name',
                    border: OutlineInputBorder(),
                  ),
                ),
              if (draft.resolution ==
                  PurchaseProductResolution.createOnReceipt) ...[
                TextField(
                  controller: draft.sku,
                  decoration: const InputDecoration(
                    labelText: 'SKU optional',
                    border: OutlineInputBorder(),
                  ),
                ),
                TextField(
                  controller: draft.salePrice,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Sale price',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ];
            final quantityFields = <Widget>[
              TextField(
                controller: draft.quantity,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Qty',
                  border: OutlineInputBorder(),
                ),
              ),
              TextField(
                controller: draft.cost,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Unit Cost',
                  border: OutlineInputBorder(),
                ),
              ),
            ];

            if (wide) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final field in productFields)
                        SizedBox(width: 280, child: field),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(child: quantityFields[0]),
                      const SizedBox(width: 8),
                      Expanded(child: quantityFields[1]),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed: onRemove,
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('Remove'),
                      ),
                    ],
                  ),
                ],
              );
            }

            return Column(
              children: [
                for (final field in [...productFields, ...quantityFields]) ...[
                  field,
                  const SizedBox(height: 8),
                ],
                OutlinedButton.icon(
                  onPressed: onRemove,
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Remove'),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _POItemDraft {
  PurchaseProductResolution resolution =
      PurchaseProductResolution.existingProduct;
  String? productId;
  String? productName;
  String? productSku;

  final quantity = TextEditingController();
  final cost = TextEditingController();
  final name = TextEditingController();
  final sku = TextEditingController();
  final salePrice = TextEditingController();

  void dispose() {
    quantity.dispose();
    cost.dispose();
    name.dispose();
    sku.dispose();
    salePrice.dispose();
  }
}
