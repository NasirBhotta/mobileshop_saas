import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_strings.dart';
import '../../data/models/sale_payment_model.dart';
import '../providers/pos_provider.dart';

void showPaymentSheet(BuildContext context, WidgetRef ref) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => PaymentMethodSheet(ref: ref),
  );
}

class PaymentMethodSheet extends ConsumerStatefulWidget {
  final WidgetRef ref;

  const PaymentMethodSheet({super.key, required this.ref});

  @override
  ConsumerState<PaymentMethodSheet> createState() => _PaymentMethodSheetState();
}

class _PaymentMethodSheetState extends ConsumerState<PaymentMethodSheet> {
  // Har method ka controller
  final Map<PaymentMethod, TextEditingController> _controllers = {
    for (final method in PaymentMethod.values) method: TextEditingController(),
  };

  @override
  void initState() {
    super.initState();
    // Existing payments se populate karo
    final cart = ref.read(cartProvider);
    for (final payment in cart.payments) {
      _controllers[payment.method]?.text = payment.amount.toStringAsFixed(0);
    }
  }

  @override
  void dispose() {
    for (final ctrl in _controllers.values) {
      ctrl.dispose();
    }
    super.dispose();
  }

  double get _totalEntered {
    return _controllers.values.fold(0, (sum, ctrl) {
      return sum + (double.tryParse(ctrl.text) ?? 0);
    });
  }

  void _applyPayments() {
    // Sab payments clear karo
    ref.read(cartProvider.notifier).clearPayments();

    // Naye payments set karo
    for (final method in PaymentMethod.values) {
      final amount = double.tryParse(_controllers[method]?.text ?? '') ?? 0;
      if (amount > 0) {
        ref.read(cartProvider.notifier).setPayment(method, amount);
      }
    }

    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartProvider);
    final remaining = cart.total - _totalEntered;
    final isComplete = remaining.abs() < 0.01;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        20,
        20,
        MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Title + Total
          Row(
            children: [
              const Text(
                AppStrings.paymentTitle,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              const Spacer(),
              Text(
                'Total: ₨${cart.total.toStringAsFixed(0)}',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Quick Cash button
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () {
                setState(() {
                  // Sab clear karo
                  for (final ctrl in _controllers.values) {
                    ctrl.clear();
                  }
                  // Cash mein poora amount daalo
                  _controllers[PaymentMethod.cash]?.text = cart.total
                      .toStringAsFixed(0);
                });
              },
              icon: const Icon(Icons.payments_rounded, size: 18),
              label: Text('Full Cash: ₨${cart.total.toStringAsFixed(0)}'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Payment methods
          ...PaymentMethod.values.map((method) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _PaymentMethodRow(
                method: method,
                controller: _controllers[method]!,
                onChanged: () => setState(() {}),
              ),
            );
          }),

          // Summary
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color:
                  isComplete
                      ? AppColors.success.withValues(alpha: 0.08)
                      : AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  isComplete
                      ? AppStrings.paymentComplete
                      : AppStrings.paymentRemaining,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color:
                        isComplete
                            ? AppColors.success
                            : AppColors.textSecondary,
                  ),
                ),
                Text(
                  isComplete ? '✓' : '₨${remaining.abs().toStringAsFixed(0)}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: isComplete ? AppColors.success : AppColors.error,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Apply button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: isComplete ? _applyPayments : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.success,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: const Text(
                'Payment Apply Karein',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PaymentMethodRow extends StatelessWidget {
  final PaymentMethod method;
  final TextEditingController controller;
  final VoidCallback onChanged;

  const _PaymentMethodRow({
    required this.method,
    required this.controller,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Method label
        SizedBox(
          width: 100,
          child: Text(
            method.label,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
        ),
        const SizedBox(width: 12),

        // Amount input
        Expanded(
          child: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            onChanged: (_) => onChanged(),
            decoration: InputDecoration(
              hintText: '0',
              prefixText: '₨ ',
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
