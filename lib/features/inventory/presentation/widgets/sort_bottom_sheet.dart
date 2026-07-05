// features/inventory/presentation/widgets/sort_bottom_sheet.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobileshop_saas/core/extensions/product_sort_ext.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_strings.dart';
import '../providers/inventory_provider.dart';

void showSortSheet(BuildContext context, WidgetRef ref) {
  showModalBottomSheet(
    context: context,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) => _SortSheet(ref: ref),
  );
}

class _SortSheet extends StatelessWidget {
  final WidgetRef ref;

  const _SortSheet({required this.ref});

  @override
  Widget build(BuildContext context) {
    final currentSort = ref.watch(sortOptionProvider);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),

          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                AppStrings.sortBy,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),

          // Sort options
          ...ProductSortOption.values.map((option) {
            final isSelected = currentSort == option;
            return ListTile(
              dense: true,
              leading: Icon(
                _sortIcon(option),
                color: isSelected ? AppColors.primary : AppColors.textSecondary,
                size: 20,
              ),
              title: Text(
                option.label,
                style: TextStyle(
                  color: isSelected ? AppColors.primary : AppColors.textPrimary,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
              trailing:
                  isSelected
                      ? const Icon(
                        Icons.check_rounded,
                        color: AppColors.primary,
                        size: 18,
                      )
                      : null,
              onTap: () {
                ref.read(sortOptionProvider.notifier).state = option;
                Navigator.pop(context);
              },
            );
          }),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  IconData _sortIcon(ProductSortOption option) {
    switch (option) {
      case ProductSortOption.nameAZ:
      case ProductSortOption.nameZA:
        return Icons.sort_by_alpha_rounded;
      case ProductSortOption.priceLow:
      case ProductSortOption.priceHigh:
        return Icons.attach_money_rounded;
      case ProductSortOption.stockLow:
      case ProductSortOption.stockHigh:
        return Icons.inventory_2_rounded;
    }
  }
}
