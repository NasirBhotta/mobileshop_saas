import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobileshop_saas/features/inventory/presentation/widgets/category_filter_bar.dart';
import 'package:mobileshop_saas/features/inventory/presentation/widgets/product_card.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../shared/providers/navigation_loading_provider.dart';
import '../../../../shared/widgets/app_layout.dart';
import '../providers/inventory_provider.dart';

class InventoryScreen extends ConsumerWidget {
  const InventoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AppLayout(currentIndex: 2, child: _InventoryBody());
  }
}

class _InventoryBody extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final productsState = ref.watch(productsProvider);
    final categoriesState = ref.watch(categoriesProvider);
    final selectedCategory = ref.watch(selectedCategoryProvider);

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
                  const Expanded(
                    child: Text(
                      AppStrings.inventoryTitle,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
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
              ),
            ),

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
                    child: ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: products.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final product = products[index];
                        return ProductCard(
                          product: product,
                          onTap: () {
                            ref
                                .read(navigationLoadingProvider.notifier)
                                .showFor();
                            context.push('/inventory/edit', extra: product);
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
}
