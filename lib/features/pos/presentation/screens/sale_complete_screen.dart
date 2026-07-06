import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/utils/responsive.dart';
import '../../data/models/sale_model.dart';
import '../../data/services/receipt_service.dart';
import '../providers/pos_provider.dart';

class SaleCompleteScreen extends ConsumerWidget {
  final SaleModel sale;

  const SaleCompleteScreen({super.key, required this.sale});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDesktop = Responsive.isDesktop(context);
    final footer = ref
        .watch(receiptFooterProvider)
        .maybeWhen(data: (value) => value, orElse: () => null);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: isDesktop ? 480 : double.infinity,
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: IconButton.filledTonal(
                      onPressed: () => context.go('/pos'),
                      icon: const Icon(Icons.arrow_back_rounded),
                      tooltip: 'Back',
                    ),
                  ),
                  const SizedBox(height: 24),

                  // ── Success Icon ──
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: AppColors.success.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.check_circle_rounded,
                      color: AppColors.success,
                      size: 48,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // ── Title ──
                  const Text(
                    AppStrings.saleCompleteTitle,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Invoice #${sale.id?.substring(0, 8).toUpperCase()}',
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // ── Receipt Card ──
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Customer (agar hai)
                        if (sale.customerName != null) ...[
                          _ReceiptRow(
                            label: 'Customer',
                            value: sale.customerName!,
                          ),
                          const Divider(height: 16),
                        ],

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

                        const Divider(height: 16),

                        // Subtotal
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

                        const Divider(height: 16),

                        // Total
                        Row(
                          children: [
                            const Text(
                              AppStrings.cartTotal,
                              style: TextStyle(
                                fontSize: 16,
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

                        const Divider(height: 16),

                        // Payments
                        const Text(
                          AppStrings.saleCompletePayments,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        ...sale.payments.map(
                          (p) => _ReceiptRow(
                            label: p.method.name,
                            value: '₨ ${p.amount.toStringAsFixed(0)}',
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // ── Action Buttons ──
                  Wrap(
                    spacing: 12,
                    runSpacing: 10,
                    children: [
                      OutlinedButton.icon(
                        onPressed:
                            () => _deliverReceipt(
                              ReceiptDeliveryMethod.thermalPrint,
                              footer,
                            ),
                        icon: const Icon(Icons.print_rounded, size: 18),
                        label: const Text(AppStrings.printReceipt),
                      ),
                      OutlinedButton.icon(
                        onPressed:
                            () => _deliverReceipt(
                              ReceiptDeliveryMethod.whatsapp,
                              footer,
                            ),
                        icon: const Icon(Icons.chat_rounded, size: 18),
                        label: const Text('WhatsApp'),
                      ),
                      OutlinedButton.icon(
                        onPressed:
                            () => _deliverReceipt(
                              ReceiptDeliveryMethod.email,
                              footer,
                            ),
                        icon: const Icon(Icons.email_rounded, size: 18),
                        label: const Text('Email'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => _shareReceipt(footer),
                        icon: const Icon(Icons.share_rounded, size: 18),
                        label: const Text(AppStrings.shareReceipt),
                      ),
                      FilledButton.icon(
                        onPressed: () => context.go('/pos'),
                        icon: const Icon(
                          Icons.add_shopping_cart_rounded,
                          size: 18,
                        ),
                        label: const Text(AppStrings.newSale),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _deliverReceipt(ReceiptDeliveryMethod method, String? footer) {
    return ReceiptService.deliver(sale: sale, method: method, footer: footer);
  }

  Future<void> _shareReceipt(String? footer) {
    return ReceiptService.deliver(
      sale: sale,
      method: ReceiptDeliveryMethod.whatsapp,
      footer: footer,
    );
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
