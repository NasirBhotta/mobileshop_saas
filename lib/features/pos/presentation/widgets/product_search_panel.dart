import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../shared/widgets/barcode_camera_scanner.dart';
import '../../../inventory/data/models/product_model.dart';
import '../../../inventory/presentation/providers/inventory_provider.dart';
import '../../data/models/cart_item_model.dart';
import '../providers/pos_provider.dart';

class ProductSearchPanel extends ConsumerStatefulWidget {
  const ProductSearchPanel({super.key});

  @override
  ConsumerState<ProductSearchPanel> createState() => _ProductSearchPanelState();
}

class _ProductSearchPanelState extends ConsumerState<ProductSearchPanel> {
  final _searchCtrl = TextEditingController();
  final _searchFocus = FocusNode();
  Timer? _debounce;
  String _query = '';
  String _debouncedQuery = '';
  bool _resolvingBarcode = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  bool get _cameraScannerSupported =>
      kIsWeb ||
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  Future<void> _openCameraScanner() async {
    final value = await BarcodeCameraScanner.open(context);
    if (value != null && mounted) await _resolveBarcode(value);
  }

  Future<void> _resolveBarcode(String rawValue) async {
    final code = rawValue.trim();
    if (code.isEmpty || _resolvingBarcode) return;
    setState(() => _resolvingBarcode = true);

    try {
      final products = await ref
          .read(inventoryRepositoryProvider)
          .searchProducts(query: code, limit: 20);
      final normalized = code.toLowerCase();
      final matches = products.where(
        (product) =>
            product.barcode?.trim().toLowerCase() == normalized ||
            product.sku?.trim().toLowerCase() == normalized,
      );
      final product = matches.firstOrNull;
      if (!mounted) return;

      if (product == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Barcode "$code" ka product nahi mila')),
        );
      } else {
        final cartItem =
            ref
                .read(cartProvider)
                .items
                .where((item) => item.productId == product.id)
                .firstOrNull;
        if (product.isOutOfStock ||
            (cartItem != null && cartItem.quantity >= product.stock)) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${product.name} ka stock available nahi')),
          );
        } else {
          ref
              .read(cartProvider.notifier)
              .addItem(CartItemModel.fromProduct(product));
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${product.name} cart mein add ho gaya'),
              duration: const Duration(milliseconds: 900),
            ),
          );
        }
      }
    } finally {
      if (mounted) {
        _searchCtrl.clear();
        setState(() {
          _query = '';
          _debouncedQuery = '';
          _resolvingBarcode = false;
        });
        _searchFocus.requestFocus();
      }
    }
  }

  void _setQuery(String value) {
    setState(() => _query = value);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      setState(() => _debouncedQuery = value.trim());
    });
  }

  Future<void> _refreshProducts() async {
    final repository = ref.read(inventoryRepositoryProvider);

    try {
      await repository.syncOfflineMutations();
    } catch (_) {
      // Pending mutations stay queued; continue with the remote cache refresh.
    }

    await repository.refreshCurrentProductsCache(
      timeout: const Duration(seconds: 10),
    );

    if (!mounted) return;
    final request = ProductSearchRequest(query: _debouncedQuery, limit: 50);
    ref
      ..invalidate(allProductsProvider)
      ..invalidate(productsProvider)
      ..invalidate(inventoryProductsProvider)
      ..invalidate(productSearchProvider);

    await ref.read(productSearchProvider(request).future);
  }

  @override
  Widget build(BuildContext context) {
    final productsAsync = ref.watch(
      productSearchProvider(
        ProductSearchRequest(query: _debouncedQuery, limit: 50),
      ),
    );

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            controller: _searchCtrl,
            focusNode: _searchFocus,
            autofocus: true,
            onChanged: _setQuery,
            onSubmitted: _resolveBarcode,
            decoration: InputDecoration(
              hintText: AppStrings.searchProductsPos,
              prefixIcon: const Icon(
                Icons.search_rounded,
                color: AppColors.textHint,
                size: 20,
              ),
              suffixIcon:
                  _resolvingBarcode
                      ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                      : _query.isNotEmpty
                      ? IconButton(
                        icon: const Icon(Icons.close_rounded, size: 18),
                        onPressed: () {
                          _searchCtrl.clear();
                          _debounce?.cancel();
                          setState(() {
                            _query = '';
                            _debouncedQuery = '';
                          });
                        },
                      )
                      : _cameraScannerSupported
                      ? IconButton(
                        icon: const Icon(Icons.qr_code_scanner_rounded),
                        tooltip: 'Camera se barcode scan karein',
                        onPressed: _openCameraScanner,
                      )
                      : const Icon(
                        Icons.qr_code_2_rounded,
                        color: AppColors.textHint,
                      ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 10,
              ),
              filled: true,
              fillColor: AppColors.surfaceVariant,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(
                  color: AppColors.primary,
                  width: 2,
                ),
              ),
            ),
          ),
        ),
        Expanded(
          child: productsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text(e.toString())),
            data: (products) {
              if (_debouncedQuery.isNotEmpty && _debouncedQuery.length < 2) {
                return const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.search_rounded,
                        size: 48,
                        color: AppColors.textHint,
                      ),
                      SizedBox(height: 12),
                      Text(
                        'Kam az kam 2 characters type karein',
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                );
              }

              if (products.isEmpty) {
                return RefreshIndicator(
                  onRefresh: _refreshProducts,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: const [
                      SizedBox(height: 120),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.search_off_rounded,
                            size: 48,
                            color: AppColors.textHint,
                          ),
                          SizedBox(height: 12),
                          Text(
                            AppStrings.noProductsFound,
                            style: TextStyle(color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              }

              return RefreshIndicator(
                onRefresh: _refreshProducts,
                child: ListView.separated(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  itemCount: products.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 6),
                  itemBuilder: (context, index) {
                    final product = products[index];
                    return _ProductTile(product: product);
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ProductTile extends ConsumerWidget {
  final ProductModel product;

  const _ProductTile({required this.product});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cartItems = ref.watch(cartProvider).items;
    final cartItem =
        cartItems.where((item) => item.productId == product.id).firstOrNull;
    final inCart = cartItem != null;

    final isOutOfStock = product.isOutOfStock;
    final isAtStockLimit =
        cartItem != null && cartItem.quantity >= product.stock;

    return InkWell(
      onTap:
          isOutOfStock || isAtStockLimit
              ? null
              : () {
                ref
                    .read(cartProvider.notifier)
                    .addItem(CartItemModel.fromProduct(product));
              },
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color:
              inCart
                  ? AppColors.primary.withValues(alpha: 0.06)
                  : AppColors.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: inCart ? AppColors.primary : AppColors.border,
            width: inCart ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color:
                    isOutOfStock
                        ? AppColors.surfaceVariant
                        : AppColors.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.phone_android_rounded,
                size: 20,
                color: isOutOfStock ? AppColors.textHint : AppColors.primary,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.name,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color:
                          isOutOfStock
                              ? AppColors.textHint
                              : AppColors.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color:
                              isOutOfStock
                                  ? AppColors.error.withValues(alpha: 0.1)
                                  : AppColors.success.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          isOutOfStock
                              ? 'Out of Stock'
                              : '${product.stock} left',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color:
                                isOutOfStock
                                    ? AppColors.error
                                    : AppColors.success,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  'Rs ${product.salePrice.toStringAsFixed(0)}',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                if (inCart)
                  Container(
                    margin: const EdgeInsets.only(top: 4),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${cartItem.quantity}/${product.stock} in cart',
                      style: const TextStyle(
                        fontSize: 10,
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
