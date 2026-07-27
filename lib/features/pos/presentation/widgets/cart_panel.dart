import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobileshop_saas/features/pos/data/models/sale_payment_model.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/entitlements/entitlement_provider.dart';
import '../../../accounts/presentation/providers/accounts_provider.dart';
import '../../domain/pos_payment_account_policy.dart';
import '../providers/pos_provider.dart';
import 'cart_item_tile.dart';
import 'customer_attach_sheet.dart';
import 'payment_method_sheet.dart';

class CartPanel extends ConsumerWidget {
  const CartPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart = ref.watch(cartProvider);
    final checkoutState = ref.watch(checkoutControllerProvider);
    final isLoading = checkoutState.isLoading;
    final checkoutEnabled = isEntitledActionVisible(
      ref.watch(featureEntitlementProvider('pos.checkout')).value,
    );

    if (cart.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.shopping_cart_outlined,
              size: 64,
              color: AppColors.textHint,
            ),
            const SizedBox(height: 12),
            const Text(
              AppStrings.cartEmpty,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              AppStrings.cartEmptyDesc,
              style: TextStyle(fontSize: 13, color: AppColors.textHint),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // ── Cart Header ──
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              Text(
                '${AppStrings.cartItems} (${cart.itemCount})',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              const Spacer(),
              // Customer attach button
              TextButton.icon(
                onPressed: () => showCustomerSheet(context, ref),
                icon: Icon(
                  cart.customer != null
                      ? Icons.person_rounded
                      : Icons.person_add_outlined,
                  size: 16,
                  color:
                      cart.customer != null
                          ? AppColors.primary
                          : AppColors.textSecondary,
                ),
                label: Text(
                  cart.customer?.fullName ?? AppStrings.attachCustomer,
                  style: TextStyle(
                    fontSize: 12,
                    color:
                        cart.customer != null
                            ? AppColors.primary
                            : AppColors.textSecondary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),

        // ── Cart Items ──
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: cart.items.length,
            separatorBuilder: (_, _) => const SizedBox(height: 6),
            itemBuilder: (context, index) {
              return CartItemTile(item: cart.items[index]);
            },
          ),
        ),

        // ── Totals Section ──
        Container(
          padding: const EdgeInsets.all(16),
          decoration: const BoxDecoration(
            color: AppColors.surface,
            border: Border(top: BorderSide(color: AppColors.border)),
          ),
          child: Column(
            children: [
              // Subtotal
              _TotalRow(label: AppStrings.cartSubtotal, value: cart.subtotal),

              // Discount (agar hai)
              if (cart.discountAmount > 0)
                _TotalRow(
                  label: AppStrings.cartDiscount,
                  value: -cart.discountAmount,
                  color: AppColors.success,
                ),

              // Tax (agar hai)
              if (cart.taxAmount > 0)
                _TotalRow(label: AppStrings.cartTax, value: cart.taxAmount),

              const Divider(height: 16),

              // Total
              _TotalRow(
                label: AppStrings.cartTotal,
                value: cart.total,
                isBold: true,
                fontSize: 18,
              ),
              const SizedBox(height: 12),

              // Payment section
              _PaymentSummary(cart: cart),
              const SizedBox(height: 12),

              // Checkout button
              if (checkoutEnabled)
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed:
                        isLoading
                            ? null
                            : cart.payments.isEmpty
                            ? () => _handleCashCheckout(context, ref)
                            : cart.isPaymentComplete
                            ? () => _handleCheckout(context, ref)
                            : () => showPaymentSheet(context, ref),
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          cart.isPaymentComplete
                              ? AppColors.success
                              : AppColors.primary,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
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
                              cart.payments.isEmpty
                                  ? 'Cash Sale — ₨${cart.total.toStringAsFixed(0)}'
                                  : cart.isPaymentComplete
                                  ? AppStrings.checkoutButton
                                  : AppStrings.paymentIncomplete,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _handleCheckout(BuildContext context, WidgetRef ref) async {
    final cart = ref.read(cartProvider);

    // Payment nahi ki → payment sheet kholo
    if (cart.payments.isEmpty) {
      showPaymentSheet(context, ref);
      return;
    }

    // Checkout karo
    final sale = await ref.read(checkoutControllerProvider.notifier).checkout();

    if (sale != null && context.mounted) {
      // Sale complete screen pe jao
      context.go('/pos/complete', extra: sale);
      return;
    }

    if (context.mounted) {
      final error = ref.read(checkoutControllerProvider).error;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _friendlyCheckoutError(error?.toString() ?? 'Checkout nahi hua'),
          ),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _handleCashCheckout(BuildContext context, WidgetRef ref) async {
    try {
      final accounts = await ref.read(accountsProvider.future);
      if (!context.mounted) return;

      final cashAccount = PosPaymentAccountPolicy.suggestedAccount(
        PaymentMethod.cash,
        accounts,
      );
      if (cashAccount == null) {
        showPaymentSheet(context, ref);
        return;
      }

      final cart = ref.read(cartProvider);
      ref
          .read(cartProvider.notifier)
          .setPayment(
            PaymentMethod.cash,
            cart.total,
            accountId: cashAccount.id,
          );
      await _handleCheckout(context, ref);
    } catch (_) {
      if (context.mounted) showPaymentSheet(context, ref);
    }
  }

  String _friendlyCheckoutError(String message) {
    return message
        .replaceFirst('Exception: ', '')
        .replaceFirst('PostgrestException(message: ', '')
        .split(', code:')
        .first;
  }
}

// ── Total Row ────────────────────────────────────────
class _TotalRow extends StatelessWidget {
  final String label;
  final double value;
  final Color? color;
  final bool isBold;
  final double fontSize;

  const _TotalRow({
    required this.label,
    required this.value,
    this.color,
    this.isBold = false,
    this.fontSize = 13,
  });

  @override
  Widget build(BuildContext context) {
    final textColor = color ?? AppColors.textPrimary;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: fontSize,
              color: isBold ? AppColors.textPrimary : AppColors.textSecondary,
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          const Spacer(),
          Text(
            '₨ ${value.abs().toStringAsFixed(0)}',
            style: TextStyle(
              fontSize: fontSize,
              color: textColor,
              fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Payment Summary ──────────────────────────────────
class _PaymentSummary extends ConsumerWidget {
  final CartState cart;

  const _PaymentSummary({required this.cart});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (cart.payments.isEmpty) {
      return SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: () => showPaymentSheet(context, ref),
          icon: const Icon(Icons.account_balance_wallet_outlined, size: 18),
          label: const Text('Other Payment / Khata'),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 12),
            foregroundColor: AppColors.primary,
          ),
        ),
      );
    }

    return Column(
      children: [
        // Payment method buttons
        Row(
          children:
              PaymentMethod.values.map((method) {
                final payment =
                    cart.payments.where((p) => p.method == method).firstOrNull;
                final isSelected = payment != null;
                final color = _methodColor(method);

                return Expanded(
                  child: GestureDetector(
                    onTap: () => showPaymentSheet(context, ref),
                    child: Container(
                      margin: const EdgeInsets.only(right: 6),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color:
                            isSelected
                                ? color.withValues(alpha: 0.12)
                                : AppColors.surfaceVariant,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isSelected ? color : AppColors.border,
                        ),
                      ),
                      child: Column(
                        children: [
                          Icon(
                            _methodIcon(method),
                            size: 18,
                            color: isSelected ? color : AppColors.textHint,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            isSelected
                                ? '₨${payment.amount.toStringAsFixed(0)}'
                                : method.label,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: isSelected ? color : AppColors.textHint,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
        ),

        // Remaining amount (agar payment incomplete)
        if (cart.payments.isNotEmpty && !cart.isPaymentComplete) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.error.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  AppStrings.paymentRemaining,
                  style: TextStyle(fontSize: 12, color: AppColors.error),
                ),
                Text(
                  '₨ ${cart.remainingAmount.toStringAsFixed(0)}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: AppColors.error,
                  ),
                ),
              ],
            ),
          ),
        ],

        // Payment complete badge
        if (cart.isPaymentComplete && cart.payments.isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.check_circle_rounded,
                  size: 14,
                  color: AppColors.success,
                ),
                SizedBox(width: 6),
                Text(
                  AppStrings.paymentComplete,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.success,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  IconData _methodIcon(PaymentMethod method) {
    switch (method) {
      case PaymentMethod.cash:
        return Icons.payments_rounded;
      case PaymentMethod.easypaisa:
        return Icons.phone_android_rounded;
      case PaymentMethod.jazzcash:
        return Icons.phone_android_rounded;
      case PaymentMethod.card:
        return Icons.credit_card_rounded;
      case PaymentMethod.credit:
        return Icons.account_balance_wallet_rounded;
    }
  }

  Color _methodColor(PaymentMethod method) {
    switch (method) {
      case PaymentMethod.cash:
        return AppColors.success;
      case PaymentMethod.easypaisa:
        return AppColors.secondary;
      case PaymentMethod.jazzcash:
        return AppColors.warning;
      case PaymentMethod.card:
        return AppColors.primary;
      case PaymentMethod.credit:
        return AppColors.error;
    }
  }
}
