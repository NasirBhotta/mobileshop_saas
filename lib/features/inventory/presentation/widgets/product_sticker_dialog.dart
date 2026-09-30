import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/barcode_generator.dart';
import '../../../buyin/data/models/customer_purchase_model.dart';
import '../../../settings/presentation/providers/receipt_settings_provider.dart';
import '../../data/models/product_model.dart';
import '../../data/services/product_sticker_service.dart';
import '../providers/inventory_provider.dart';

class ProductStickerDialog extends ConsumerStatefulWidget {
  final ProductModel? product;
  final CustomerPurchaseModel? purchase;
  final String? initialImei;
  final String? initialDetails;

  const ProductStickerDialog({
    super.key,
    this.product,
    this.purchase,
    this.initialImei,
    this.initialDetails,
  }) : assert(product != null || purchase != null, 'Either product or purchase must be provided');

  static Future<void> show(
    BuildContext context, {
    ProductModel? product,
    CustomerPurchaseModel? purchase,
    String? imei,
    String? details,
  }) {
    return showDialog(
      context: context,
      builder: (ctx) => ProductStickerDialog(
        product: product,
        purchase: purchase,
        initialImei: imei,
        initialDetails: details,
      ),
    );
  }

  @override
  ConsumerState<ProductStickerDialog> createState() => _ProductStickerDialogState();
}

class _ProductStickerDialogState extends ConsumerState<ProductStickerDialog> {
  int _copies = 1;
  bool _isPrinting = false;

  String get _title => widget.product?.name ?? widget.purchase?.productName ?? '';

  String get _barcode {
    if (widget.purchase != null) return widget.purchase!.imei1.trim();
    if (widget.initialImei != null && widget.initialImei!.isNotEmpty) return widget.initialImei!.trim();
    return BarcodeGenerator.ensureBarcode(widget.product?.barcode);
  }

  String? get _details {
    if (widget.initialDetails != null && widget.initialDetails!.isNotEmpty) {
      return widget.initialDetails;
    }
    if (widget.purchase != null) {
      final p = widget.purchase!;
      return [
        p.storage,
        p.color,
        p.deviceCondition != null ? 'Cond: ${p.deviceCondition}' : null,
      ].where((e) => e != null && e.trim().isNotEmpty).join(' • ');
    }
    return widget.product?.description;
  }

  double get _price {
    if (widget.purchase != null) {
      return widget.purchase!.expectedSalePrice > 0
          ? widget.purchase!.expectedSalePrice
          : widget.purchase!.purchasePrice;
    }
    return widget.product?.salePrice ?? 0.0;
  }

  bool get _isUsedOrUnit => widget.purchase != null || widget.initialImei != null;

  Future<void> _handlePrint() async {
    setState(() => _isPrinting = true);
    try {
      final config = await ref.read(receiptConfigurationProvider.future);
      final shopName = config.shopName.isNotEmpty ? config.shopName : 'MOBILE SHOP';

      bool success;
      if (widget.purchase != null) {
        success = await ProductStickerService.printCustomerPurchaseSticker(
          purchase: widget.purchase!,
          shopName: shopName,
          copies: _copies,
        );
      } else {
        final currentProd = widget.product!;
        final barcodeToPrint = _barcode;

        // Agar product ka barcode pehle se save nahi tha, to naya barcode product ke sath save karein
        if ((currentProd.barcode == null || currentProd.barcode!.trim().isEmpty) &&
            widget.initialImei == null) {
          final updatedProduct = currentProd.copyWith(barcode: barcodeToPrint);
          await ref.read(productControllerProvider.notifier).updateProduct(updatedProduct);
        }

        success = await ProductStickerService.printProductSticker(
          product: currentProd.copyWith(barcode: barcodeToPrint),
          shopName: shopName,
          imei: widget.initialImei,
          details: widget.initialDetails,
          copies: _copies,
        );
      }

      if (mounted && success) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Sticker print dialog open ho gaya'),
            backgroundColor: AppColors.success,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Sticker print error: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isPrinting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          const Icon(Icons.label_rounded, color: AppColors.primary),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Print Sticker (50 × 30 mm)',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Thermal label sticker for Speed X SP-690UB & gap label printers:',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),

            // ── Sticker Preview Card ──
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.border, width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withAlpha(15),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Header: Shop Name & Price
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'MY SHOP',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      if (_price > 0)
                        Text(
                          'Rs. ${_price.toStringAsFixed(0)}',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Colors.black,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),

                  // Title
                  Text(
                    _title,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),

                  // Subtitle / Specs
                  if (_details != null && _details!.isNotEmpty)
                    Text(
                      _details!,
                      style: const TextStyle(
                        fontSize: 9,
                        color: Colors.black54,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),

                  const SizedBox(height: 6),

                  // Simulated Barcode
                  Container(
                    height: 24,
                    color: Colors.grey.shade100,
                    child: Center(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(
                          26,
                          (i) => Container(
                            width: (i % 3 == 0) ? 2.5 : ((i % 2 == 0) ? 1.5 : 1),
                            height: 20,
                            margin: const EdgeInsets.symmetric(horizontal: 1),
                            color: Colors.black,
                          ),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 3),

                  // Code / IMEI text
                  Center(
                    child: Text(
                      _isUsedOrUnit ? 'IMEI: $_barcode' : _barcode,
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1,
                        color: Colors.black,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // ── Copies Selector (for normal products) ──
            if (!_isUsedOrUnit) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Copies to Print:',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline_rounded),
                        onPressed: _copies > 1 ? () => setState(() => _copies--) : null,
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceVariant,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '$_copies',
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.add_circle_outline_rounded),
                        onPressed: _copies < 100 ? () => setState(() => _copies++) : null,
                      ),
                    ],
                  ),
                ],
              ),
            ] else ...[
              const Center(
                child: Text(
                  'Physical phone unit - 1 sticker per unit',
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary, fontStyle: FontStyle.italic),
                ),
              ),
            ],
          ],
        ),
      ),
      actionsPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      actions: [
        TextButton(
          onPressed: _isPrinting ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: _isPrinting ? null : _handlePrint,
          icon: _isPrinting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.print_rounded),
          label: Text(_isPrinting ? 'Printing...' : 'Print Sticker'),
        ),
      ],
    );
  }
}
