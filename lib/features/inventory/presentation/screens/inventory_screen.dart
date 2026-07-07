import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobileshop_saas/features/inventory/data/models/product_model.dart';
import 'package:mobileshop_saas/features/inventory/presentation/widgets/category_filter_bar.dart';
import 'package:mobileshop_saas/features/inventory/presentation/widgets/product_card.dart';
import 'package:mobileshop_saas/features/inventory/presentation/widgets/sort_bottom_sheet.dart';
import 'package:mobileshop_saas/shared/widgets/search_bar_field.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/utils/responsive.dart';
import '../../../../shared/providers/navigation_loading_provider.dart';
import '../providers/inventory_provider.dart';

class InventoryScreen extends ConsumerWidget {
  const InventoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _InventoryBody();
  }
}

class _InventoryBody extends ConsumerStatefulWidget {
  @override
  ConsumerState<_InventoryBody> createState() => _InventoryBodyState();
}

class _InventoryBodyState extends ConsumerState<_InventoryBody> {
  final Set<String> _selectedProductIds = {};

  bool get _isSelectionMode => _selectedProductIds.isNotEmpty;

  void _toggleSelection(String productId, bool selected) {
    setState(() {
      if (selected) {
        _selectedProductIds.add(productId);
      } else {
        _selectedProductIds.remove(productId);
      }
    });
  }

  void _clearSelection() {
    setState(_selectedProductIds.clear);
  }

  @override
  Widget build(BuildContext context) {
    final productsState = ref.watch(filteredProductsProvider);

    final categoriesState = ref.watch(categoriesProvider);
    final selectedCategory = ref.watch(selectedCategoryProvider);
    final isUpdating = ref.watch(productControllerProvider).isLoading;
    final isDesktop = Responsive.isDesktop(context);
    final isTablet = Responsive.isTablet(context);
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // ── Header ──
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _isSelectionMode
                          ? '${_selectedProductIds.length} selected'
                          : AppStrings.inventoryTitle,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  if (_isSelectionMode) ...[
                    IconButton(
                      onPressed: isUpdating ? null : _clearSelection,
                      icon: const Icon(Icons.close_rounded),
                      tooltip: 'Clear selection',
                    ),
                    FilledButton.icon(
                      onPressed:
                          isUpdating
                              ? null
                              : () => _showBulkPriceUpdate(context),
                      icon: const Icon(Icons.percent_rounded, size: 18),
                      label: const Text('Price'),
                    ),
                  ] else ...[
                    // Categories button
                    IconButton(
                      onPressed: () {
                        ref.read(navigationLoadingProvider.notifier).showFor();
                        context.push('/inventory/categories');
                      },
                      icon: const Icon(Icons.label_outline_rounded),
                      color: AppColors.textSecondary,
                      tooltip: AppStrings.categoriesTitle,
                    ),

                    IconButton(
                      onPressed:
                          () =>
                              isDesktop
                                  ? showDropDown(context, ref)
                                  : showSortSheet(context, ref),
                      icon: const Icon(Icons.sort_rounded),
                      color: AppColors.textSecondary,
                      tooltip: AppStrings.sortBy,
                    ),
                    // Add product button
                    FilledButton.icon(
                      onPressed: () {
                        ref.read(navigationLoadingProvider.notifier).showFor();
                        context.push('/inventory/add');
                      },
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text('Add'),
                    ),
                  ],

                  IconButton(
                    onPressed: () => context.push('/inventory/import'),
                    icon: const Icon(Icons.upload_file_rounded),
                    color: AppColors.textSecondary,
                    tooltip: 'CSV Import',
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: SizedBox(
                height: 45,
                child: SearchBarField(
                  hint: AppStrings.searchProducts,
                  onChanged: (query) {
                    ref.read(searchQueryProvider.notifier).state = query;
                  },
                ),
              ),
            ),
            SizedBox(height: 10),
            // ── Category Filter ──
            categoriesState.when(
              loading: () => const SizedBox.shrink(),
              error: (_, _) => const SizedBox.shrink(),
              data:
                  (categories) => CategoryFilterBar(
                    categories: categories,
                    selectedId: selectedCategory,
                    onSelected: (id) {
                      ref.read(selectedCategoryProvider.notifier).state = id;
                    },
                  ),
            ),

            // ── Products List ──
            Expanded(
              child: productsState.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) => Center(child: Text(error.toString())),
                data: (products) {
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    child: Text(
                      '${products.length} ${AppStrings.filterResults}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  );
                  if (products.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.inventory_2_outlined,
                            size: 64,
                            color: AppColors.textHint,
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            AppStrings.inventoryEmpty,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            AppStrings.inventoryEmptyDesc,
                            style: TextStyle(color: AppColors.textHint),
                          ),
                          const SizedBox(height: 24),
                          FilledButton.icon(
                            onPressed: () {
                              ref
                                  .read(navigationLoadingProvider.notifier)
                                  .showFor();
                              context.push('/inventory/add');
                            },
                            icon: const Icon(Icons.add_rounded),
                            label: Text(AppStrings.inventoryAddProduct),
                          ),
                        ],
                      ),
                    );
                  }

                  return RefreshIndicator(
                    onRefresh: () async => ref.invalidate(productsProvider),
                    child:
                        isDesktop
                            ? GridView.builder(
                              padding: const EdgeInsets.all(16),
                              gridDelegate:
                                  SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: 4,
                                    mainAxisSpacing: 8,
                                    crossAxisSpacing: 8,
                                    childAspectRatio: 3.5,
                                  ),
                              itemCount: products.length,
                              itemBuilder: (context, index) {
                                final product = products[index];
                                return ProductCard(
                                  product: product,
                                  isSelectionMode: _isSelectionMode,
                                  isSelected: _selectedProductIds.contains(
                                    product.id,
                                  ),
                                  onSelectionChanged:
                                      (selected) => _toggleSelection(
                                        product.id,
                                        selected,
                                      ),
                                  onTap: () {
                                    ref
                                        .read(
                                          navigationLoadingProvider.notifier,
                                        )
                                        .showFor();
                                    context.push(
                                      '/inventory/edit',
                                      extra: product,
                                    );
                                  },
                                );
                              },
                            )
                            : isTablet
                            ? GridView.builder(
                              padding: const EdgeInsets.all(16),
                              gridDelegate:
                                  SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: 2,
                                    mainAxisSpacing: 8,
                                    crossAxisSpacing: 8,
                                    childAspectRatio: 3.5,
                                  ),
                              itemCount: products.length,
                              itemBuilder: (context, index) {
                                final product = products[index];
                                return ProductCard(
                                  product: product,
                                  isSelectionMode: _isSelectionMode,
                                  isSelected: _selectedProductIds.contains(
                                    product.id,
                                  ),
                                  onSelectionChanged:
                                      (selected) => _toggleSelection(
                                        product.id,
                                        selected,
                                      ),
                                  onTap: () {
                                    ref
                                        .read(
                                          navigationLoadingProvider.notifier,
                                        )
                                        .showFor();
                                    context.push(
                                      '/inventory/edit',
                                      extra: product,
                                    );
                                  },
                                );
                              },
                            )
                            : ListView.separated(
                              padding: const EdgeInsets.all(16),
                              itemCount: products.length,
                              separatorBuilder:
                                  (_, _) => const SizedBox(height: 8),
                              itemBuilder: (context, index) {
                                final product = products[index];
                                return ProductCard(
                                  product: product,
                                  isSelectionMode: _isSelectionMode,
                                  isSelected: _selectedProductIds.contains(
                                    product.id,
                                  ),
                                  onSelectionChanged:
                                      (selected) => _toggleSelection(
                                        product.id,
                                        selected,
                                      ),
                                  onTap: () {
                                    ref
                                        .read(
                                          navigationLoadingProvider.notifier,
                                        )
                                        .showFor();
                                    context.push(
                                      '/inventory/edit',
                                      extra: product,
                                    );
                                  },
                                );
                              },
                            ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showBulkPriceUpdate(BuildContext context) async {
    final List<ProductModel> products = ref
        .read(productsProvider)
        .maybeWhen(
          data: (products) => products,
          orElse: () => <ProductModel>[],
        );
    final selectedProducts =
        products
            .where((product) => _selectedProductIds.contains(product.id))
            .toList();
    if (selectedProducts.isEmpty) return;

    final percentageController = TextEditingController();
    var direction = 'markup';
    final isDesktop = Responsive.isDesktop(context);

    Widget buildBulkPriceContent(
      BuildContext overlayContext,
      StateSetter setOverlayState,
    ) {
      final percentage = double.tryParse(percentageController.text.trim()) ?? 0;
      final multiplier =
          direction == 'markup'
              ? 1 + (percentage / 100)
              : 1 - (percentage / 100);
      final canSubmit =
          percentage > 0 &&
          (direction == 'markup' ||
              (direction == 'markdown' && percentage < 100));
      final sampleProducts = selectedProducts.take(3).toList();

      return SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            isDesktop ? 0 : 20,
            isDesktop ? 0 : 20,
            isDesktop ? 0 : 20,
            (isDesktop ? 0 : MediaQuery.of(overlayContext).viewInsets.bottom) +
                (isDesktop ? 0 : 20),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Bulk price update',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${selectedProducts.length} products selected',
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
                const SizedBox(height: 16),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(
                      value: 'markup',
                      icon: Icon(Icons.trending_up_rounded),
                      label: Text('Markup'),
                    ),
                    ButtonSegment(
                      value: 'markdown',
                      icon: Icon(Icons.trending_down_rounded),
                      label: Text('Markdown'),
                    ),
                  ],
                  selected: {direction},
                  onSelectionChanged:
                      (value) => setOverlayState(() {
                        direction = value.first;
                      }),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: percentageController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Percentage',
                    suffixText: '%',
                  ),
                  onChanged: (_) => setOverlayState(() {}),
                ),
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceVariant,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Preview',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ...sampleProducts.map((product) {
                        final newPrice =
                            canSubmit ? product.salePrice * multiplier : 0;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  product.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Text(
                                canSubmit
                                    ? 'Rs ${product.salePrice.toStringAsFixed(0)} -> Rs ${newPrice.toStringAsFixed(0)}'
                                    : 'Enter percentage',
                                style: const TextStyle(
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                      if (selectedProducts.length > sampleProducts.length)
                        Text(
                          '+${selectedProducts.length - sampleProducts.length} more',
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(overlayContext),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed:
                            canSubmit
                                ? () async {
                                  final result = await ref
                                      .read(productControllerProvider.notifier)
                                      .bulkUpdatePrices(
                                        BulkPriceUpdateRequest(
                                          products: selectedProducts,
                                          percentage: percentage,
                                          direction: direction,
                                        ),
                                      );

                                  if (!overlayContext.mounted) return;
                                  if (!result.isSuccess) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          result.errorMessage ??
                                              'Bulk update failed. Please try again.',
                                        ),
                                      ),
                                    );
                                    return;
                                  }

                                  Navigator.pop(overlayContext);
                                  _clearSelection();
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        'Updated ${result.updatedCount} product prices.',
                                      ),
                                    ),
                                  );
                                }
                                : null,
                        child: const Text('Apply'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (isDesktop) {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) {
          return Dialog(
            insetPadding: const EdgeInsets.all(24),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: StatefulBuilder(
                builder:
                    (dialogContext, setDialogState) =>
                        buildBulkPriceContent(dialogContext, setDialogState),
              ),
            ),
          );
        },
      );

      percentageController.dispose();
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            return buildBulkPriceContent(sheetContext, setSheetState);
          },
        );
      },
    );

    percentageController.dispose();
  }
}
