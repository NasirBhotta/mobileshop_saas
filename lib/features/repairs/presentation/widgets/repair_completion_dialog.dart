import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobileshop_saas/core/constants/app_strings.dart';
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
  final List<_PartDraft> _retiredParts = [];
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
    for (final draft in _retiredParts) {
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
      title: const Text(AppStrings.repairCompleteTitle),
      content: SizedBox(
        width: 760,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(AppStrings.repairCompletionInfo),
              const SizedBox(height: 12),
              for (var index = 0; index < _parts.length; index++)
                _PartEditor(
                  draft: _parts[index],
                  products: products,
                  suppliers: suppliers,
                  onChanged: _partOrChargeComponentChanged,
                  onRemove: () {
                    setState(() {
                      _retiredParts.add(_parts.removeAt(index));
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
                label: const Text(AppStrings.repairAddPart),
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
                  labelText: AppStrings.repairFinalBill,
                  helperText:
                      _chargeManuallyEdited
                          ? AppStrings.repairManualTotalHelper
                          : AppStrings.repairFinalBillHelper,
                  prefixText: AppStrings.customerCreditLimitPrefix,
                  suffixIcon:
                      _chargeManuallyEdited
                          ? IconButton(
                            tooltip: AppStrings.repairUseCalculatedTotal,
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
                    AppStrings.repairServiceCharge,
                    affectsCustomerTotal: true,
                  ),
                  _amountField(
                    _discount,
                    AppStrings.repairDiscount,
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
                title: const Text(AppStrings.repairAdvancedCharges),
              ),
              if (_advanced)
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _amountField(_commission, AppStrings.repairCommission),
                    _amountField(_otherCost, AppStrings.repairOtherDirectCost),
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
                      Text(AppStrings.repairCustomerTotal(charge)),
                      Text(AppStrings.repairPartsCustomerPrice(partsCharge)),
                      Text(
                        AppStrings.repairPartsCost(inventoryCost + directCost),
                      ),
                      Text(
                        AppStrings.repairGrossProfit(profit),
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
          child: const Text(AppStrings.repairBack),
        ),
        FilledButton(
          onPressed: _saving ? null : () => _complete(products),
          child: Text(
            _saving
                ? AppStrings.repairCompleting
                : AppStrings.repairConfirmCompletion,
          ),
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
        prefixText: AppStrings.customerCreditLimitPrefix,
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
    if (charge == null || charge < 0) {
      return _message(AppStrings.repairInvalidCharge);
    }
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
        return _message(AppStrings.repairInvalidPartDetails);
      }
      if (draft.source == RepairPartSource.inventory &&
          product != null &&
          qty > product.stock) {
        return _message(
          AppStrings.repairStockAvailable(product.name, product.stock),
        );
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
            AppStrings.repairCompletionFailed,
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
                      label: Text(AppStrings.repairInventory),
                    ),
                    ButtonSegment(
                      value: RepairPartSource.directPurchase,
                      label: Text(AppStrings.repairDirectPurchase),
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
            _InventoryProductPicker(
              selectedProduct:
                  products
                      .where((item) => item.id == draft.productId)
                      .firstOrNull,
              products: products,
              onSelected: (product) {
                draft.productId = product.id;
                draft.cost.text = product.costPrice.toStringAsFixed(0);
                draft.sale.text = product.salePrice.toStringAsFixed(0);
                onChanged();
              },
            )
          else ...[
            TextField(
              controller: draft.name,
              decoration: const InputDecoration(
                labelText: AppStrings.repairPartName,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: draft.settlementType,
              decoration: const InputDecoration(
                labelText: AppStrings.repairPurchaseSettlement,
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(
                  value: 'already_recorded',
                  child: Text(AppStrings.repairCostAlreadyRecorded),
                ),
                DropdownMenuItem(
                  value: 'supplier_payable',
                  child: Text(AppStrings.repairAddSupplierPayable),
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
                  labelText: AppStrings.repairSupplier,
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
              Expanded(
                child: _field(draft.quantity, AppStrings.repairQuantity),
              ),
              const SizedBox(width: 8),
              Expanded(child: _field(draft.cost, AppStrings.repairUnitCost)),
              const SizedBox(width: 8),
              Expanded(
                child: _field(draft.sale, AppStrings.repairCustomerPrice),
              ),
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

class _InventoryProductPicker extends StatelessWidget {
  final ProductModel? selectedProduct;
  final List<ProductModel> products;
  final ValueChanged<ProductModel> onSelected;

  const _InventoryProductPicker({
    required this.selectedProduct,
    required this.products,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final selected = selectedProduct;
    return InkWell(
      borderRadius: BorderRadius.circular(4),
      onTap: () async {
        final product = await _showInventoryProductSearch(context, products);
        if (context.mounted && product != null) onSelected(product);
      },
      child: InputDecorator(
        decoration: const InputDecoration(
          labelText: AppStrings.repairInventoryProduct,
          hintText: AppStrings.repairInventorySearchHint,
          border: OutlineInputBorder(),
          suffixIcon: Icon(Icons.search_rounded),
        ),
        child:
            selected == null
                ? const Text(
                  AppStrings.repairTapInventorySearch,
                  style: TextStyle(color: Colors.black54),
                )
                : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      selected.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      AppStrings.repairInventorySummary(
                        selected.stock,
                        selected.costPrice,
                        selected.sku,
                      ),
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.black54,
                      ),
                    ),
                  ],
                ),
      ),
    );
  }
}

Future<ProductModel?> _showInventoryProductSearch(
  BuildContext context,
  List<ProductModel> products,
) {
  return showDialog<ProductModel>(
    context: context,
    builder: (_) => _InventoryProductSearchDialog(products: products),
  );
}

class _InventoryProductSearchDialog extends StatefulWidget {
  final List<ProductModel> products;

  const _InventoryProductSearchDialog({required this.products});

  @override
  State<_InventoryProductSearchDialog> createState() =>
      _InventoryProductSearchDialogState();
}

class _InventoryProductSearchDialogState
    extends State<_InventoryProductSearchDialog> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final matches = _searchRepairInventoryProducts(widget.products, _query);
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620, maxHeight: 620),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      AppStrings.repairSearchInventoryPart,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: AppStrings.repairClose,
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _search,
                autofocus: true,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: AppStrings.repairProductSearchHint,
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon:
                      _query.isEmpty
                          ? null
                          : IconButton(
                            tooltip: AppStrings.repairClearSearch,
                            onPressed: () {
                              _search.clear();
                              setState(() => _query = '');
                            },
                            icon: const Icon(Icons.clear_rounded),
                          ),
                  border: const OutlineInputBorder(),
                ),
                onChanged: (value) => setState(() => _query = value),
              ),
              const SizedBox(height: 8),
              Text(
                _query.trim().isEmpty
                    ? AppStrings.repairSearchInventoryPrompt
                    : AppStrings.repairMatchingItems(matches.length),
                style: const TextStyle(fontSize: 12, color: Colors.black54),
              ),
              const SizedBox(height: 8),
              Expanded(
                child:
                    _query.trim().isEmpty
                        ? const Center(
                          child: Text(AppStrings.repairTypeInventoryPrompt),
                        )
                        : matches.isEmpty
                        ? const Center(
                          child: Text(AppStrings.repairNoInventoryMatch),
                        )
                        : ListView.separated(
                          itemCount: matches.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final product = matches[index];
                            return ListTile(
                              leading: const Icon(Icons.inventory_2_outlined),
                              title: Text(product.name),
                              subtitle: Text(
                                [
                                  if (product.sku?.isNotEmpty == true)
                                    AppStrings.repairSku(product.sku!),
                                  if (product.categoryName?.isNotEmpty == true)
                                    product.categoryName!,
                                  AppStrings.repairCost(product.costPrice),
                                ].join(AppStrings.customerDetailSeparator),
                              ),
                              trailing: Text(
                                AppStrings.repairStock(product.stock),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              onTap: () => Navigator.pop(context, product),
                            );
                          },
                        ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

List<ProductModel> _searchRepairInventoryProducts(
  List<ProductModel> products,
  String rawQuery,
) {
  final query = rawQuery.trim().toLowerCase();
  if (query.isEmpty) return const [];
  final tokens = query.split(RegExp(r'\s+'));
  final matches =
      products.where((product) {
        if (!product.isActive || product.stock <= 0) return false;
        final searchable =
            [
              product.name,
              product.sku ?? '',
              product.barcode ?? '',
              product.categoryName ?? '',
            ].join(' ').toLowerCase();
        return tokens.every(searchable.contains);
      }).toList();
  matches.sort((a, b) {
    int rank(ProductModel product) {
      final name = product.name.toLowerCase();
      final sku = product.sku?.toLowerCase();
      final barcode = product.barcode?.toLowerCase();
      if (sku == query || barcode == query) return 0;
      if (name == query) return 1;
      if (name.startsWith(query)) return 2;
      if (sku?.startsWith(query) == true) return 3;
      return 4;
    }

    final rankCompare = rank(a).compareTo(rank(b));
    if (rankCompare != 0) return rankCompare;
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  });
  return matches.take(50).toList();
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
