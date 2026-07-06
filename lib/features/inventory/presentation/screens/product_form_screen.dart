import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/utils/responsive.dart';
import '../../../../shared/widgets/loading_overlay.dart';
import '../../data/models/category_model.dart';
import '../../data/models/price_history_model.dart';
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
  late final TextEditingController _thresholdController;
  String? _selectedCategoryId;
  bool _imeiTracked = false;
  bool get _isEdit => widget.product != null;

  List<CategoryModel> _uniqueCategories(List<CategoryModel> categories) {
    final seen = <String>{};
    return [
      for (final category in categories)
        if (seen.add(category.id)) category,
    ];
  }

  String? _categoryDropdownValue(List<CategoryModel> categories) {
    final selectedId = _selectedCategoryId;
    if (selectedId == null) return null;
    if (categories.any((category) => category.id == selectedId)) {
      return selectedId;
    }
    if (_isEdit && widget.product?.categoryId == selectedId) {
      return selectedId;
    }
    return null;
  }

  List<DropdownMenuItem<String?>> _categoryDropdownItems(
    List<CategoryModel> categories,
  ) {
    final uniqueCategories = _uniqueCategories(categories);
    final selectedId = _selectedCategoryId;
    final hasSelectedCategory =
        selectedId == null ||
        uniqueCategories.any((category) => category.id == selectedId);

    return [
      const DropdownMenuItem(value: null, child: Text('Koi nahi')),
      ...uniqueCategories.map(
        (category) =>
            DropdownMenuItem(value: category.id, child: Text(category.name)),
      ),
      if (!hasSelectedCategory && _isEdit)
        DropdownMenuItem(
          value: selectedId,
          child: Text(widget.product?.categoryName ?? 'Current category'),
        ),
    ];
  }

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

    _thresholdController = TextEditingController(
      text: widget.product?.reorderThreshold.toString() ?? '5',
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _skuController.dispose();
    _descController.dispose();
    _salePriceController.dispose();
    _costPriceController.dispose();
    _quantityController.dispose();
    _thresholdController.dispose();
    super.dispose();
  }

  Future<void> _handleSubmit() async {
    if (!_formKey.currentState!.validate()) return;

    if (_isEdit && widget.product!.imeiTracked && !_imeiTracked) {
      final hasActiveImeiUnits = await ref.read(
        activeImeiUnitsProvider(widget.product!.id).future,
      );
      if (hasActiveImeiUnits) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'IMEI tracking cannot be disabled while active IMEI units exist.',
            ),
          ),
        );
        return;
      }
    }

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
      reorderThreshold: int.tryParse(_thresholdController.text) ?? 5,
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
    final hasActiveImeiUnits =
        _isEdit
            ? ref.watch(activeImeiUnitsProvider(widget.product!.id))
            : const AsyncData(false);
    final isImeiDisableLocked =
        _isEdit &&
        widget.product!.imeiTracked &&
        hasActiveImeiUnits.maybeWhen(
          data: (value) => value,
          orElse: () => false,
        );

    return LoadingOverlay(
      isLoading: isLoading,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          leading: IconButton(
            onPressed: () => Navigator.pop(context),
            icon: Icon(Icons.arrow_back),
          ),
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

                    _FormField(
                      label: 'Low Stock Alert (Quantity)',
                      child: TextFormField(
                        controller: _thresholdController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          hintText: '5',
                          helperText: 'Jab stock is level pe aaye → alert',
                        ),
                        validator: (v) {
                          final val = int.tryParse(v ?? '');
                          if (val == null || val < 1) {
                            return 'Kam az kam 1 hona chahiye';
                          }
                          return null;
                        },
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
                        data: (categories) {
                          final dropdownCategories = _uniqueCategories(
                            categories,
                          );
                          return DropdownButtonFormField<String?>(
                            initialValue: _categoryDropdownValue(
                              dropdownCategories,
                            ),
                            hint: const Text('Category select karein'),
                            decoration: const InputDecoration(),
                            items: _categoryDropdownItems(dropdownCategories),
                            onChanged: (val) {
                              setState(() => _selectedCategoryId = val);
                            },
                          );
                        },
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
                                isImeiDisableLocked
                                    ? null
                                    : (val) =>
                                        setState(() => _imeiTracked = val),
                            activeThumbColor: AppColors.primary,
                          ),
                        ],
                      ),
                    ),
                    if (isImeiDisableLocked) ...[
                      const SizedBox(height: 8),
                      const Text(
                        'Locked because active IMEI units exist for this product.',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.warning,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
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
                    if (_isEdit) ...[
                      const SizedBox(height: 24),
                      _PriceHistorySection(productId: widget.product!.id),
                    ],
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

class _PriceHistorySection extends ConsumerWidget {
  final String productId;

  const _PriceHistorySection({required this.productId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyState = ref.watch(productPriceHistoryProvider(productId));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Price History',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            IconButton(
              onPressed:
                  () => ref.invalidate(productPriceHistoryProvider(productId)),
              icon: const Icon(Icons.refresh_rounded),
              tooltip: 'Refresh',
            ),
          ],
        ),
        const SizedBox(height: 8),
        historyState.when(
          loading: () => const LinearProgressIndicator(),
          error:
              (error, _) => Text(
                error.toString(),
                style: const TextStyle(color: AppColors.error, fontSize: 12),
              ),
          data: (history) {
            if (history.isEmpty) {
              return Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.surfaceVariant,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.border),
                ),
                child: const Text(
                  'No price changes yet.',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              );
            }

            return Column(
              children:
                  history
                      .map((item) => _PriceHistoryTile(history: item))
                      .toList(),
            );
          },
        ),
      ],
    );
  }
}

class _PriceHistoryTile extends StatelessWidget {
  final PriceHistoryModel history;

  const _PriceHistoryTile({required this.history});

  @override
  Widget build(BuildContext context) {
    final formatter = DateFormat('MMM d, yyyy h:mm a');
    final userLabel =
        history.changedBy == null
            ? 'System'
            : 'User ${history.changedBy!.substring(0, history.changedBy!.length < 8 ? history.changedBy!.length : 8)}';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.info.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.history_rounded,
              color: AppColors.info,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Rs ${history.oldPrice.toStringAsFixed(0)} -> Rs ${history.newPrice.toStringAsFixed(0)}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$userLabel - ${formatter.format(history.changedAt)}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Text(
            history.changeSource == 'bulk_update' ? 'Bulk' : 'Edit',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
        ],
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
