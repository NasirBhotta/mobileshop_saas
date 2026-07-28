import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobileshop_saas/features/inventory/data/models/product_model.dart';
import 'package:mobileshop_saas/features/inventory/presentation/providers/inventory_provider.dart';
import 'package:mobileshop_saas/features/repairs/data/models/repair_part_model.dart';
import 'package:mobileshop_saas/features/repairs/data/models/repair_ticket_model.dart';
import 'package:mobileshop_saas/features/repairs/domain/repair_accounting_contract.dart';
import 'package:mobileshop_saas/features/repairs/presentation/providers/repair_provider.dart';
import 'package:mobileshop_saas/features/suppliers/data/models/procurement_models.dart';
import 'package:mobileshop_saas/features/suppliers/presentation/providers/procurement_provider.dart';
import 'package:uuid/uuid.dart';

Future<bool> showRepairCompletionDialog(
  BuildContext context,
  WidgetRef ref,
  RepairTicketModel ticket,
) async {
  return await showDialog<bool>(
        context: context,
        builder: (_) => _RepairCompletionDialog(ticket: ticket),
      ) ??
      false;
}

class _RepairCompletionDialog extends ConsumerStatefulWidget {
  final RepairTicketModel ticket;

  const _RepairCompletionDialog({required this.ticket});

  @override
  ConsumerState<_RepairCompletionDialog> createState() =>
      _RepairCompletionDialogState();
}

class _RepairCompletionDialogState
    extends ConsumerState<_RepairCompletionDialog> {
  final _charge = TextEditingController();
  final _service = TextEditingController(text: '0');
  final _discount = TextEditingController(text: '0');
  final _commission = TextEditingController(text: '0');
  final _otherCost = TextEditingController(text: '0');
  final List<_PartDraft> _parts = [];
  bool _advanced = false;
  bool _saving = false;
  bool _chargeManuallyEdited = false;

  @override
  void initState() {
    super.initState();
    final amount = widget.ticket.totalCost ?? widget.ticket.estimatedCost;
    if (amount != null) {
      _service.text = amount.toStringAsFixed(0);
      _charge.text = amount.toStringAsFixed(0);
    }
  }

  @override
  void dispose() {
    for (final draft in _parts) {
      draft.dispose();
    }
    _charge.dispose();
    _service.dispose();
    _discount.dispose();
    _commission.dispose();
    _otherCost.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final products =
        ref.watch(productsProvider).value ?? const <ProductModel>[];
    final suppliers =
        ref.watch(suppliersProvider).value ?? const <SupplierModel>[];
    final charge = _number(_charge);
    final inventoryCost = _parts
        .where((part) => part.source == RepairPartSource.inventory)
        .fold<double>(0, (sum, part) => sum + part.totalCost);
    final directCost = _parts
        .where((part) => part.source == RepairPartSource.directPurchase)
        .fold<double>(0, (sum, part) => sum + part.totalCost);
    final partsCharge = _parts.fold<double>(
      0,
      (sum, part) => sum + part.totalCharge,
    );
    final profit = RepairAccountingContract.grossProfit(
      customerCharge: charge,
      inventoryPartsCost: inventoryCost,
      directPartsCost: directCost,
      perJobCommission: _number(_commission),
      otherDirectCost: _number(_otherCost),
    );

    return AlertDialog(
      title: const Text('Complete Repair'),
      content: SizedBox(
        width: 760,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Parts are consumed and profit is finalized only after confirmation.',
              ),
              const SizedBox(height: 12),
              for (var index = 0; index < _parts.length; index++)
                _PartEditor(
                  draft: _parts[index],
                  products: products,
                  suppliers: suppliers,
                  onChanged: _partOrChargeComponentChanged,
                  onRemove: () {
                    setState(() {
                      _parts[index].dispose();
                      _parts.removeAt(index);
                    });
                    _syncSuggestedCharge();
                  },
                ),
              OutlinedButton.icon(
                onPressed:
                    _saving
                        ? null
                        : () => setState(() => _parts.add(_PartDraft())),
                icon: const Icon(Icons.add_rounded),
                label: const Text('Add Part'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _charge,
                onChanged: (_) {
                  _chargeManuallyEdited = true;
                  setState(() {});
                },
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: 'Final bill total (including parts)',
                  helperText:
                      _chargeManuallyEdited
                          ? 'Manually adjusted. Tap calculate to restore the suggested total.'
                          : 'Parts + service charge - discount',
                  prefixText: 'Rs ',
                  suffixIcon:
                      _chargeManuallyEdited
                          ? IconButton(
                            tooltip: 'Use calculated total',
                            onPressed: () {
                              _chargeManuallyEdited = false;
                              _syncSuggestedCharge();
                            },
                            icon: const Icon(Icons.calculate_outlined),
                          )
                          : null,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _amountField(
                    _service,
                    'Repair / service charge',
                    affectsCustomerTotal: true,
                  ),
                  _amountField(
                    _discount,
                    'Discount',
                    affectsCustomerTotal: true,
                  ),
                ],
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _advanced,
                onChanged:
                    _saving
                        ? null
                        : (value) => setState(() => _advanced = value),
                title: const Text('Optional advanced charges & costs'),
              ),
              if (_advanced)
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _amountField(_commission, 'Per-job commission'),
                    _amountField(_otherCost, 'Other direct cost'),
                  ],
                ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Wrap(
                    spacing: 24,
                    runSpacing: 8,
                    children: [
                      Text('Customer total: Rs ${charge.toStringAsFixed(0)}'),
                      Text(
                        'Parts customer price: Rs ${partsCharge.toStringAsFixed(0)}',
                      ),
                      Text(
                        'Parts cost: Rs ${(inventoryCost + directCost).toStringAsFixed(0)}',
                      ),
                      Text(
                        'Gross profit: Rs ${profit.toStringAsFixed(0)}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Back'),
        ),
        FilledButton(
          onPressed: _saving ? null : () => _complete(products),
          child: Text(_saving ? 'Completing...' : 'Confirm Completion'),
        ),
      ],
    );
  }

  Widget _amountField(
    TextEditingController controller,
    String label, {
    bool affectsCustomerTotal = false,
  }) => SizedBox(
    width: 210,
    child: TextField(
      controller: controller,
      onChanged:
          (_) =>
              affectsCustomerTotal
                  ? _partOrChargeComponentChanged()
                  : setState(() {}),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: label,
        prefixText: 'Rs ',
        border: const OutlineInputBorder(),
      ),
    ),
  );

  void _partOrChargeComponentChanged() {
    if (!_chargeManuallyEdited) _syncSuggestedCharge();
    setState(() {});
  }

  void _syncSuggestedCharge() {
    final partsCharge = _parts.fold<double>(
      0,
      (sum, part) => sum + part.totalCharge,
    );
    final suggested = (partsCharge + _number(_service) - _number(_discount))
        .clamp(0, double.infinity);
    _charge.text = suggested.toStringAsFixed(
      suggested == suggested.roundToDouble() ? 0 : 2,
    );
  }

  Future<void> _complete(List<ProductModel> products) async {
    final charge = double.tryParse(_charge.text.trim());
    if (charge == null || charge < 0) return _message('Enter a valid charge.');
    final now = DateTime.now();
    final parts = <RepairPartModel>[];
    for (final draft in _parts) {
      final qty = int.tryParse(draft.quantity.text.trim()) ?? 0;
      final cost = double.tryParse(draft.cost.text.trim()) ?? -1;
      final sale = double.tryParse(draft.sale.text.trim()) ?? -1;
      final product =
          draft.productId == null
              ? null
              : products
                  .where((item) => item.id == draft.productId)
                  .firstOrNull;
      final name =
          draft.source == RepairPartSource.inventory
              ? product?.name
              : draft.name.text.trim();
      if (qty <= 0 ||
          cost < 0 ||
          sale < 0 ||
          name == null ||
          name.isEmpty ||
          (draft.settlementType == 'supplier_payable' &&
              draft.supplierId == null)) {
        return _message('Complete all part details with valid amounts.');
      }
      parts.add(
        RepairPartModel(
          id: const Uuid().v4(),
          tenantId: widget.ticket.tenantId,
          branchId: widget.ticket.branchId,
          ticketId: widget.ticket.id,
          sourceType:
              draft.source == RepairPartSource.inventory
                  ? 'inventory'
                  : 'direct_purchase',
          productId: draft.productId,
          supplierId: draft.supplierId,
          settlementType: draft.settlementType,
          name: name,
          quantity: qty,
          unitCostSnapshot: cost,
          unitSalePrice: sale,
          createdBy: widget.ticket.createdBy,
          createdAt: now,
          updatedAt: now,
        ),
      );
    }
    setState(() => _saving = true);
    final result = await ref
        .read(repairTicketControllerProvider.notifier)
        .completeRepair(
          ticket: widget.ticket,
          parts: parts,
          customerCharge: charge,
          serviceCharge: _number(_service),
          discount: _number(_discount),
          commission: _number(_commission),
          otherDirectCost: _number(_otherCost),
        );
    if (!mounted) return;
    if (result == null) {
      setState(() => _saving = false);
      return _message(
        ref.read(repairTicketControllerProvider).asError?.error.toString() ??
            'Repair could not be completed.',
      );
    }
    Navigator.of(context).pop(true);
  }

  double _number(TextEditingController controller) =>
      double.tryParse(controller.text.trim()) ?? 0;

  void _message(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
}

class _PartEditor extends StatelessWidget {
  final _PartDraft draft;
  final List<ProductModel> products;
  final List<SupplierModel> suppliers;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  const _PartEditor({
    required this.draft,
    required this.products,
    required this.suppliers,
    required this.onChanged,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(10),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: SegmentedButton<RepairPartSource>(
                  segments: const [
                    ButtonSegment(
                      value: RepairPartSource.inventory,
                      label: Text('Inventory'),
                    ),
                    ButtonSegment(
                      value: RepairPartSource.directPurchase,
                      label: Text('Direct purchase'),
                    ),
                  ],
                  selected: {draft.source},
                  onSelectionChanged: (value) {
                    draft.source = value.single;
                    draft.productId = null;
                    onChanged();
                  },
                ),
              ),
              IconButton(
                onPressed: onRemove,
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (draft.source == RepairPartSource.inventory)
            DropdownButtonFormField<String>(
              initialValue: draft.productId,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Inventory product',
                border: OutlineInputBorder(),
              ),
              items:
                  products
                      .map(
                        (product) => DropdownMenuItem(
                          value: product.id,
                          child: Text(
                            '${product.name} • Stock ${product.stock}',
                          ),
                        ),
                      )
                      .toList(),
              onChanged: (value) {
                draft.productId = value;
                final product =
                    products.where((item) => item.id == value).firstOrNull;
                if (product != null) {
                  draft.cost.text = product.costPrice.toStringAsFixed(0);
                  draft.sale.text = product.salePrice.toStringAsFixed(0);
                }
                onChanged();
              },
            )
          else ...[
            TextField(
              controller: draft.name,
              decoration: const InputDecoration(
                labelText: 'Part name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: draft.settlementType,
              decoration: const InputDecoration(
                labelText: 'Purchase settlement',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(
                  value: 'already_recorded',
                  child: Text('Cost already recorded'),
                ),
                DropdownMenuItem(
                  value: 'supplier_payable',
                  child: Text('Add to supplier payable'),
                ),
              ],
              onChanged: (value) {
                draft.settlementType = value ?? 'already_recorded';
                draft.supplierId = null;
                onChanged();
              },
            ),
            if (draft.settlementType == 'supplier_payable') ...[
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: draft.supplierId,
                isExpanded: true,
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
                onChanged: (value) => draft.supplierId = value,
              ),
            ],
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _field(draft.quantity, 'Qty')),
              const SizedBox(width: 8),
              Expanded(child: _field(draft.cost, 'Unit cost')),
              const SizedBox(width: 8),
              Expanded(child: _field(draft.sale, 'Customer price')),
            ],
          ),
        ],
      ),
    ),
  );

  Widget _field(TextEditingController controller, String label) => TextField(
    controller: controller,
    onChanged: (_) => onChanged(),
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    decoration: InputDecoration(
      labelText: label,
      border: const OutlineInputBorder(),
    ),
  );
}

class _PartDraft {
  RepairPartSource source = RepairPartSource.inventory;
  String? productId;
  String? supplierId;
  String settlementType = 'already_recorded';
  final name = TextEditingController();
  final quantity = TextEditingController(text: '1');
  final cost = TextEditingController();
  final sale = TextEditingController();

  double get totalCost =>
      (int.tryParse(quantity.text) ?? 0) * (double.tryParse(cost.text) ?? 0);
  double get totalCharge =>
      (int.tryParse(quantity.text) ?? 0) * (double.tryParse(sale.text) ?? 0);

  void dispose() {
    name.dispose();
    quantity.dispose();
    cost.dispose();
    sale.dispose();
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
