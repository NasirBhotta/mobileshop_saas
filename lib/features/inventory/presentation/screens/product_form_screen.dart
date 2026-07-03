import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/utils/responsive.dart';
import '../../../../shared/widgets/loading_overlay.dart';
import '../../data/models/product_model.dart';
import '../providers/inventory_provider.dart';

class ProductFormScreen extends ConsumerStatefulWidget {
  final ProductModel? product; // null = add, not null = edit

  const ProductFormScreen({super.key, this.product});

  @override
  ConsumerState<ProductFormScreen> createState() => _ProductFormScreenState();
}

class _ProductFormScreenState extends ConsumerState<ProductFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _skuController;
  late final TextEditingController _descController;
  late final TextEditingController _salePriceController;
  late final TextEditingController _costPriceController;
  late final TextEditingController _quantityController;

  String? _selectedCategoryId;
  bool _imeiTracked = false;
  bool get _isEdit => widget.product != null;

  @override
  void initState() {
    super.initState();
    final p = widget.product;
    _nameController = TextEditingController(text: p?.name ?? '');
    _skuController = TextEditingController(text: p?.sku ?? '');
    _descController = TextEditingController(text: p?.description ?? '');
    _salePriceController = TextEditingController(
      text: p != null ? p.salePrice.toStringAsFixed(0) : '',
    );
    _costPriceController = TextEditingController(
      text: p != null ? p.costPrice.toStringAsFixed(0) : '',
    );
    _quantityController = TextEditingController(
      text: p != null ? p.stock.toString() : '',
    );
    _selectedCategoryId = p?.categoryId;
    _imeiTracked = p?.imeiTracked ?? false;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _skuController.dispose();
    _descController.dispose();
    _salePriceController.dispose();
    _costPriceController.dispose();
    _quantityController.dispose();
    super.dispose();
  }

  Future<void> _handleSubmit() async {
    if (!_formKey.currentState!.validate()) return;

    final product = ProductModel(
      id: widget.product?.id ?? '',
      tenantId: '',
      branchId: '',
      categoryId: _selectedCategoryId,
      name: _nameController.text.trim(),
      sku: _skuController.text.trim(),
      description: _descController.text.trim(),
      salePrice: double.tryParse(_salePriceController.text) ?? 0,
      costPrice: double.tryParse(_costPriceController.text) ?? 0,
      imeiTracked: _imeiTracked,
      stock: int.tryParse(_quantityController.text) ?? 0,
    );

    bool success;
    if (_isEdit) {
      success = await ref
          .read(productControllerProvider.notifier)
          .updateProduct(product);
    } else {
      success = await ref
          .read(productControllerProvider.notifier)
          .addProduct(product);
    }

    if (success && mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final categoriesState = ref.watch(categoriesProvider);
    final isLoading = ref.watch(productControllerProvider).isLoading;
    final isDesktop = Responsive.isDesktop(context);

    return LoadingOverlay(
      isLoading: isLoading,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: Text(
            _isEdit
                ? AppStrings.inventoryEditProduct
                : AppStrings.inventoryAddProduct,
          ),
          actions: [
            if (_isEdit)
              IconButton(
                onPressed: () async {
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder:
                        (dialogContext) => AlertDialog(
                          title: const Text('Product delete karein?'),
                          actions: [
                            TextButton(
                              onPressed:
                                  () => Navigator.pop(dialogContext, false),
                              child: const Text('Cancel'),
                            ),
                            TextButton(
                              onPressed:
                                  () => Navigator.pop(dialogContext, true),
                              child: const Text(
                                'Delete',
                                style: TextStyle(color: AppColors.error),
                              ),
                            ),
                          ],
                        ),
                  );
                  if (confirm == true && mounted) {
                    await ref
                        .read(productControllerProvider.notifier)
                        .deleteProduct(widget.product!.id);
                    if (context.mounted) context.pop();
                  }
                },
                icon: const Icon(Icons.delete_outline_rounded),
                color: AppColors.error,
              ),
          ],
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: isDesktop ? 600 : double.infinity,
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Product Name ──
                    _FormField(
                      label: AppStrings.fieldProductName,
                      child: TextFormField(
                        controller: _nameController,
                        decoration: InputDecoration(
                          hintText: AppStrings.hintProductName,
                        ),
                        validator:
                            (v) =>
                                v == null || v.trim().isEmpty
                                    ? AppStrings.errorProductNameRequired
                                    : null,
                      ),
                    ),

                    // ── SKU ──
                    _FormField(
                      label: AppStrings.fieldSku,
                      child: TextFormField(
                        controller: _skuController,
                        decoration: InputDecoration(
                          hintText: AppStrings.hintSku,
                        ),
                      ),
                    ),

                    // ── Prices Row ──
                    Row(
                      children: [
                        Expanded(
                          child: _FormField(
                            label: AppStrings.fieldSalePrice,
                            child: TextFormField(
                              controller: _salePriceController,
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                hintText: AppStrings.hintSalePrice,
                                prefixText: '₨ ',
                              ),
                              validator: (v) {
                                if (v == null || v.isEmpty) {
                                  return AppStrings.errorSalePriceInvalid;
                                }
                                if (double.tryParse(v) == null) {
                                  return AppStrings.errorSalePriceInvalid;
                                }
                                return null;
                              },
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _FormField(
                            label: AppStrings.fieldCostPrice,
                            child: TextFormField(
                              controller: _costPriceController,
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                hintText: AppStrings.hintCostPrice,
                                prefixText: '₨ ',
                              ),
                              validator: (v) {
                                if (v == null || v.isEmpty) {
                                  return AppStrings.errorCostPriceInvalid;
                                }
                                if (double.tryParse(v) == null) {
                                  return AppStrings.errorCostPriceInvalid;
                                }
                                return null;
                              },
                            ),
                          ),
                        ),
                      ],
                    ),

                    // ── Category ──
                    _FormField(
                      label: AppStrings.fieldQuantity,
                      child: TextFormField(
                        controller: _quantityController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          hintText: '0',
                          suffixText: 'pcs',
                        ),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return null;

                          final quantity = int.tryParse(v);
                          if (quantity == null || quantity < 0) {
                            return 'Valid quantity likhein';
                          }

                          return null;
                        },
                      ),
                    ),

                    _FormField(
                      label: AppStrings.fieldCategory,
                      child: categoriesState.when(
                        loading: () => const LinearProgressIndicator(),
                        error: (_, _) => const SizedBox.shrink(),
                        data:
                            (categories) => DropdownButtonFormField<String?>(
                              initialValue: _selectedCategoryId,
                              hint: const Text('Category select karein'),
                              decoration: const InputDecoration(),
                              items: [
                                const DropdownMenuItem(
                                  value: null,
                                  child: Text('Koi nahi'),
                                ),
                                ...categories.map(
                                  (cat) => DropdownMenuItem(
                                    value: cat.id,
                                    child: Text(cat.name),
                                  ),
                                ),
                              ],
                              onChanged: (val) {
                                setState(() => _selectedCategoryId = val);
                              },
                            ),
                      ),
                    ),

                    // ── Description ──
                    _FormField(
                      label: AppStrings.fieldDescription,
                      child: TextFormField(
                        controller: _descController,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          hintText: 'Product ki details likhein...',
                        ),
                      ),
                    ),

                    // ── IMEI Toggle ──
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceVariant,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Row(
                        children: [
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  AppStrings.fieldImeiTracked,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                                Text(
                                  'Har unit ka IMEI track hoga',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Switch(
                            value: _imeiTracked,
                            onChanged:
                                (val) => setState(() => _imeiTracked = val),
                            activeThumbColor: AppColors.primary,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),

                    // ── Submit ──
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: isLoading ? null : _handleSubmit,
                        child:
                            isLoading
                                ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                                : Text(
                                  _isEdit
                                      ? 'Update Karein'
                                      : 'Product Add Karein',
                                ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FormField extends StatelessWidget {
  final String label;
  final Widget child;

  const _FormField({required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          child,
        ],
      ),
    );
  }
}
