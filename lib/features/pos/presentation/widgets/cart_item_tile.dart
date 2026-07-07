import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_strings.dart';
import '../../data/models/cart_item_model.dart';
import '../../data/models/discount_approval_model.dart';
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
          Row(
            children: [
              _QtyController(item: item),
              const Spacer(),
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
                            ? '-Rs ${item.discountAmount.toStringAsFixed(0)}'
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
              Text(
                'Rs ${item.lineTotal.toStringAsFixed(0)}',
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

  void _showDiscountDialog(BuildContext context, WidgetRef ref) {
    final ctrl = TextEditingController(
      text:
          item.discountAmount > 0 ? item.discountAmount.toStringAsFixed(0) : '',
    );
    final pinCtrl = TextEditingController();
    final reasonCtrl = TextEditingController();
    var type = DiscountType.fixed;

    showDialog(
      context: context,
      builder:
          (_) => StatefulBuilder(
            builder:
                (dialogContext, setDialogState) => AlertDialog(
                  title: const Text(AppStrings.itemDiscount),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SegmentedButton<DiscountType>(
                        segments: const [
                          ButtonSegment(
                            value: DiscountType.fixed,
                            label: Text('Rs'),
                          ),
                          ButtonSegment(
                            value: DiscountType.percent,
                            label: Text('%'),
                          ),
                        ],
                        selected: {type},
                        onSelectionChanged:
                            (values) =>
                                setDialogState(() => type = values.first),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: ctrl,
                        keyboardType: TextInputType.number,
                        autofocus: true,
                        decoration: InputDecoration(
                          hintText: AppStrings.hintDiscount,
                          prefixText: type == DiscountType.fixed ? 'Rs ' : null,
                          suffixText: type == DiscountType.percent ? '%' : null,
                          helperText:
                              type == DiscountType.fixed
                                  ? 'Max: Rs ${item.unitPrice.toStringAsFixed(0)} per item'
                                  : 'Max: 100%',
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: pinCtrl,
                        obscureText: true,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Manager PIN (if over limit)',
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: reasonCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Reason (optional)',
                        ),
                      ),
                    ],
                  ),
                  actions: [
                    TextButton(
                      onPressed: () {
                        ref
                            .read(cartProvider.notifier)
                            .setItemDiscount(item.productId, 0);
                        Navigator.pop(context);
                      },
                      child: const Text('Remove'),
                    ),
                    FilledButton(
                      onPressed: () async {
                        final discount = double.tryParse(ctrl.text) ?? 0;
                        if (discount < 0 ||
                            (type == DiscountType.fixed &&
                                discount > item.unitPrice) ||
                            (type == DiscountType.percent && discount > 100)) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(AppStrings.errorDiscountExceeds),
                              backgroundColor: AppColors.error,
                            ),
                          );
                          return;
                        }
                        final success = await ref
                            .read(discountControllerProvider.notifier)
                            .applyItemDiscount(
                              item: item,
                              type: type,
                              value: discount,
                              approvalPin: pinCtrl.text,
                              reason: reasonCtrl.text,
                            );
                        if (success && context.mounted) Navigator.pop(context);
                        if (!success && context.mounted) {
                          final error = ref.read(discountControllerProvider);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                error.error?.toString() ??
                                    'Discount apply nahi hua',
                              ),
                              backgroundColor: AppColors.error,
                            ),
                          );
                        }
                      },
                      child: const Text('Apply'),
                    ),
                  ],
                ),
          ),
    );
  }
}

class _QtyController extends ConsumerWidget {
  final CartItemModel item;

  const _QtyController({required this.item});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canIncrease = !item.isAtStockLimit;
    return Row(
      children: [
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
          tooltip: item.quantity == 1 ? 'Remove item' : 'Decrease quantity',
        ),
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
        _QtyButton(
          icon: Icons.add_rounded,
          onTap:
              canIncrease
                  ? () => ref
                      .read(cartProvider.notifier)
                      .incrementItem(item.productId)
                  : null,
          color: canIncrease ? AppColors.success : AppColors.textHint,
          tooltip: canIncrease ? 'Increase quantity' : 'Stock limit reached',
        ),
      ],
    );
  }
}

class _QtyButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final Color color;
  final String tooltip;

  const _QtyButton({
    required this.icon,
    required this.onTap,
    required this.color,
    required this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: color.withValues(alpha: 0.24)),
          ),
          child: Icon(icon, size: 17, color: color),
        ),
      ),
    );
  }
}
