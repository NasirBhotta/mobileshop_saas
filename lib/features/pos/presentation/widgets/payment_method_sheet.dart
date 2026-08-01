import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/utils/responsive.dart';
import '../../../../core/entitlements/entitlement_provider.dart';
import '../../data/models/sale_payment_model.dart';
import '../../domain/pos_payment_account_policy.dart';
import '../providers/pos_provider.dart';
import '../../../accounts/data/models/account_models.dart';
import '../../../accounts/presentation/providers/accounts_provider.dart';

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
    enableDrag: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder:
        (sheetContext) => DraggableScrollableSheet(
          initialChildSize: 0.8,
          minChildSize: 0.45,
          maxChildSize: 0.95,
          expand: false,
          builder: (context, scrollController) {
            return PaymentMethodSheet(
              ref: ref,
              scrollController: scrollController,
            );
          },
        ),
  );
}

class PaymentMethodSheet extends ConsumerStatefulWidget {
  final WidgetRef ref;
  final bool showHandle;
  final ScrollController? scrollController;

  const PaymentMethodSheet({
    super.key,
    required this.ref,
    this.showHandle = true,
    this.scrollController,
  });

  @override
  ConsumerState<PaymentMethodSheet> createState() => _PaymentMethodSheetState();
}

class _PaymentMethodSheetState extends ConsumerState<PaymentMethodSheet> {
  // Har method ka controller
  final Map<PaymentMethod, TextEditingController> _controllers = {
    for (final method in PaymentMethod.values) method: TextEditingController(),
  };
  final Map<PaymentMethod, String?> _accountIds = {};

  @override
  void initState() {
    super.initState();
    // Existing payments se populate karo
    final cart = ref.read(cartProvider);
    for (final payment in cart.payments) {
      _controllers[payment.method]?.text = payment.amount.toStringAsFixed(0);
      _accountIds[payment.method] = payment.accountId;
    }
  }

  @override
  void dispose() {
    for (final ctrl in _controllers.values) {
      ctrl.dispose();
    }
    super.dispose();
  }

  double _visibleTotalEntered(bool creditSalesEnabled) {
    return PaymentMethod.values
        .where((method) => method != PaymentMethod.credit || creditSalesEnabled)
        .fold(
          0,
          (sum, method) => sum + _parseAmount(_controllers[method]?.text ?? ''),
        );
  }

  void _applyPayments(List<AccountModel> accounts) {
    // Sab payments clear karo
    ref.read(cartProvider.notifier).clearPayments();
    final cart = ref.read(cartProvider);
    final creditSalesEnabled = isEntitledActionVisible(
      ref.read(featureEntitlementProvider('pos.credit_sales')).value,
    );
    final enteredAmounts = <PaymentMethod, double>{
      for (final method in PaymentMethod.values)
        method:
            method == PaymentMethod.credit && !creditSalesEnabled
                ? 0
                : _parseAmount(_controllers[method]?.text ?? ''),
    };
    final selectedMethods =
        PaymentMethod.values
            .where((method) => (enteredAmounts[method] ?? 0) > 0)
            .toList();

    if (selectedMethods.isEmpty) return;

    _normalizePaymentAmounts(enteredAmounts, selectedMethods, cart.total);
    for (final method in selectedMethods) {
      if (!PosPaymentAccountPolicy.requiresAccount(method)) continue;
      final accountId = _effectiveAccountId(method, accounts);
      if (accountId == null) return;
      _accountIds[method] = accountId;
    }

    // Naye payments set karo
    for (final method in PaymentMethod.values) {
      final amount = enteredAmounts[method] ?? 0;
      if (amount > 0) {
        ref
            .read(cartProvider.notifier)
            .setPayment(method, amount, accountId: _accountIds[method]);
      }
    }

    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartProvider);
    final accountsAsync = ref.watch(accountsProvider);
    final accounts = accountsAsync.value ?? const <AccountModel>[];
    final creditSalesEnabled = isEntitledActionVisible(
      ref.watch(featureEntitlementProvider('pos.credit_sales')).value,
    );
    final visibleTotalEntered = _visibleTotalEntered(creditSalesEnabled);
    final remaining = cart.total - visibleTotalEntered;
    final isComplete =
        visibleTotalEntered > 0 &&
        (visibleTotalEntered >= cart.total - 0.01 ||
            visibleTotalEntered.round() == cart.total.round()) &&
        _allEnteredPaymentsHaveAccounts(accounts);

    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        controller: widget.scrollController,
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
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
                border: Border.all(
                  color: AppColors.info.withValues(alpha: 0.2),
                ),
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
            ...PaymentMethod.values
                .where(
                  (method) =>
                      method != PaymentMethod.credit || creditSalesEnabled,
                )
                .map((method) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _PaymentMethodRow(
                      method: method,
                      controller: _controllers[method]!,
                      onChanged: () => setState(() {}),
                      accounts: PosPaymentAccountPolicy.compatibleAccounts(
                        method,
                        accounts,
                      ),
                      selectedAccountId: _effectiveAccountId(method, accounts),
                      onAccountChanged:
                          (value) =>
                              setState(() => _accountIds[method] = value),
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
                onPressed: isComplete ? () => _applyPayments(accounts) : null,
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
      ),
    );
  }

  String? _effectiveAccountId(
    PaymentMethod method,
    List<AccountModel> accounts,
  ) {
    if (!PosPaymentAccountPolicy.requiresAccount(method)) return null;
    final selected = _accountIds[method];
    if (selected != null &&
        accounts.any(
          (account) =>
              account.id == selected &&
              PosPaymentAccountPolicy.isCompatible(method, account),
        )) {
      return selected;
    }
    return PosPaymentAccountPolicy.suggestedAccount(method, accounts)?.id;
  }

  bool _allEnteredPaymentsHaveAccounts(List<AccountModel> accounts) {
    for (final method in PaymentMethod.values) {
      if (_parseAmount(_controllers[method]?.text ?? '') <= 0 ||
          !PosPaymentAccountPolicy.requiresAccount(method)) {
        continue;
      }
      if (_effectiveAccountId(method, accounts) == null) return false;
    }
    return true;
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
  final List<AccountModel> accounts;
  final String? selectedAccountId;
  final ValueChanged<String?> onAccountChanged;

  const _PaymentMethodRow({
    required this.method,
    required this.controller,
    required this.onChanged,
    required this.accounts,
    required this.selectedAccountId,
    required this.onAccountChanged,
  });

  @override
  Widget build(BuildContext context) {
    final color = _methodColor(method);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
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
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: color,
                      ),
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
                    borderSide: BorderSide(
                      color: color.withValues(alpha: 0.35),
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: color, width: 1.4),
                  ),
                ),
              ),
            ),
          ],
        ),
        if (PosPaymentAccountPolicy.requiresAccount(method)) ...[
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: selectedAccountId,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: '${method.label} receiving account',
              helperText:
                  accounts.isEmpty
                      ? 'Accounts screen mein compatible account banayein.'
                      : null,
            ),
            items:
                accounts
                    .map(
                      (account) => DropdownMenuItem(
                        value: account.id,
                        child: Text(
                          '${account.name} • Rs ${account.currentBalance.toStringAsFixed(0)}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
            onChanged: accounts.isEmpty ? null : onAccountChanged,
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
