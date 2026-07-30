import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/utils/responsive.dart';
import '../../data/models/customer_model.dart';
import '../../data/models/sale_payment_model.dart';
import '../../domain/pos_payment_account_policy.dart';
import '../../../accounts/data/models/account_models.dart';
import '../../../accounts/presentation/providers/accounts_provider.dart';
import '../providers/pos_provider.dart';

class CustomersScreen extends ConsumerWidget {
  const CustomersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const _CustomersBody();
  }
}

class _CustomersBody extends ConsumerStatefulWidget {
  const _CustomersBody();

  @override
  ConsumerState<_CustomersBody> createState() => _CustomersBodyState();
}

class _CustomersBodyState extends ConsumerState<_CustomersBody> {
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final customers = ref.watch(customersProvider);
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      AppStrings.customersTitle,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: () => _showAddCustomerSheet(context),
                    icon: const Icon(Icons.person_add_rounded, size: 18),
                    label: const Text(AppStrings.customerAdd),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: TextFormField(
                controller: _searchCtrl,
                onChanged:
                    (value) =>
                        ref.read(customerListQueryProvider.notifier).state =
                            value,
                decoration: const InputDecoration(
                  hintText: AppStrings.customerSearchHint,
                  prefixIcon: Icon(Icons.search_rounded),
                ),
              ),
            ),
            Expanded(
              child: customers.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error:
                    (error, _) => Center(
                      child: Text(
                        error.toString(),
                        style: const TextStyle(color: AppColors.error),
                      ),
                    ),
                data: (items) {
                  if (items.isEmpty) {
                    return const Center(
                      child: Text(
                        AppStrings.customersEmpty,
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                    );
                  }
                  return RefreshIndicator(
                    onRefresh: () async => ref.invalidate(customersProvider),
                    child: ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: items.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final customer = items[index];
                        return _CustomerTile(customer: customer);
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddCustomerSheet(BuildContext context) {
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
                constraints: const BoxConstraints(maxWidth: 480),
                child: const _CustomerFormSheet(showHandle: false),
              ),
            ),
      );
      return;
    }

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _CustomerFormSheet(),
    );
  }
}

class _CustomerTile extends StatelessWidget {
  final CustomerModel customer;

  const _CustomerTile({required this.customer});

  @override
  Widget build(BuildContext context) {
    final due = customer.outstandingBalance;

    debugPrint("custome data is: ${customer.toJson()}");
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: AppColors.primary.withValues(alpha: 0.1),
          child: Text(
            customer.fullName.isEmpty
                ? AppStrings.customerUnknownInitial
                : customer.fullName[0].toUpperCase(),
            style: const TextStyle(
              color: AppColors.primary,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        title: Text(
          customer.fullName,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          [
            if (customer.phone != null) customer.phone,
            if (customer.email != null) customer.email,
            AppStrings.customerDue(due),
          ].join(AppStrings.customerDetailSeparator),
        ),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () => context.push('/customers/detail', extra: customer),
      ),
    );
  }
}

class CustomerDetailScreen extends ConsumerWidget {
  final CustomerModel customer;

  const CustomerDetailScreen({super.key, required this.customer});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashboard = ref.watch(customerDashboardProvider(customer.id!));
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(customer.fullName),
        actions: [
          IconButton(
            onPressed:
                () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  showDragHandle: true,
                  builder: (_) => _CreditLimitSheet(customerId: customer.id!),
                ),
            icon: const Icon(Icons.account_balance_wallet_rounded),
            tooltip: AppStrings.customerCreditLimitTooltip,
          ),
        ],
      ),
      body: dashboard.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error:
            (error, _) => Center(
              child: Text(
                error.toString(),
                style: const TextStyle(color: AppColors.error),
              ),
            ),
        data: (data) {
          final limit = data.customer.creditLimit;
          return RefreshIndicator(
            onRefresh:
                () async =>
                    ref.invalidate(customerDashboardProvider(customer.id!)),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _MetricCard(
                      label: AppStrings.customerLifetimeValue,
                      value: AppStrings.customerMoney(data.lifetimeValue),
                      icon: Icons.trending_up_rounded,
                    ),
                    _MetricCard(
                      label: AppStrings.customerOutstanding,
                      value: AppStrings.customerMoney(data.outstandingDues),
                      icon: Icons.payments_rounded,
                      color:
                          data.outstandingDues > 0
                              ? AppColors.warning
                              : AppColors.success,
                    ),
                    _MetricCard(
                      label: AppStrings.customerCreditLimit,
                      value:
                          limit == null
                              ? AppStrings.customerCreditLimitNotSet
                              : AppStrings.customerMoney(limit),
                      icon: Icons.speed_rounded,
                    ),
                    _MetricCard(
                      label: AppStrings.customerActiveRepairs,
                      value: data.activeRepairTickets.toString(),
                      icon: Icons.build_rounded,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.info.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: AppColors.info.withValues(alpha: 0.2),
                    ),
                  ),
                  child: const Text(
                    AppStrings.customerCreditExplanation,
                    style: TextStyle(
                      color: AppColors.info,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed:
                        data.outstandingDues <= 0
                            ? null
                            : () => showModalBottomSheet<void>(
                              context: context,
                              isScrollControlled: true,
                              showDragHandle: true,
                              builder:
                                  (_) => _SettleDuesSheet(
                                    customerId: customer.id!,
                                    outstanding: data.outstandingDues,
                                  ),
                            ),
                    icon: const Icon(Icons.task_alt_rounded, size: 18),
                    label: const Text(AppStrings.customerSettleDues),
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  AppStrings.customerPurchaseHistory,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                if (data.purchases.isEmpty)
                  const Text(
                    AppStrings.customerNoPurchases,
                    style: TextStyle(color: AppColors.textSecondary),
                  )
                else
                  ...data.purchases.map(
                    (sale) => Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        title: Text(AppStrings.customerInvoice(sale.id ?? '')),
                        subtitle: Text(
                          sale.createdAt
                                  ?.toLocal()
                                  .toString()
                                  .split('.')
                                  .first ??
                              '',
                        ),
                        trailing: Text(
                          AppStrings.customerMoney(sale.total),
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 20),
                const Text(
                  AppStrings.customerSettlements,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                if (data.settlements.isEmpty)
                  const Text(
                    AppStrings.customerNoSettlements,
                    style: TextStyle(color: AppColors.textSecondary),
                  )
                else
                  ...data.settlements.map(
                    (settlement) => Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: const Icon(Icons.receipt_long_rounded),
                        title: Text(
                          AppStrings.customerMoney(settlement.amount),
                        ),
                        subtitle: Text(
                          AppStrings.customerSettlementDetails(
                            settlement.method,
                            settlement.createdAt
                                .toLocal()
                                .toString()
                                .split('.')
                                .first,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _MetricCard({
    required this.label,
    required this.value,
    required this.icon,
    this.color = AppColors.primary,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 190,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: color),
              const SizedBox(height: 10),
              Text(
                label,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CustomerFormSheet extends ConsumerStatefulWidget {
  final bool showHandle;

  const _CustomerFormSheet({this.showHandle = true});

  @override
  ConsumerState<_CustomerFormSheet> createState() => _CustomerFormSheetState();
}

class _CustomerFormSheetState extends ConsumerState<_CustomerFormSheet> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _notes = TextEditingController();
  final _creditLimit = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _email.dispose();
    _notes.dispose();
    _creditLimit.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(customerControllerProvider);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        widget.showHandle ? 0 : 16,
        16,
        MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      AppStrings.customerAddTitle,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                  ),
                  if (!widget.showHandle)
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                      tooltip: AppStrings.customerClose,
                    ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(
                  labelText: AppStrings.customerFullNameLabel,
                ),
                validator: (value) {
                  final name = value?.trim() ?? '';

                  if (name.isEmpty) {
                    return "Full name required hai.";
                  }

                  if (name.length < 4) {
                    return "Full name kam az kam 4 characters ka ho";
                  }

                  return null;
                },
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Phone'),
                validator: (value) {
                  final phone = value?.trim() ?? '';
                  if (phone.isEmpty) return 'Phone required ha.';

                  final normalized = phone.replaceAll(RegExp(r'[\s\-()]'), '');

                  if (!RegExp(r'^\+?\d{10,15}$').hasMatch(normalized)) {
                    return 'Valid phone number enter karein.';
                  }

                  return null;
                },
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Email (optional)',
                ),
                validator: (value) {
                  final email = value?.trim() ?? '';
                  if (email.isEmpty) return null;

                  final validEmail = RegExp(
                    r'^[^@\s]+@[^@\s]+\.[^@\s]+$',
                  ).hasMatch(email);

                  if (!validEmail) {
                    return 'Valid email address enter karein.';
                  }

                  return null;
                },
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _creditLimit,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: AppStrings.customerCreditLimitLabel,
                  prefixText: AppStrings.customerCreditLimitPrefix,
                  helperText: AppStrings.customerCreditLimitHelper,
                ),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _notes,
                minLines: 2,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Notes (optional)',
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: state.isLoading ? null : _submit,
                  child:
                      state.isLoading
                          ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                          : const Text(AppStrings.customerSave),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();

    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    final customer = await ref
        .read(customerControllerProvider.notifier)
        .addCustomer(
          fullName: _name.text.trim(),
          phone: _nullIfEmpty(_phone.text),
          email: _nullIfEmpty(_email.text),
          notes: _nullIfEmpty(_notes.text),
          creditLimit:
              _creditLimit.text.trim().isEmpty
                  ? null
                  : double.parse(_creditLimit.text.trim()),
        );

    if (!mounted) return;
    if (customer == null) {
      final error = ref.read(customerControllerProvider).error;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error?.toString() ?? AppStrings.customerSaveFailed),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }
    Navigator.pop(context);
  }

  String? _nullIfEmpty(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}

class _CreditLimitSheet extends ConsumerStatefulWidget {
  final String customerId;

  const _CreditLimitSheet({required this.customerId});

  @override
  ConsumerState<_CreditLimitSheet> createState() => _CreditLimitSheetState();
}

class _CreditLimitSheetState extends ConsumerState<_CreditLimitSheet> {
  final _limit = TextEditingController();

  @override
  void dispose() {
    _limit.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(customerControllerProvider);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            AppStrings.customerCreditLimitTitle,
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _limit,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: AppStrings.customerLimitLabel,
              prefixText: AppStrings.customerCreditLimitPrefix,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: state.isLoading ? null : () => _save(clear: true),
                  child: const Text(AppStrings.customerClear),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: state.isLoading ? null : () => _save(),
                  child: const Text(AppStrings.customerSaveAction),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _save({bool clear = false}) async {
    final customer = await ref
        .read(customerControllerProvider.notifier)
        .updateCreditLimit(
          customerId: widget.customerId,
          creditLimit: clear ? null : double.tryParse(_limit.text.trim()),
          clearCreditLimit: clear,
        );
    if (!mounted) return;
    if (customer == null) {
      final error = ref.read(customerControllerProvider).error;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error?.toString() ?? AppStrings.customerCreditLimitSaveFailed,
          ),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }
    Navigator.pop(context);
  }
}

class _SettleDuesSheet extends ConsumerStatefulWidget {
  final String customerId;
  final double outstanding;

  const _SettleDuesSheet({required this.customerId, required this.outstanding});

  @override
  ConsumerState<_SettleDuesSheet> createState() => _SettleDuesSheetState();
}

class _SettleDuesSheetState extends ConsumerState<_SettleDuesSheet> {
  final _amount = TextEditingController();
  final _notes = TextEditingController();
  String _method = 'cash';
  String? _accountId;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _amount.text = widget.outstanding.toStringAsFixed(0);
  }

  @override
  void dispose() {
    _amount.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(customerSettlementControllerProvider);
    final isSubmitting = _submitting || state.isLoading;
    final accounts =
        ref.watch(accountsProvider).value ?? const <AccountModel>[];
    final paymentMethod = PaymentMethodX.fromCode(_method);
    final compatibleAccounts = PosPaymentAccountPolicy.compatibleAccounts(
      paymentMethod,
      accounts,
    );
    final effectiveAccountId =
        _accountId ??
        PosPaymentAccountPolicy.suggestedAccount(
          paymentMethod,
          compatibleAccounts,
        )?.id;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            AppStrings.customerSettleDues,
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _amount,
            enabled: !isSubmitting,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: AppStrings.customerSettlementAmountLabel,
              prefixText: AppStrings.customerCreditLimitPrefix,
            ),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: _method,
            items: const [
              DropdownMenuItem(
                value: 'cash',
                child: Text(AppStrings.paymentCash),
              ),
              DropdownMenuItem(
                value: 'easypaisa',
                child: Text(AppStrings.paymentEasypaisa),
              ),
              DropdownMenuItem(
                value: 'jazzcash',
                child: Text(AppStrings.paymentJazzcash),
              ),
              DropdownMenuItem(
                value: 'card',
                child: Text(AppStrings.paymentCard),
              ),
            ],
            onChanged:
                isSubmitting
                    ? null
                    : (value) => setState(() {
                      _method = value ?? 'cash';
                      _accountId = null;
                    }),
            decoration: const InputDecoration(
              labelText: AppStrings.customerSettlementMethodLabel,
            ),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: effectiveAccountId,
            isExpanded: true,
            items:
                compatibleAccounts
                    .map(
                      (account) => DropdownMenuItem(
                        value: account.id,
                        child: Text(
                          AppStrings.customerAccountSummary(
                            account.name,
                            account.currentBalance,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
            onChanged:
                isSubmitting || compatibleAccounts.isEmpty
                    ? null
                    : (value) => setState(() => _accountId = value),
            decoration: InputDecoration(
              labelText: AppStrings.customerReceivingAccountLabel,
              helperText:
                  compatibleAccounts.isEmpty
                      ? AppStrings.customerCompatibleAccountRequired
                      : null,
            ),
          ),
          const SizedBox(height: 10),
          TextFormField(
            controller: _notes,
            enabled: !isSubmitting,
            decoration: const InputDecoration(
              labelText: AppStrings.customerNotesLabel,
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed:
                  isSubmitting || effectiveAccountId == null
                      ? null
                      : () => _submit(effectiveAccountId),
              child:
                  isSubmitting
                      ? const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          ),
                          SizedBox(width: 10),
                          Text(AppStrings.customerRecordingSettlement),
                        ],
                      )
                      : const Text(AppStrings.customerRecordSettlement),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _submit(String accountId) async {
    final amount = double.tryParse(_amount.text.trim()) ?? 0;
    if (amount <= 0) {
      _showError(AppStrings.customerSettlementAmountInvalid);
      return;
    }
    if (amount > widget.outstanding + 0.01) {
      _showError(AppStrings.customerSettlementExceedsDues);
      return;
    }

    setState(() => _submitting = true);
    try {
      final ok = await ref
          .read(customerSettlementControllerProvider.notifier)
          .settle(
            customerId: widget.customerId,
            amount: amount,
            method: _method,
            accountId: accountId,
            notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
          );
      if (!mounted) return;
      if (!ok) {
        final error = ref.read(customerSettlementControllerProvider).error;
        _showError(_settlementErrorMessage(error));
        return;
      }

      final messenger = ScaffoldMessenger.of(context);
      Navigator.pop(context);
      messenger.showSnackBar(
        const SnackBar(content: Text(AppStrings.customerSettlementSuccess)),
      );
    } catch (error) {
      if (mounted) {
        _showError(_settlementErrorMessage(error));
      }
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppColors.error),
    );
  }
}

String _settlementErrorMessage(Object? error) {
  if (error == null) return AppStrings.customerSettlementSaveFailed;

  final message = error.toString();
  final normalized = message.toLowerCase();
  if (normalized.contains('23503') ||
      normalized.contains('ledger_transaction_id_fkey')) {
    return AppStrings.customerSettlementLedgerFailed;
  }
  if (normalized.contains('permission') ||
      normalized.contains('42501') ||
      normalized.contains('not authorized')) {
    return AppStrings.customerSettlementPermissionDenied;
  }
  if (normalized.contains('current dues') ||
      normalized.contains('exceeds current customer dues')) {
    return AppStrings.customerSettlementExceedsDues;
  }
  if (normalized.contains('account') &&
      (normalized.contains('compatible') || normalized.contains('not found'))) {
    return AppStrings.customerSettlementAccountInvalid;
  }
  if (normalized.contains('timeout') ||
      normalized.contains('socketexception') ||
      normalized.contains('failed host lookup') ||
      normalized.contains('network') ||
      normalized.contains('connection')) {
    return AppStrings.customerSettlementOffline;
  }

  return AppStrings.customerSettlementRetry;
}
