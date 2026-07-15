import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobileshop_saas/core/constants/app_strings.dart';
import 'package:mobileshop_saas/core/entitlements/entitlement_provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../data/models/product_model.dart';

class ProductCard extends ConsumerWidget {
  final ProductModel product;
  final VoidCallback onTap;
  final bool isSelectionMode;
  final bool isSelected;
  final ValueChanged<bool>? onSelectionChanged;

  const ProductCard({
    super.key,
    required this.product,
    required this.onTap,
    this.isSelectionMode = false,
    this.isSelected = false,
    this.onSelectionChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isLowStock = product.stock <= 5;
    final isOutOfStock = product.stock == 0;
    final stockAdjustmentsEnabled = isEntitledActionVisible(
      ref
          .watch(featureEntitlementProvider('inventory.stock_adjustments'))
          .value,
    );

    return InkWell(
      onTap:
          isSelectionMode ? () => onSelectionChanged?.call(!isSelected) : onTap,
      onLongPress: () => onSelectionChanged?.call(true),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color:
              isSelected
                  ? AppColors.primary.withValues(alpha: 0.06)
                  : AppColors.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.border,
          ),
        ),
        child: Row(
          children: [
            if (isSelectionMode) ...[
              Checkbox(
                value: isSelected,
                onChanged: (value) => onSelectionChanged?.call(value ?? false),
              ),
              const SizedBox(width: 8),
            ],
            // Product icon
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.phone_android_rounded,
                color: AppColors.primary,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),

            // Name + category
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                      fontSize: 14,
                    ),
                  ),
                  if (product.categoryName != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      product.categoryName!,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // Price + stock
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '₨ ${product.salePrice.toStringAsFixed(0)}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color:
                        isOutOfStock
                            ? AppColors.error.withValues(alpha: 0.1)
                            : isLowStock
                            ? AppColors.warning.withValues(alpha: 0.1)
                            : AppColors.success.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    isOutOfStock ? 'Out of Stock' : '${product.stock} in stock',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color:
                          isOutOfStock
                              ? AppColors.error
                              : isLowStock
                              ? AppColors.warning
                              : AppColors.success,
                    ),
                  ),
                ),
                SizedBox(height: 5),
                // ProductCard ke andar, bottom mein
                if (stockAdjustmentsEnabled)
                  TextButton.icon(
                    onPressed:
                        () => context.push('/inventory/adjust', extra: product),
                    icon: const Icon(Icons.tune_rounded, size: 16),
                    label: const Text(AppStrings.stockAdjust),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      padding: EdgeInsets.only(
                        left: 15,
                        right: 15,
                        top: 5,
                        bottom: 5,
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
