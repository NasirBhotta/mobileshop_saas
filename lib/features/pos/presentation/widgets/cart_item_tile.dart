import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_strings.dart';
import '../../data/models/cart_item_model.dart';
import '../providers/pos_provider.dart';

class CartItemTile extends ConsumerWidget {
  final CartItemModel item;

  const CartItemTile({super.key, required this.item});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          // ── Top Row: Name + Remove ──
          Row(
            children: [
              Expanded(
                child: Text(
                  item.productName,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // Remove button
              GestureDetector(
                onTap:
                    () => ref
                        .read(cartProvider.notifier)
                        .removeItem(item.productId),
                child: const Icon(
                  Icons.close_rounded,
                  size: 18,
                  color: AppColors.textHint,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // ── Bottom Row: Qty + Discount + Line Total ──
          Row(
            children: [
              // Quantity stepper
              _QtyController(item: item),
              const Spacer(),

              // Discount button
              GestureDetector(
                onTap: () => _showDiscountDialog(context, ref),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color:
                        item.discountAmount > 0
                            ? AppColors.warning.withValues(alpha: 0.1)
                            : AppColors.surfaceVariant,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color:
                          item.discountAmount > 0
                              ? AppColors.warning
                              : AppColors.border,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.percent_rounded,
                        size: 12,
                        color:
                            item.discountAmount > 0
                                ? AppColors.warning
                                : AppColors.textHint,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        item.discountAmount > 0
                            ? '-₨${item.discountAmount.toStringAsFixed(0)}'
                            : AppStrings.itemDiscount,
                        style: TextStyle(
                          fontSize: 11,
                          color:
                              item.discountAmount > 0
                                  ? AppColors.warning
                                  : AppColors.textHint,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),

              // Line total
              Text(
                '₨ ${item.lineTotal.toStringAsFixed(0)}',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Discount dialog
  void _showDiscountDialog(BuildContext context, WidgetRef ref) {
    final ctrl = TextEditingController(
      text:
          item.discountAmount > 0 ? item.discountAmount.toStringAsFixed(0) : '',
    );

    showDialog(
      context: context,
      builder:
          (_) => AlertDialog(
            title: const Text(AppStrings.itemDiscount),
            content: TextField(
              controller: ctrl,
              keyboardType: TextInputType.number,
              autofocus: true,
              decoration: InputDecoration(
                hintText: AppStrings.hintDiscount,
                prefixText: '₨ ',
                helperText:
                    'Max: ₨${item.unitPrice.toStringAsFixed(0)} per item',
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  // Discount hata do
                  ref
                      .read(cartProvider.notifier)
                      .setItemDiscount(item.productId, 0);
                  Navigator.pop(context);
                },
                child: const Text('Remove'),
              ),
              FilledButton(
                onPressed: () {
                  final discount = double.tryParse(ctrl.text) ?? 0;
                  if (discount < 0 || discount > item.unitPrice) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(AppStrings.errorDiscountExceeds),
                        backgroundColor: AppColors.error,
                      ),
                    );
                    return;
                  }
                  ref
                      .read(cartProvider.notifier)
                      .setItemDiscount(item.productId, discount);
                  Navigator.pop(context);
                },
                child: const Text('Apply'),
              ),
            ],
          ),
    );
  }
}

// ── Quantity Controller ──────────────────────────────
class _QtyController extends ConsumerWidget {
  final CartItemModel item;

  const _QtyController({required this.item});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      children: [
        // Decrement
        _QtyButton(
          icon: Icons.remove_rounded,
          onTap:
              () =>
                  item.quantity == 1
                      ? ref
                          .read(cartProvider.notifier)
                          .removeItem(item.productId)
                      : ref
                          .read(cartProvider.notifier)
                          .decrementItem(item.productId),
          color: item.quantity == 1 ? AppColors.error : AppColors.textSecondary,
        ),

        // Quantity
        Container(
          width: 36,
          alignment: Alignment.center,
          child: Text(
            '${item.quantity}',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
        ),

        // Increment
        _QtyButton(
          icon: Icons.add_rounded,
          onTap:
              () =>
                  ref.read(cartProvider.notifier).incrementItem(item.productId),
          color: AppColors.primary,
        ),
      ],
    );
  }
}

class _QtyButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final Color color;

  const _QtyButton({
    required this.icon,
    required this.onTap,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(icon, size: 16, color: color),
      ),
    );
  }
}
