import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/utils/responsive.dart';
import '../../data/models/held_cart_model.dart';
import '../providers/pos_provider.dart';

class HeldCartsScreen extends ConsumerWidget {
  const HeldCartsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final heldCartsAsync = ref.watch(heldCartsProvider);
    final isDesktop = Responsive.isDesktop(context);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(AppStrings.posHeldCarts),
        backgroundColor: AppColors.surface,
        elevation: 0,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: isDesktop ? 640 : double.infinity,
          ),
          child: heldCartsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text(e.toString())),
            data: (carts) {
              if (carts.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(
                        Icons.pause_circle_outline_rounded,
                        size: 64,
                        color: AppColors.textHint,
                      ),
                      SizedBox(height: 16),
                      Text(
                        AppStrings.noHeldCarts,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        AppStrings.noHeldCartsDesc,
                        style: TextStyle(color: AppColors.textHint),
                      ),
                    ],
                  ),
                );
              }

              return ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: carts.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  return _HeldCartTile(
                    cart: carts[index],
                    onResume: () {
                      // Cart resume karo
                      ref
                          .read(cartProvider.notifier)
                          .resumeFromHeld(carts[index]);

                      // Held cart delete karo
                      ref
                          .read(posRepositoryProvider)
                          .deleteHeldCart(carts[index].id!);

                      ref.invalidate(heldCartsProvider);

                      // POS screen pe wapas jao
                      context.go('/pos');
                    },
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }
}

class _HeldCartTile extends StatelessWidget {
  final HeldCartModel cart;
  final VoidCallback onResume;

  const _HeldCartTile({required this.cart, required this.onResume});

  @override
  Widget build(BuildContext context) {
    // Total calculate karo
    final total = cart.items.fold<double>(
      0,
      (sum, item) => sum + item.lineTotal,
    );

    // Expire check
    final isExpired =
        cart.expiresAt != null && DateTime.now().isAfter(cart.expiresAt!);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isExpired ? AppColors.error : AppColors.border,
        ),
      ),
      child: Row(
        children: [
          // Icon
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color:
                  isExpired
                      ? AppColors.error.withValues(alpha: 0.1)
                      : AppColors.warning.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.pause_rounded,
              color: isExpired ? AppColors.error : AppColors.warning,
            ),
          ),
          const SizedBox(width: 12),

          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  cart.label ?? 'Held Cart',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${cart.items.length} items • ₨${total.toStringAsFixed(0)}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
                if (cart.customerName != null)
                  Text(
                    cart.customerName!,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.primary,
                    ),
                  ),
                if (isExpired)
                  const Text(
                    'Expired',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.error,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
          ),

          // Resume button
          if (!isExpired)
            FilledButton(
              onPressed: onResume,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
              ),
              child: const Text(AppStrings.resumeCart),
            ),
        ],
      ),
    );
  }
}
