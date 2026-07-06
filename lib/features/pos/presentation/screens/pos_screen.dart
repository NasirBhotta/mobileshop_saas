import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/utils/responsive.dart';
import '../../../../shared/widgets/app_layout.dart';
import '../providers/pos_provider.dart';
import '../widgets/cart_panel.dart';
import '../widgets/product_search_panel.dart';

class PosScreen extends ConsumerWidget {
  const PosScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AppLayout(
      currentIndex: 1, // POS tab
      child: _PosBody(),
    );
  }
}

class _PosBody extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDesktop = Responsive.isDesktop(context);
    final isTablet = Responsive.isTablet(context);
    final cart = ref.watch(cartProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      // ── AppBar ──
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              AppStrings.posTitle,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            if (cart.itemCount > 0)
              Text(
                '${cart.itemCount} ${AppStrings.cartItemCount} • ₨${cart.total.toStringAsFixed(0)}',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
          ],
        ),
        actions: [
          IconButton(
            onPressed: () => context.push('/pos/return'),
            icon: const Icon(Icons.assignment_return_rounded),
            color: AppColors.textSecondary,
            tooltip: 'Return / Refund',
          ),
          IconButton(
            onPressed: () => context.push('/pos/reprint'),
            icon: const Icon(Icons.receipt_long_rounded),
            color: AppColors.textSecondary,
            tooltip: 'Reprint Receipt',
          ),

          // Held carts button
          Stack(
            children: [
              IconButton(
                onPressed: () => context.push('/pos/held'),
                icon: const Icon(Icons.pause_circle_outline_rounded),
                color: AppColors.textSecondary,
                tooltip: AppStrings.posHeldCarts,
              ),
              // Held carts count badge
              _HeldCartsBadge(),
            ],
          ),

          // Hold button (cart mein items hon tabhi)
          if (cart.itemCount > 0)
            IconButton(
              onPressed: () => _showHoldDialog(context, ref),
              icon: const Icon(Icons.pause_rounded),
              color: AppColors.warning,
              tooltip: AppStrings.holdCart,
            ),

          // Void button (cart mein items hon tabhi)
          if (cart.itemCount > 0)
            IconButton(
              onPressed: () => _showVoidDialog(context, ref),
              icon: const Icon(Icons.delete_outline_rounded),
              color: AppColors.error,
              tooltip: AppStrings.voidCart,
            ),

          const SizedBox(width: 8),
        ],
      ),

      // ── Body ──
      body:
          isDesktop || isTablet
              ? _SplitLayout() // Tablet + Desktop → side by side
              : _MobileLayout(), // Mobile → stack
    );
  }

  // Hold dialog
  void _showHoldDialog(BuildContext context, WidgetRef ref) {
    final labelCtrl = TextEditingController();

    showDialog(
      context: context,
      builder:
          (_) => AlertDialog(
            title: const Text(AppStrings.holdCart),
            content: TextField(
              controller: labelCtrl,
              decoration: const InputDecoration(
                labelText: AppStrings.holdCartLabel,
                hintText: AppStrings.hintHoldLabel,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () async {
                  Navigator.pop(context);
                  final success = await ref
                      .read(checkoutControllerProvider.notifier)
                      .holdCart(
                        label:
                            labelCtrl.text.trim().isEmpty
                                ? null
                                : labelCtrl.text.trim(),
                      );
                  if (success && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(AppStrings.holdSuccess),
                        backgroundColor: AppColors.success,
                      ),
                    );
                  }
                },
                child: const Text('Hold Karein'),
              ),
            ],
          ),
    );
  }

  // Void dialog
  void _showVoidDialog(BuildContext context, WidgetRef ref) {
    final reasonCtrl = TextEditingController();

    showDialog(
      context: context,
      builder:
          (_) => AlertDialog(
            title: const Text(AppStrings.voidCart),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(AppStrings.voidCartConfirm),
                const SizedBox(height: 12),
                TextField(
                  controller: reasonCtrl,
                  decoration: const InputDecoration(
                    labelText: AppStrings.voidReason,
                    hintText: AppStrings.hintVoidReason,
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: AppColors.error),
                onPressed: () async {
                  Navigator.pop(context);
                  await ref
                      .read(checkoutControllerProvider.notifier)
                      .voidCart(
                        reason:
                            reasonCtrl.text.trim().isEmpty
                                ? null
                                : reasonCtrl.text.trim(),
                      );
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(AppStrings.voidSuccess),
                        backgroundColor: AppColors.warning,
                      ),
                    );
                  }
                },
                child: const Text(AppStrings.voidConfirmButton),
              ),
            ],
          ),
    );
  }
}

// ════════════════════════════════════════
// MOBILE LAYOUT
// ════════════════════════════════════════
class _MobileLayout extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart = ref.watch(cartProvider);

    return Column(
      children: [
        // Products panel — flexible
        Expanded(child: ProductSearchPanel()),

        // Cart summary bar (bottom) — sirf tab dikhao jab items hon
        if (cart.itemCount > 0) _MobileCartBar(cart: cart),
      ],
    );
  }
}

// Mobile bottom cart bar
class _MobileCartBar extends ConsumerWidget {
  final CartState cart;

  const _MobileCartBar({required this.cart});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      onTap: () => _showCartSheet(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: const BoxDecoration(
          color: AppColors.primary,
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Row(
          children: [
            // Item count badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '${cart.itemCount} items',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const Spacer(),

            // Total
            Text(
              '₨ ${cart.total.toStringAsFixed(0)}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.keyboard_arrow_up_rounded, color: Colors.white),
          ],
        ),
      ),
    );
  }

  void _showCartSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder:
          (_) => DraggableScrollableSheet(
            initialChildSize: 0.85,
            minChildSize: 0.5,
            maxChildSize: 0.95,
            expand: false,
            builder: (_, scrollController) => const CartPanel(),
          ),
    );
  }
}

// ════════════════════════════════════════
// TABLET + DESKTOP SPLIT LAYOUT
// ════════════════════════════════════════
class _SplitLayout extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final isDesktop = Responsive.isDesktop(context);

    return Row(
      children: [
        // Left: Products panel
        Expanded(
          flex: isDesktop ? 3 : 2, // Desktop pe zyada space
          child: Container(
            decoration: const BoxDecoration(
              border: Border(right: BorderSide(color: AppColors.border)),
            ),
            child: ProductSearchPanel(),
          ),
        ),

        // Right: Cart panel
        Expanded(
          flex: isDesktop ? 2 : 3,
          child: Container(color: AppColors.surface, child: const CartPanel()),
        ),
      ],
    );
  }
}

// ── Held Carts Badge ─────────────────────────────────
class _HeldCartsBadge extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final heldCarts = ref.watch(heldCartsProvider);

    return heldCarts.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (carts) {
        if (carts.isEmpty) return const SizedBox.shrink();
        return Positioned(
          right: 6,
          top: 6,
          child: Container(
            width: 16,
            height: 16,
            decoration: const BoxDecoration(
              color: AppColors.error,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                '${carts.length}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
