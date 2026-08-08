import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobileshop_saas/features/inventory/data/models/product_model.dart';
import 'package:mobileshop_saas/features/inventory/presentation/widgets/category_filter_bar.dart';
import 'package:mobileshop_saas/features/inventory/presentation/widgets/product_card.dart';
import 'package:mobileshop_saas/features/inventory/presentation/widgets/sort_bottom_sheet.dart';

import '../../../../core/authorization/branch_permission_shadow_provider.dart';
import '../../../../core/authorization/permission_locked_screen.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/utils/responsive.dart';
import '../../../../core/entitlements/entitlement_provider.dart';
import '../../../../shared/providers/navigation_loading_provider.dart';
import '../../../settings/presentation/widgets/account_menu_button.dart';
import '../../data/models/inventory_supplier_option.dart';
import '../providers/inventory_provider.dart';

class InventoryScreen extends ConsumerStatefulWidget {
  final bool initialLowStockOnly;
  final String? initialSupplierId;

  const InventoryScreen({
    super.key,
    this.initialLowStockOnly = false,
    this.initialSupplierId,
  });

  @override
  ConsumerState<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends ConsumerState<InventoryScreen> {
  bool _initialInventoryResolved = false;

  @override
  Widget build(BuildContext context) {
    final access = ref.watch(
      branchAwarePermissionProvider('inventory.product.view'),
    );

    if (access.isLoading && !access.hasValue) {
      return const _InventoryInitialLoader();
    }
    if (access.hasError || access.value != true) {
      return const PermissionLockedScreen(
        moduleName: 'Inventory',
        accountAction: AccountMenuButton(),
      );
    }

    if (!_initialInventoryResolved) {
      final categoriesState = ref.watch(categoriesProvider);
      final productsState = ref.watch(
        inventoryProductsProvider(
          InventoryProductsRequest(
            query: ref.read(searchQueryProvider).trim(),
            categoryId: ref.read(selectedCategoryProvider),
            sortOption: ref.read(sortOptionProvider),
            limit: 50,
            lowStockOnly: widget.initialLowStockOnly,
            supplierId: widget.initialSupplierId,
          ),
        ),
      );
      final isResolving = <AsyncValue<Object?>>[
        categoriesState,
        productsState,
      ].any((state) => state.isLoading && !state.hasValue);
      if (isResolving) return const _InventoryInitialLoader();
      _initialInventoryResolved = true;
    }

    return _InventoryBody(
      initialLowStockOnly: widget.initialLowStockOnly,
      initialSupplierId: widget.initialSupplierId,
    );
  }
}

class _InventoryInitialLoader extends StatelessWidget {
  const _InventoryInitialLoader();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(child: Center(child: CircularProgressIndicator())),
    );
  }
}

class _InventoryProductsStateBuilder extends ConsumerWidget {
  final InventoryProductsRequest request;
  final Widget Function(AsyncValue<List<ProductModel>>) builder;

  const _InventoryProductsStateBuilder({
    required this.request,
    required this.builder,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return builder(ref.watch(inventoryProductsProvider(request)));
  }
}

class _LoadMoreTile extends StatelessWidget {
  final VoidCallback onPressed;
  final bool compact;

  const _LoadMoreTile({required this.onPressed, this.compact = false});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.expand_more_rounded, size: 18),
        label: Text(compact ? 'More' : 'Load more products'),
      ),
    );
  }
}

class _InventoryFilterError extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _InventoryFilterError({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.cloud_off_rounded,
            size: 48,
            color: AppColors.textHint,
          ),
          const SizedBox(height: 12),
          const Text(
            'Supplier inventory load nahi hui',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w700,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Retry'),
          ),
        ],
      ),
    ),
  );
}

class _SupplierFilter extends StatelessWidget {
  final AsyncValue<List<InventorySupplierOption>> suppliersState;
  final String? selectedSupplierId;
  final ValueChanged<String?> onSelected;
  final VoidCallback onRetry;

  const _SupplierFilter({
    required this.suppliersState,
    required this.selectedSupplierId,
    required this.onSelected,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return suppliersState.when(
      loading:
          () => const SizedBox(
            height: 38,
            child: Align(
              alignment: Alignment.centerLeft,
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
      error:
          (_, _) => SizedBox(
            height: 38,
            child: OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.cloud_off_rounded, size: 16),
              label: const Text('Retry suppliers'),
            ),
          ),
      data: (suppliers) {
        if (suppliers.isEmpty) return const SizedBox.shrink();
        final selectedExists = suppliers.any(
          (supplier) => supplier.id == selectedSupplierId,
        );
        final effectiveValue = selectedExists ? selectedSupplierId : null;

        return Container(
          constraints: const BoxConstraints(maxWidth: 280),
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color:
                effectiveValue == null
                    ? AppColors.surface
                    : AppColors.primary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color:
                  effectiveValue == null
                      ? AppColors.border
                      : AppColors.primary.withValues(alpha: 0.35),
            ),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String?>(
              value: effectiveValue,
              isExpanded: true,
              icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 20),
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Row(
                    children: [
                      Icon(Icons.local_shipping_outlined, size: 17),
                      SizedBox(width: 7),
                      Text('All suppliers'),
                    ],
                  ),
                ),
                for (final supplier in suppliers)
                  DropdownMenuItem<String?>(
                    value: supplier.id,
                    child: Text(
                      supplier.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: onSelected,
            ),
          ),
        );
      },
    );
  }
}

class _InventoryBody extends ConsumerStatefulWidget {
  final bool initialLowStockOnly;
  final String? initialSupplierId;

  const _InventoryBody({
    required this.initialLowStockOnly,
    required this.initialSupplierId,
  });

  @override
  ConsumerState<_InventoryBody> createState() => _InventoryBodyState();
}

class _InventoryBodyState extends ConsumerState<_InventoryBody> {
  static const _pageSize = 50;
  static const _searchDelay = Duration(milliseconds: 250);

  final Set<String> _selectedProductIds = {};
  late final TextEditingController _searchController;
  late final FocusNode _searchFocusNode;
  late final ValueNotifier<String> _committedSearchQuery;
  Timer? _searchDebounce;
  List<ProductModel>? _lastVisibleProducts;
  bool _initialProductsResolved = false;
  int _visibleLimit = _pageSize;
  late bool _lowStockOnly;
  String? _selectedSupplierId;

  bool get _isSelectionMode => _selectedProductIds.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(
      text: ref.read(searchQueryProvider),
    );
    _searchFocusNode = FocusNode(debugLabel: 'inventory-search');
    _committedSearchQuery = ValueNotifier(_searchController.text.trim());
    _lowStockOnly = widget.initialLowStockOnly;
    _selectedSupplierId = widget.initialSupplierId;
  }

  @override
  void didUpdateWidget(covariant _InventoryBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialLowStockOnly != widget.initialLowStockOnly ||
        oldWidget.initialSupplierId != widget.initialSupplierId) {
      _lowStockOnly = widget.initialLowStockOnly;
      _selectedSupplierId = widget.initialSupplierId;
      _visibleLimit = _pageSize;
      _lastVisibleProducts = null;
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _committedSearchQuery.dispose();
    _searchFocusNode.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(_searchDelay, () {
      if (!mounted) return;
      if (_visibleLimit != _pageSize) _resetPaging();
      final query = value.trim();
      _committedSearchQuery.value = query;
      ref.read(searchQueryProvider.notifier).state = query;
    });
  }

  void _clearSearch() {
    _searchDebounce?.cancel();
    _searchController.clear();
    _resetPaging();
    _committedSearchQuery.value = '';
    ref.read(searchQueryProvider.notifier).state = '';
  }

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

  void _resetPaging() {
    setState(() {
      _visibleLimit = _pageSize;
    });
  }

  void _loadMore() {
    setState(() {
      _visibleLimit += _pageSize;
    });
  }

  InventoryProductsRequest _currentRequest({int? limit}) {
    return InventoryProductsRequest(
      query: ref.read(searchQueryProvider),
      categoryId: ref.read(selectedCategoryProvider),
      supplierId: _selectedSupplierId,
      sortOption: ref.read(sortOptionProvider),
      limit: limit ?? _visibleLimit,
      lowStockOnly: _lowStockOnly,
    );
  }

  Future<void> _refreshInventory() async {
    final repository = ref.read(inventoryRepositoryProvider);

    try {
      await repository.syncOfflineMutations();
    } catch (_) {
      // Continue with remote reads; queued mutations remain available locally.
    }

    await Future.wait([
      repository.refreshCurrentProductsCache(
        timeout: const Duration(seconds: 10),
      ),
      repository.refreshCurrentCategoriesCache(
        timeout: const Duration(seconds: 10),
      ),
    ]);

    if (!mounted) return;
    _resetPaging();
    final request = _currentRequest(limit: _pageSize);

    ref
      ..invalidate(allProductsProvider)
      ..invalidate(categoriesProvider)
      ..invalidate(inventorySuppliersProvider)
      ..invalidate(inventoryProductsPageProvider)
      ..invalidate(inventoryProductsProvider);

    await Future.wait([
      ref.read(categoriesProvider.future),
      ref.read(inventoryProductsProvider(request).future),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final categoriesState = ref.watch(categoriesProvider);
    final suppliersState = ref.watch(inventorySuppliersProvider);
    final selectedCategory = ref.watch(selectedCategoryProvider);
    final sortOption = ref.watch(sortOptionProvider);
    final isUpdating = ref.watch(productControllerProvider).isLoading;
    final isDesktop = Responsive.isDesktop(context);
    final isCompactDesktop = Responsive.isCompactDesktop(context);
    final isLargeDesktop = Responsive.isLargeDesktop(context);
    final isTablet = Responsive.isTablet(context);
    final csvImportEntitlement = ref.watch(
      featureEntitlementProvider('inventory.csv_import'),
    );
    final bulkPricingEntitlement = ref.watch(
      featureEntitlementProvider('inventory.bulk_pricing'),
    );
    final createPermission = ref.watch(
      branchAwarePermissionProvider('inventory.product.create'),
    );
    final updatePermission = ref.watch(
      branchAwarePermissionProvider('inventory.product.update'),
    );
    final categoryPermission = ref.watch(
      branchAwarePermissionProvider('inventory.category.view'),
    );
    final adjustStockPermission = ref.watch(
      branchAwarePermissionProvider('inventory.stock.adjust'),
    );

    AsyncValue<List<ProductModel>>? initialProductsState;
    if (!_initialProductsResolved) {
      final state = ref.watch(
        inventoryProductsProvider(
          InventoryProductsRequest(
            query: _committedSearchQuery.value,
            categoryId: selectedCategory,
            sortOption: sortOption,
            limit: _pageSize,
            lowStockOnly: _lowStockOnly,
            supplierId: _selectedSupplierId,
          ),
        ),
      );
      initialProductsState = state;
      if (state.hasValue || state.hasError) {
        _initialProductsResolved = true;
        if (state.hasValue) {
          _lastVisibleProducts = state.value;
        }
      }
    }

    final initialDependencies = <AsyncValue<Object?>>[
      categoriesState,
      if (initialProductsState != null) initialProductsState,
    ];
    final isInitialLoad = initialDependencies.any(
      (dependency) => dependency.isLoading && !dependency.hasValue,
    );

    if (isInitialLoad) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(child: Center(child: CircularProgressIndicator())),
      );
    }

    final csvImportEnabled = isEntitledActionVisible(
      csvImportEntitlement.value,
    );
    final bulkPricingEnabled = isEntitledActionVisible(
      bulkPricingEntitlement.value,
    );
    final canCreate = createPermission.value == true;
    final canUpdate = updatePermission.value == true;
    final canViewCategories = categoryPermission.value == true;
    final canAdjustStock = adjustStockPermission.value == true;
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
                    if (bulkPricingEnabled && canUpdate)
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
                    if (canViewCategories)
                      IconButton(
                        onPressed: () {
                          ref
                              .read(navigationLoadingProvider.notifier)
                              .showFor();
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
                    if (canCreate)
                      FilledButton.icon(
                        onPressed: () {
                          ref
                              .read(navigationLoadingProvider.notifier)
                              .showFor();
                          context.push('/inventory/add');
                        },
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: const Text('Add'),
                      ),
                  ],

                  if (csvImportEnabled && canCreate)
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
                child: TextField(
                  controller: _searchController,
                  focusNode: _searchFocusNode,
                  onChanged: _onSearchChanged,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: AppStrings.searchProducts,
                    prefixIcon: const Icon(
                      Icons.search_rounded,
                      color: AppColors.textHint,
                      size: 20,
                    ),
                    suffixIcon: ValueListenableBuilder<TextEditingValue>(
                      valueListenable: _searchController,
                      builder:
                          (context, value, _) =>
                              value.text.isEmpty
                                  ? const SizedBox.shrink()
                                  : IconButton(
                                    onPressed: _clearSearch,
                                    icon: const Icon(
                                      Icons.close_rounded,
                                      size: 18,
                                      color: AppColors.textHint,
                                    ),
                                  ),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 5,
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
            ),
            SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(left: 16),
                    child: _SupplierFilter(
                      suppliersState: suppliersState,
                      selectedSupplierId: _selectedSupplierId,
                      onSelected: (supplierId) {
                        setState(() {
                          _selectedSupplierId = supplierId;
                          _visibleLimit = _pageSize;
                          _lastVisibleProducts = null;
                          _selectedProductIds.clear();
                        });
                      },
                      onRetry: () => ref.invalidate(inventorySuppliersProvider),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 0, 16, 0),
                  child: FilterChip(
                    avatar: Icon(
                      Icons.warning_amber_rounded,
                      size: 18,
                      color:
                          _lowStockOnly ? AppColors.error : AppColors.textHint,
                    ),
                    label: const Text('Low stock only'),
                    selected: _lowStockOnly,
                    onSelected: (selected) {
                      setState(() {
                        _lowStockOnly = selected;
                        _visibleLimit = _pageSize;
                        _lastVisibleProducts = null;
                      });
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),

            // ── Category Filter ──
            categoriesState.when(
              loading: () => const SizedBox.shrink(),
              error: (_, _) => const SizedBox.shrink(),
              data:
                  (categories) => CategoryFilterBar(
                    categories: categories,
                    selectedId: selectedCategory,
                    onSelected: (id) {
                      _resetPaging();
                      ref.read(selectedCategoryProvider.notifier).state = id;
                    },
                  ),
            ),

            // ── Products List ──
            Expanded(
              child: ValueListenableBuilder<String>(
                valueListenable: _committedSearchQuery,
                builder:
                    (context, query, _) => _InventoryProductsStateBuilder(
                      request: InventoryProductsRequest(
                        query: query,
                        categoryId: selectedCategory,
                        supplierId: _selectedSupplierId,
                        sortOption: sortOption,
                        limit: _visibleLimit,
                        lowStockOnly: _lowStockOnly,
                      ),
                      builder: (productsState) {
                        final visibleProductsState =
                            productsState.isLoading &&
                                    _lastVisibleProducts != null
                                ? AsyncValue<List<ProductModel>>.data(
                                  _lastVisibleProducts!,
                                )
                                : productsState;
                        return visibleProductsState.when(
                          loading:
                              () => const Center(
                                child: CircularProgressIndicator(),
                              ),
                          error:
                              (error, _) => _InventoryFilterError(
                                message: error.toString().replaceFirst(
                                  'Bad state: ',
                                  '',
                                ),
                                onRetry: () {
                                  ref.invalidate(
                                    inventoryProductsProvider(
                                      _currentRequest(),
                                    ),
                                  );
                                },
                              ),
                          data: (products) {
                            _lastVisibleProducts = products;
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
                                      style: TextStyle(
                                        color: AppColors.textHint,
                                      ),
                                    ),
                                    if (canCreate) ...[
                                      const SizedBox(height: 24),
                                      FilledButton.icon(
                                        onPressed: () {
                                          ref
                                              .read(
                                                navigationLoadingProvider
                                                    .notifier,
                                              )
                                              .showFor();
                                          context.push('/inventory/add');
                                        },
                                        icon: const Icon(Icons.add_rounded),
                                        label: Text(
                                          AppStrings.inventoryAddProduct,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              );
                            }

                            return RefreshIndicator(
                              onRefresh: _refreshInventory,
                              child:
                                  isLargeDesktop
                                      ? GridView.builder(
                                        padding: const EdgeInsets.all(16),
                                        gridDelegate:
                                            SliverGridDelegateWithFixedCrossAxisCount(
                                              crossAxisCount: 4,
                                              mainAxisSpacing: 8,
                                              crossAxisSpacing: 8,
                                              childAspectRatio: 3.5,
                                            ),
                                        itemCount: _itemCount(products),
                                        itemBuilder: (context, index) {
                                          if (index == products.length) {
                                            return _LoadMoreTile(
                                              compact: true,
                                              onPressed: _loadMore,
                                            );
                                          }
                                          return _buildProductCard(
                                            context,
                                            products[index],
                                            canUpdate: canUpdate,
                                            canAdjustStock: canAdjustStock,
                                          );
                                        },
                                      )
                                      : isCompactDesktop
                                      ? GridView.builder(
                                        padding: const EdgeInsets.all(16),
                                        gridDelegate:
                                            SliverGridDelegateWithFixedCrossAxisCount(
                                              crossAxisCount: 3,
                                              mainAxisSpacing: 8,
                                              crossAxisSpacing: 8,
                                              childAspectRatio: 2.5,
                                            ),
                                        itemCount: _itemCount(products),
                                        itemBuilder: (context, index) {
                                          if (index == products.length) {
                                            return _LoadMoreTile(
                                              compact: true,
                                              onPressed: _loadMore,
                                            );
                                          }
                                          return _buildProductCard(
                                            context,
                                            products[index],
                                            canUpdate: canUpdate,
                                            canAdjustStock: canAdjustStock,
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
                                        itemCount: _itemCount(products),
                                        itemBuilder: (context, index) {
                                          if (index == products.length) {
                                            return _LoadMoreTile(
                                              compact: true,
                                              onPressed: _loadMore,
                                            );
                                          }
                                          return _buildProductCard(
                                            context,
                                            products[index],
                                            canUpdate: canUpdate,
                                            canAdjustStock: canAdjustStock,
                                          );
                                        },
                                      )
                                      : ListView.separated(
                                        padding: const EdgeInsets.all(16),
                                        itemCount: _itemCount(products),
                                        separatorBuilder:
                                            (_, _) => const SizedBox(height: 8),
                                        itemBuilder: (context, index) {
                                          if (index == products.length) {
                                            return _LoadMoreTile(
                                              onPressed: _loadMore,
                                            );
                                          }
                                          return _buildProductCard(
                                            context,
                                            products[index],
                                            canUpdate: canUpdate,
                                            canAdjustStock: canAdjustStock,
                                          );
                                        },
                                      ),
                            );
                          },
                        );
                      },
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  int _itemCount(List<ProductModel> products) {
    return products.length >= _visibleLimit
        ? products.length + 1
        : products.length;
  }

  Widget _buildProductCard(
    BuildContext context,
    ProductModel product, {
    required bool canUpdate,
    required bool canAdjustStock,
  }) {
    return ProductCard(
      product: product,
      canEdit: canUpdate,
      canAdjustStock: canAdjustStock,
      isSelectionMode: _isSelectionMode,
      isSelected: _selectedProductIds.contains(product.id),
      onSelectionChanged: (selected) => _toggleSelection(product.id, selected),
      onTap: () {
        ref.read(navigationLoadingProvider.notifier).showFor();
        context.push('/inventory/edit', extra: product);
      },
    );
  }

  Future<void> _showBulkPriceUpdate(BuildContext context) async {
    final List<ProductModel> products = ref
        .read(inventoryProductsProvider(_currentRequest()))
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
