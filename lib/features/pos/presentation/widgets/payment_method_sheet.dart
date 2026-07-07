import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/utils/responsive.dart';
import '../../data/models/sale_payment_model.dart';
import '../providers/pos_provider.dart';

void showPaymentSheet(BuildContext context, WidgetRef ref) {
  if (Responsive.isDesktop(context)) {
    showDialog<void>(
      context: context,
      builder:
          (_) => Dialog(
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 32,
              vertical: 24,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: PaymentMethodSheet(ref: ref, showHandle: false),
            ),
          ),
    );
    return;
  }

  showModalBottomSheet<void>(
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
  final bool showHandle;

  const PaymentMethodSheet({
    super.key,
    required this.ref,
    this.showHandle = true,
  });

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
      return sum + _parseAmount(ctrl.text);
    });
  }

  void _applyPayments() {
    // Sab payments clear karo
    ref.read(cartProvider.notifier).clearPayments();
    final cart = ref.read(cartProvider);
    final enteredAmounts = <PaymentMethod, double>{
      for (final method in PaymentMethod.values)
        method: _parseAmount(_controllers[method]?.text ?? ''),
    };
    final selectedMethods =
        PaymentMethod.values
            .where((method) => (enteredAmounts[method] ?? 0) > 0)
            .toList();

    if (selectedMethods.isEmpty) return;

    _normalizePaymentAmounts(enteredAmounts, selectedMethods, cart.total);

    // Naye payments set karo
    for (final method in PaymentMethod.values) {
      final amount = enteredAmounts[method] ?? 0;
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
    final isComplete =
        _totalEntered > 0 &&
        (_totalEntered >= cart.total - 0.01 ||
            _totalEntered.round() == cart.total.round());

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
          if (widget.showHandle) ...[
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
          ],

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
              if (!widget.showHandle) ...[
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                  tooltip: 'Close',
                ),
                const SizedBox(width: 4),
              ],
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

          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.info.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.info.withValues(alpha: 0.2)),
            ),
            child: Text(
              cart.customer == null
                  ? 'Khata payment ke liye customer attach karna zaroori hai.'
                  : 'Khata ${cart.customer!.fullName} ke outstanding balance mein add ho ga.',
              style: const TextStyle(
                color: AppColors.info,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
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

  double _parseAmount(String value) {
    final normalized = value.replaceAll(',', '').trim();
    return double.tryParse(normalized) ?? 0;
  }

  void _normalizePaymentAmounts(
    Map<PaymentMethod, double> amounts,
    List<PaymentMethod> selectedMethods,
    double cartTotal,
  ) {
    var delta =
        cartTotal -
        amounts.values.fold<double>(0, (sum, amount) => sum + amount);
    if (delta.abs() < 0.01) return;

    if (delta > 0) {
      final method =
          selectedMethods.contains(PaymentMethod.cash)
              ? PaymentMethod.cash
              : selectedMethods.last;
      amounts[method] = (amounts[method] ?? 0) + delta;
      return;
    }

    var overpay = -delta;
    final reductionOrder = [
      if (selectedMethods.contains(PaymentMethod.cash)) PaymentMethod.cash,
      ...selectedMethods.reversed.where((m) => m != PaymentMethod.cash),
    ];
    for (final method in reductionOrder) {
      if (overpay <= 0) break;
      final current = amounts[method] ?? 0;
      final reduction = current < overpay ? current : overpay;
      amounts[method] = current - reduction;
      overpay -= reduction;
    }

    delta =
        cartTotal -
        amounts.values.fold<double>(0, (sum, amount) => sum + amount);
    if (delta.abs() >= 0.01 && selectedMethods.isNotEmpty) {
      final method = selectedMethods.last;
      amounts[method] =
          ((amounts[method] ?? 0) + delta).clamp(0, double.infinity).toDouble();
    }
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
    final color = _methodColor(method);
    return Row(
      children: [
        // Method label
        SizedBox(
          width: 100,
          child: Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(_methodIcon(method), color: color, size: 16),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  method.label,
                  style: TextStyle(fontWeight: FontWeight.w700, color: color),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
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
              enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(color: color.withValues(alpha: 0.35)),
              ),
              focusedBorder: OutlineInputBorder(
                borderSide: BorderSide(color: color, width: 1.4),
              ),
            ),
          ),
        ),
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
        return Icons.phone_iphone_rounded;
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
