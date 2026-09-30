import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/offline/offline_store.dart';
import '../../../../shared/widgets/barcode_camera_scanner.dart';
import '../../../inventory/data/models/product_model.dart';
import '../../../inventory/presentation/providers/inventory_provider.dart';
import '../../../repairs/data/models/inventory_unit_model.dart';
import '../../data/models/cart_item_model.dart';
import '../providers/pos_provider.dart';

class PhoneUnitOption {
  final String imei;
  final String? details;
  final double price;
  final double? cost;
  final String? unitId;
  final bool isUsed;

  const PhoneUnitOption({
    required this.imei,
    this.details,
    required this.price,
    this.cost,
    this.unitId,
    this.isUsed = false,
  });
}

class ProductUnitPickerDialog extends ConsumerStatefulWidget {
  final ProductModel product;

  const ProductUnitPickerDialog({super.key, required this.product});

  static Future<void> show(BuildContext context, ProductModel product) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => ProductUnitPickerDialog(product: product),
    );
  }

  @override
  ConsumerState<ProductUnitPickerDialog> createState() => _ProductUnitPickerDialogState();
}

class _ProductUnitPickerDialogState extends ConsumerState<ProductUnitPickerDialog> {
  final _manualImeiController = TextEditingController();
  bool _isLoading = true;
  List<PhoneUnitOption> _units = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadAvailableUnits();
  }

  @override
  void dispose() {
    _manualImeiController.dispose();
    super.dispose();
  }

  Future<void> _loadAvailableUnits() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final branchId = widget.product.branchId.isNotEmpty
          ? widget.product.branchId
          : 'default_branch';

      final options = <PhoneUnitOption>[];
      final seenImeis = <String>{};

      // 1. Fetch used phone buy-in records for this product
      final allPurchases = await OfflineStore.loadCustomerPurchases(branchId);
      final productPurchases = allPurchases.where(
        (p) => p.productId == widget.product.id && p.status == 'in_stock',
      );

      for (final p in productPurchases) {
        final imei = p.imei1.trim();
        if (imei.isNotEmpty && !seenImeis.contains(imei)) {
          seenImeis.add(imei);
          final specs = [
            p.storage,
            p.color,
            p.deviceCondition != null ? 'Cond: ${p.deviceCondition}' : null,
          ].where((e) => e != null && e.trim().isNotEmpty).join(' • ');

          options.add(
            PhoneUnitOption(
              imei: imei,
              details: specs.isNotEmpty ? specs : 'Second-Hand Buy-In',
              price: p.expectedSalePrice > 0 ? p.expectedSalePrice : widget.product.salePrice,
              cost: p.purchasePrice,
              unitId: p.id,
              isUsed: true,
            ),
          );
        }
      }

      // 2. Fetch inventory units for this product
      final invUnits = await ref
          .read(inventoryRepositoryProvider)
          .fetchProductImeiUnits(widget.product.id);

      for (final u in invUnits) {
        final imei = u.imei.trim();
        if (u.status == InventoryUnitStatus.available &&
            imei.isNotEmpty &&
            !seenImeis.contains(imei)) {
          seenImeis.add(imei);
          options.add(
            PhoneUnitOption(
              imei: imei,
              details: widget.product.description?.trim().isNotEmpty == true
                  ? widget.product.description!.trim()
                  : null,
              price: widget.product.salePrice,
              cost: widget.product.costPrice,
              unitId: u.id,
              isUsed: false,
            ),
          );
        }
      }

      if (mounted) {
        setState(() {
          _units = options;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  void _selectUnit(PhoneUnitOption unit) {
    final cartItems = ref.read(cartProvider).items;
    final inCart = cartItems.any(
      (item) => item.imei != null && item.imei!.trim().toLowerCase() == unit.imei.trim().toLowerCase(),
    );

    if (inCart) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Yeh IMEI (${unit.imei}) pehle se cart mein shamil hai.'),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }

    final cartItem = CartItemModel(
      productId: widget.product.id,
      productName: widget.product.name,
      productSku: widget.product.sku,
      unitPrice: unit.price,
      unitCost: unit.cost ?? widget.product.costPrice,
      quantity: 1,
      availableStock: 1,
      imei: unit.imei,
      deviceDetails: unit.details,
      unitId: unit.unitId,
    );

    ref.read(cartProvider.notifier).addItem(cartItem);
    Navigator.of(context).pop();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${widget.product.name} (IMEI: ${unit.imei}) cart mein add ho gaya'),
        backgroundColor: AppColors.success,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _submitManualImei() {
    final imei = _manualImeiController.text.trim();
    if (imei.isEmpty) return;

    // Check if entered IMEI matches any existing unit
    final matched = _units.where(
      (u) => u.imei.toLowerCase() == imei.toLowerCase(),
    ).firstOrNull;

    if (matched != null) {
      _selectUnit(matched);
    } else {
      _selectUnit(
        PhoneUnitOption(
          imei: imei,
          details: widget.product.description?.trim().isNotEmpty == true
              ? widget.product.description!.trim()
              : null,
          price: widget.product.salePrice,
          cost: widget.product.costPrice,
          isUsed: false,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cartItems = ref.watch(cartProvider).items;

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.only(
        top: 20,
        left: 16,
        right: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primary.withAlpha(25),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.phone_iphone_rounded, color: AppColors.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.product.name,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      'Exact Phone Unit / IMEI Select Karein',
                      style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // ── Quick Barcode / IMEI Scan Field ──
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _manualImeiController,
                  decoration: InputDecoration(
                    hintText: 'Scan ya type IMEI...',
                    prefixIcon: const Icon(Icons.qr_code_rounded, size: 20),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onSubmitted: (_) => _submitManualImei(),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                icon: const Icon(Icons.qr_code_scanner_rounded),
                tooltip: 'Camera Scanner',
                onPressed: () async {
                  final code = await BarcodeCameraScanner.open(context);
                  if (code != null && code.isNotEmpty) {
                    _manualImeiController.text = code.trim();
                    _submitManualImei();
                  }
                },
              ),
              const SizedBox(width: 4),
              FilledButton(
                onPressed: _submitManualImei,
                child: const Text('Add'),
              ),
            ],
          ),
          const SizedBox(height: 16),

          const Divider(),

          // ── Available Units List ──
          if (_isLoading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(24.0),
                child: CircularProgressIndicator(),
              ),
            )
          else if (_error != null)
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                'Units load error: $_error',
                style: const TextStyle(color: AppColors.error),
                textAlign: TextAlign.center,
              ),
            )
          else if (_units.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                children: const [
                  Icon(Icons.inventory_2_outlined, size: 36, color: AppColors.textHint),
                  SizedBox(height: 8),
                  Text(
                    'No registered IMEI units found.\nUpar IMEI type ya scan karke add karein.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                  ),
                ],
              ),
            )
          else
            Flexible(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 280),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _units.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final unit = _units[index];
                    final inCart = cartItems.any(
                      (item) => item.imei != null && item.imei!.trim().toLowerCase() == unit.imei.toLowerCase(),
                    );

                    return Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: inCart ? AppColors.surfaceVariant : AppColors.surface,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: inCart ? AppColors.primary : AppColors.border,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            unit.isUsed ? Icons.phonelink_setup_rounded : Icons.phone_android_rounded,
                            color: unit.isUsed ? Colors.orange : AppColors.primary,
                            size: 24,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      'IMEI: ${unit.imei}',
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                    ),
                                    if (unit.isUsed) ...[
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                        decoration: BoxDecoration(
                                          color: Colors.orange.withAlpha(30),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: const Text(
                                          'Used Phone',
                                          style: TextStyle(fontSize: 10, color: Colors.orange, fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                if (unit.details != null && unit.details!.isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    unit.details!,
                                    style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                                  ),
                                ],
                                const SizedBox(height: 2),
                                Text(
                                  'Rs. ${unit.price.toStringAsFixed(0)}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.primary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (inCart)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withAlpha(20),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text(
                                'In Cart',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.primary,
                                ),
                              ),
                            )
                          else
                            FilledButton.tonal(
                              onPressed: () => _selectUnit(unit),
                              child: const Text('Select'),
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }
}
