import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/utils/responsive.dart';
import '../../../../core/entitlements/entitlement_provider.dart';
import '../../data/models/sale_model.dart';
import '../../data/services/receipt_service.dart';
import '../providers/pos_provider.dart';
import '../../../settings/data/models/receipt_configuration_model.dart';
import '../../../settings/presentation/providers/receipt_settings_provider.dart';

class SaleCompleteScreen extends ConsumerWidget {
  final SaleModel sale;

  const SaleCompleteScreen({super.key, required this.sale});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDesktop = Responsive.isDesktop(context);
    final footer = ref
        .watch(receiptFooterProvider)
        .maybeWhen(data: (value) => value, orElse: () => null);
    final receiptPrintingEnabled = isEntitledActionVisible(
      ref.watch(featureEntitlementProvider('pos.receipt_printing')).value,
    );

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: Padding(
          padding: const EdgeInsets.only(left: 12.0),
          child: Center(
            child: IconButton.filledTonal(
              onPressed: () => context.go('/pos'),
              icon: const Icon(Icons.arrow_back_rounded),
              tooltip: 'Back to POS',
            ),
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: FilledButton.tonalIcon(
              onPressed: () => context.go('/pos'),
              icon: const Icon(Icons.add_shopping_cart_rounded, size: 18),
              label: const Text(AppStrings.newSale),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: isDesktop ? 520 : double.infinity,
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Column(
                children: [
                  // ── Success Icon ──
                  Container(
                    width: 76,
                    height: 76,
                    decoration: BoxDecoration(
                      color: AppColors.success.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.check_circle_rounded,
                      color: AppColors.success,
                      size: 46,
                    ),
                  ),
                  const SizedBox(height: 14),

                  // ── Title ──
                  const Text(
                    AppStrings.saleCompleteTitle,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Text(
                      'Invoice #${sale.id?.substring(0, 8).toUpperCase() ?? ''}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // ── Receipt Card ──
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.border),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.03),
                          blurRadius: 16,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Customer (agar hai)
                        if (sale.customerName != null) ...[
                          Row(
                            children: [
                              const Icon(
                                Icons.person_outline_rounded,
                                size: 18,
                                color: AppColors.textSecondary,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                sale.customerName!,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                            ],
                          ),
                          const Divider(height: 20),
                        ],

                        // Items header
                        const Text(
                          'Items Summary',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textSecondary,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 10),

                        // Items
                        ...sale.items.map(
                          (item) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    '${item.productName} × ${item.quantity}',
                                    style: const TextStyle(
                                      fontSize: 13,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                ),
                                Text(
                                  '₨ ${item.lineTotal.toStringAsFixed(0)}',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: AppColors.textPrimary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                        const Divider(height: 20),

                        // Subtotal & Discounts
                        if (sale.discountAmount > 0) ...[
                          _ReceiptRow(
                            label: AppStrings.cartSubtotal,
                            value: '₨ ${sale.subtotal.toStringAsFixed(0)}',
                          ),
                          _ReceiptRow(
                            label: AppStrings.cartDiscount,
                            value:
                                '-₨ ${sale.discountAmount.toStringAsFixed(0)}',
                            valueColor: AppColors.success,
                          ),
                        ],

                        // Tax
                        if (sale.taxAmount > 0)
                          _ReceiptRow(
                            label: AppStrings.cartTax,
                            value: '₨ ${sale.taxAmount.toStringAsFixed(0)}',
                          ),

                        if (sale.discountAmount > 0 || sale.taxAmount > 0)
                          const Divider(height: 20),

                        // Total Box
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            children: [
                              const Text(
                                AppStrings.cartTotal,
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                '₨ ${sale.total.toStringAsFixed(0)}',
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.primary,
                                ),
                              ),
                            ],
                          ),
                        ),

                        const Divider(height: 20),

                        // Payments
                        const Text(
                          AppStrings.saleCompletePayments,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textSecondary,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 8),
                        ...sale.payments.map(
                          (p) => _ReceiptRow(
                            label: p.method.name.toUpperCase(),
                            value: '₨ ${p.amount.toStringAsFixed(0)}',
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // ── Action Buttons ──
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      if (receiptPrintingEnabled)
                        OutlinedButton.icon(
                          onPressed:
                              () => _deliverReceipt(
                                ReceiptDeliveryMethod.thermalPrint,
                                footer,
                                ref,
                              ),
                          icon: const Icon(Icons.print_rounded, size: 18),
                          label: const Text(AppStrings.printReceipt),
                        ),
                      if (receiptPrintingEnabled)
                        OutlinedButton.icon(
                          onPressed:
                              () => _deliverReceipt(
                                ReceiptDeliveryMethod.whatsapp,
                                footer,
                                ref,
                              ),
                          icon: const Icon(Icons.chat_rounded, size: 18),
                          label: const Text('WhatsApp'),
                        ),
                      if (receiptPrintingEnabled)
                        OutlinedButton.icon(
                          onPressed:
                              () => _deliverReceipt(
                                ReceiptDeliveryMethod.email,
                                footer,
                                ref,
                              ),
                          icon: const Icon(Icons.email_rounded, size: 18),
                          label: const Text('Email'),
                        ),
                      if (receiptPrintingEnabled)
                        OutlinedButton.icon(
                          onPressed: () => _shareReceipt(footer, ref),
                          icon: const Icon(Icons.share_rounded, size: 18),
                          label: const Text(AppStrings.shareReceipt),
                        ),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 12,
                          ),
                        ),
                        onPressed: () => context.go('/pos'),
                        icon: const Icon(
                          Icons.add_shopping_cart_rounded,
                          size: 18,
                        ),
                        label: const Text(AppStrings.newSale),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _deliverReceipt(
    ReceiptDeliveryMethod method,
    String? footer,
    WidgetRef ref,
  ) async {
    ReceiptConfigurationModel? config;
    try {
      config = await ref.read(receiptConfigurationProvider.future);
    } catch (_) {
      config = ReceiptConfigurationModel.defaultConfig();
    }
    return ReceiptService.deliver(
      sale: sale,
      method: method,
      config: config,
      footer: footer,
      entitlementEvaluator: ref.read(entitlementEvaluatorProvider),
    );
  }

  Future<void> _shareReceipt(String? footer, WidgetRef ref) {
    return _deliverReceipt(ReceiptDeliveryMethod.whatsapp, footer, ref);
  }
}

class _ReceiptRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const _ReceiptRow({
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: valueColor ?? AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
