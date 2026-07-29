import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobileshop_saas/core/constants/app_colors.dart';
import 'package:mobileshop_saas/features/accounts/data/models/account_models.dart';
import 'package:mobileshop_saas/features/accounts/presentation/providers/accounts_provider.dart';
import 'package:mobileshop_saas/features/mobile_services/data/models/mobile_service_models.dart';
import 'package:mobileshop_saas/features/mobile_services/domain/mobile_service_types.dart';
import 'package:mobileshop_saas/features/mobile_services/presentation/providers/mobile_services_provider.dart';

class MobileServicesScreen extends ConsumerWidget {
  const MobileServicesScreen({super.key});

  static const _historyLimit = 100;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final providersAsync = ref.watch(mobileServiceProvidersProvider);
    final rulesAsync = ref.watch(mobileServiceChargeRulesProvider);
    final accountsAsync = ref.watch(accountsProvider);
    final transactionsAsync = ref.watch(
      mobileServiceTransactionsProvider(_historyLimit),
    );
    final action = ref.watch(mobileServiceActionControllerProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            await ref
                .read(mobileServiceActionControllerProvider.notifier)
                .sync();
            ref
              ..invalidate(mobileServiceProvidersProvider)
              ..invalidate(mobileServiceChargeRulesProvider)
              ..invalidate(accountsProvider)
              ..invalidate(mobileServiceTransactionsProvider(_historyLimit));
          },
          child: providersAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error:
                (error, _) => _ErrorView(
                  message: error.toString(),
                  onRetry: () => ref.invalidate(mobileServiceProvidersProvider),
                ),
            data: (providers) {
              if (rulesAsync.isLoading || accountsAsync.isLoading) {
                return const Center(child: CircularProgressIndicator());
              }
              if (rulesAsync.hasError || accountsAsync.hasError) {
                return _ErrorView(
                  message: (rulesAsync.error ?? accountsAsync.error).toString(),
                  onRetry: () {
                    ref
                      ..invalidate(mobileServiceChargeRulesProvider)
                      ..invalidate(accountsProvider);
                  },
                );
              }

              return _MobileServicesContent(
                providers:
                    providers.where((provider) => provider.isActive).toList(),
                rules:
                    (rulesAsync.value ?? const [])
                        .where((rule) => rule.isActive)
                        .toList(),
                accounts: accountsAsync.value ?? const [],
                transactions: transactionsAsync.value ?? const [],
                historyLoading: transactionsAsync.isLoading,
                historyError: transactionsAsync.error,
                busy: action.isLoading,
              );
            },
          ),
        ),
      ),
    );
  }
}

class _MobileServicesContent extends StatelessWidget {
  final List<MobileServiceProviderModel> providers;
  final List<MobileServiceChargeRuleModel> rules;
  final List<AccountModel> accounts;
  final List<MobileServiceTransactionModel> transactions;
  final bool historyLoading;
  final Object? historyError;
  final bool busy;

  const _MobileServicesContent({
    required this.providers,
    required this.rules,
    required this.accounts,
    required this.transactions,
    required this.historyLoading,
    required this.historyError,
    required this.busy,
  });

  @override
  Widget build(BuildContext context) {
    final cashAccounts =
        accounts
            .where(
              (account) => account.type == AccountType.cash && account.isActive,
            )
            .toList();

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 980;
        final form = _TransactionForm(
          providers: providers,
          rules: rules,
          accounts: accounts,
          cashAccounts: cashAccounts,
          busy: busy,
        );
        final history = _TransactionHistory(
          providers: providers,
          transactions: transactions,
          loading: historyLoading,
          error: historyError,
          busy: busy,
        );

        return ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.all(isWide ? 16 : 12),
          children: [
            _Header(
              syncing: busy,
              onSettings: () => context.push('/mobile-services/settings'),
            ),
            const SizedBox(height: 12),
            if (providers.isEmpty)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.settings_outlined),
                  title: const Text('Configure Easypaisa or JazzCash'),
                  subtitle: const Text(
                    'Link a wallet and create Send/Receive charge rules.',
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => context.push('/mobile-services/settings'),
                ),
              )
            else if (cashAccounts.isEmpty)
              const Card(
                child: ListTile(
                  leading: Icon(Icons.warning_amber_rounded),
                  title: Text('Cash account required'),
                  subtitle: Text(
                    'Create an active Cash account before recording services.',
                  ),
                ),
              ),
            const SizedBox(height: 4),
            if (isWide)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 5, child: form),
                  const SizedBox(width: 12),
                  Expanded(flex: 6, child: history),
                ],
              )
            else ...[
              form,
              const SizedBox(height: 12),
              history,
            ],
          ],
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  final bool syncing;
  final VoidCallback onSettings;

  const _Header({required this.syncing, required this.onSettings});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Mobile Services',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
              ),
              SizedBox(height: 4),
              Text('Easypaisa and JazzCash Send/Receive'),
            ],
          ),
        ),
        if (syncing)
          const Padding(
            padding: EdgeInsets.only(right: 12),
            child: SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        OutlinedButton.icon(
          onPressed: onSettings,
          icon: const Icon(Icons.settings_outlined),
          label: const Text('Settings'),
        ),
      ],
    );
  }
}

class _TransactionForm extends ConsumerStatefulWidget {
  final List<MobileServiceProviderModel> providers;
  final List<MobileServiceChargeRuleModel> rules;
  final List<AccountModel> accounts;
  final List<AccountModel> cashAccounts;
  final bool busy;

  const _TransactionForm({
    required this.providers,
    required this.rules,
    required this.accounts,
    required this.cashAccounts,
    required this.busy,
  });

  @override
  ConsumerState<_TransactionForm> createState() => _TransactionFormState();
}

class _TransactionFormState extends ConsumerState<_TransactionForm> {
  final _amountController = TextEditingController();
  final _feeController = TextEditingController();
  final _phoneController = TextEditingController();
  final _referenceController = TextEditingController();
  final _descriptionController = TextEditingController();
  String? _cashAccountId;

  @override
  void initState() {
    super.initState();
    _selectDefaults();
  }

  @override
  void didUpdateWidget(covariant _TransactionForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    _selectDefaults();
  }

  void _selectDefaults() {
    if (_cashAccountId == null && widget.cashAccounts.isNotEmpty) {
      _cashAccountId =
          widget.cashAccounts
              .where((account) => account.isDefault)
              .firstOrNull
              ?.id ??
          widget.cashAccounts.first.id;
    }
    final form = ref.read(mobileServiceFormControllerProvider);
    if (form.providerId == null && widget.providers.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref
            .read(mobileServiceFormControllerProvider.notifier)
            .selectProvider(widget.providers.first.id);
      });
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    _feeController.dispose();
    _phoneController.dispose();
    _referenceController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final form = ref.watch(mobileServiceFormControllerProvider);
    final formController = ref.read(
      mobileServiceFormControllerProvider.notifier,
    );
    final selectedProvider =
        widget.providers
            .where((provider) => provider.id == form.providerId)
            .firstOrNull;
    final selectedWallet =
        selectedProvider == null
            ? null
            : widget.accounts
                .where(
                  (account) => account.id == selectedProvider.providerAccountId,
                )
                .firstOrNull;
    final selectedRule =
        widget.rules
            .where(
              (rule) =>
                  rule.providerId == form.providerId &&
                  rule.operation == form.operation,
            )
            .firstOrNull;
    final isManual =
        selectedRule?.calculationMethod ==
        ServiceChargeCalculationMethod.manual;
    final selectedCashAccount =
        widget.accounts
            .where((account) => account.id == _cashAccountId)
            .firstOrNull;
    final preview = form.preview;
    final balanceError =
        preview == null
            ? null
            : form.operation == MobileServiceOperation.send &&
                selectedWallet != null &&
                selectedWallet.currentBalance + 0.01 < preview.serviceAmount
            ? 'You cannot send this amount. ${selectedWallet.name} balance is '
                'Rs ${_money(selectedWallet.currentBalance)}, but '
                'Rs ${_money(preview.serviceAmount)} is required.'
            : form.operation == MobileServiceOperation.receive &&
                selectedCashAccount != null &&
                selectedCashAccount.currentBalance + 0.01 <
                    preview.customerCashAmount
            ? 'You cannot pay this customer. ${selectedCashAccount.name} '
                'balance is Rs ${_money(selectedCashAccount.currentBalance)}, '
                'but Rs ${_money(preview.customerCashAmount)} is required.'
            : null;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'New transaction',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 16),
            SegmentedButton<MobileServiceOperation>(
              segments: const [
                ButtonSegment(
                  value: MobileServiceOperation.send,
                  icon: Icon(Icons.north_east_rounded),
                  label: Text('Send'),
                ),
                ButtonSegment(
                  value: MobileServiceOperation.receive,
                  icon: Icon(Icons.south_west_rounded),
                  label: Text('Receive'),
                ),
              ],
              selected: {form.operation},
              onSelectionChanged:
                  widget.busy
                      ? null
                      : (value) {
                        _feeController.clear();
                        formController.selectOperation(value.first);
                      },
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              initialValue:
                  widget.providers.any(
                        (provider) => provider.id == form.providerId,
                      )
                      ? form.providerId
                      : null,
              decoration: const InputDecoration(labelText: 'Provider'),
              items: [
                for (final provider in widget.providers)
                  DropdownMenuItem(
                    value: provider.id,
                    child: Text(provider.name),
                  ),
              ],
              onChanged:
                  widget.busy
                      ? null
                      : (value) {
                        _feeController.clear();
                        formController.selectProvider(value);
                      },
            ),
            const SizedBox(height: 12),
            _LinkedWalletCard(
              provider: selectedProvider,
              wallet: selectedWallet,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _cashAccountId,
              decoration: const InputDecoration(
                labelText: 'Customer cash account',
                helperText:
                    'Cash received from or paid to the customer is recorded here.',
              ),
              items: [
                for (final account in widget.cashAccounts)
                  DropdownMenuItem(
                    value: account.id,
                    child: Text(
                      '${account.name} • Rs ${_money(account.currentBalance)}',
                    ),
                  ),
              ],
              onChanged:
                  widget.busy
                      ? null
                      : (value) => setState(() => _cashAccountId = value),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _amountController,
              enabled: !widget.busy,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText:
                    form.operation == MobileServiceOperation.send
                        ? 'Amount to send'
                        : 'Amount received in wallet',
                prefixText: 'Rs ',
              ),
              onChanged:
                  (value) =>
                      formController.enterAmount(double.tryParse(value.trim())),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _feeController,
              enabled: !widget.busy,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: isManual ? 'Service fee' : 'Fee override (optional)',
                prefixText: 'Rs ',
                helperText:
                    isManual
                        ? 'Required by manual rule'
                        : form.preview == null
                        ? null
                        : 'Calculated: Rs ${_money(form.preview!.calculatedFee)}',
              ),
              onChanged:
                  (value) => formController.overrideFee(
                    value.trim().isEmpty ? null : double.tryParse(value.trim()),
                  ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _phoneController,
              enabled: !widget.busy,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Customer phone (optional)',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _referenceController,
              enabled: !widget.busy,
              decoration: const InputDecoration(
                labelText: 'Reference number (optional)',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _descriptionController,
              enabled: !widget.busy,
              decoration: const InputDecoration(labelText: 'Note (optional)'),
            ),
            if (form.validationMessage != null) ...[
              const SizedBox(height: 12),
              Text(
                form.validationMessage!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            if (balanceError != null) ...[
              const SizedBox(height: 12),
              Text(
                balanceError,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            if (form.preview != null && selectedProvider != null) ...[
              const SizedBox(height: 16),
              _PreviewCard(
                preview: form.preview!,
                provider: selectedProvider,
                cashAccount: selectedCashAccount,
                walletAccount: selectedWallet,
              ),
            ],
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed:
                    widget.busy ||
                            !form.canSubmit ||
                            _cashAccountId == null ||
                            selectedWallet == null ||
                            !selectedWallet.isActive ||
                            balanceError != null
                        ? null
                        : () => _confirmAndSubmit(context),
                icon: const Icon(Icons.check_circle_outline_rounded),
                label: Text(widget.busy ? 'Saving...' : 'Review & confirm'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmAndSubmit(BuildContext context) async {
    final form = ref.read(mobileServiceFormControllerProvider);
    final preview = form.preview;
    if (preview == null || _cashAccountId == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: const Text('Confirm transaction'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _ConfirmLine('Service amount', preview.serviceAmount),
                _ConfirmLine('Service fee', preview.chargedFee),
                _ConfirmLine(
                  form.operation == MobileServiceOperation.send
                      ? 'Customer pays'
                      : 'Customer receives',
                  preview.customerCashAmount,
                ),
                _ConfirmLine('Profit', preview.profitAmount),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Back'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Confirm'),
              ),
            ],
          ),
    );
    if (confirmed != true || !context.mounted) return;

    final success = await ref
        .read(mobileServiceActionControllerProvider.notifier)
        .submit(
          cashAccountId: _cashAccountId!,
          phoneNumber: _phoneController.text,
          referenceNumber: _referenceController.text,
          description: _descriptionController.text,
        );
    if (!context.mounted) return;

    final result = ref.read(mobileServiceActionControllerProvider);
    final message =
        success
            ? result.value == MobileServiceSubmissionResult.queued
                ? 'Saved offline. It will sync automatically.'
                : 'Transaction completed.'
            : result.error?.toString() ?? 'Transaction failed.';
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
    if (success) {
      _amountController.clear();
      _feeController.clear();
      _phoneController.clear();
      _referenceController.clear();
      _descriptionController.clear();
    }
  }
}

class _LinkedWalletCard extends StatelessWidget {
  final MobileServiceProviderModel? provider;
  final AccountModel? wallet;

  const _LinkedWalletCard({required this.provider, required this.wallet});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    if (provider == null) {
      return const SizedBox.shrink();
    }
    final available = wallet != null && wallet!.isActive;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color:
            available
                ? colors.primaryContainer.withValues(alpha: 0.45)
                : colors.errorContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(
            available
                ? Icons.account_balance_wallet_outlined
                : Icons.warning_amber_rounded,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  available ? 'Linked wallet' : 'Linked wallet unavailable',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  available
                      ? '${wallet!.name} • Rs ${_money(wallet!.currentBalance)}'
                      : '${provider!.name} ko Settings mein an active mobile wallet se link karein.',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewCard extends StatelessWidget {
  final MobileServiceTransactionPreview preview;
  final MobileServiceProviderModel provider;
  final AccountModel? cashAccount;
  final AccountModel? walletAccount;

  const _PreviewCard({
    required this.preview,
    required this.provider,
    required this.cashAccount,
    required this.walletAccount,
  });

  @override
  Widget build(BuildContext context) {
    final isSend = preview.operation == MobileServiceOperation.send;
    final cashAfter =
        cashAccount == null
            ? null
            : cashAccount!.currentBalance +
                (isSend
                    ? preview.customerCashAmount
                    : -preview.customerCashAmount);
    final walletAfter =
        walletAccount == null
            ? null
            : walletAccount!.currentBalance +
                (isSend ? -preview.serviceAmount : preview.serviceAmount);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer.withAlpha(90),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            _PreviewLine('Service amount', preview.serviceAmount),
            _PreviewLine('Fee / profit', preview.chargedFee),
            _PreviewLine(
              isSend ? 'Customer pays' : 'Customer receives',
              preview.customerCashAmount,
              strong: true,
            ),
            const Divider(),
            _BalanceEffect(
              label: cashAccount?.name ?? 'Cash',
              before: cashAccount?.currentBalance,
              after: cashAfter,
            ),
            _BalanceEffect(
              label: walletAccount?.name ?? '${provider.name} Wallet',
              before: walletAccount?.currentBalance,
              after: walletAfter,
            ),
          ],
        ),
      ),
    );
  }
}

class _PreviewLine extends StatelessWidget {
  final String label;
  final double value;
  final bool strong;

  const _PreviewLine(this.label, this.value, {this.strong = false});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: [
        Expanded(child: Text(label)),
        Text(
          'Rs ${_money(value)}',
          style: TextStyle(fontWeight: strong ? FontWeight.w800 : null),
        ),
      ],
    ),
  );
}

class _BalanceEffect extends StatelessWidget {
  final String label;
  final double? before;
  final double? after;

  const _BalanceEffect({
    required this.label,
    required this.before,
    required this.after,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: [
        Expanded(child: Text(label)),
        Text(
          before == null || after == null
              ? 'Balance unavailable'
              : 'Rs ${_money(before!)} → Rs ${_money(after!)}',
        ),
      ],
    ),
  );
}

class _ConfirmLine extends StatelessWidget {
  final String label;
  final double value;

  const _ConfirmLine(this.label, this.value);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        Expanded(child: Text(label)),
        Text(
          'Rs ${_money(value)}',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ],
    ),
  );
}

class _TransactionHistory extends ConsumerWidget {
  final List<MobileServiceProviderModel> providers;
  final List<MobileServiceTransactionModel> transactions;
  final bool loading;
  final Object? error;
  final bool busy;

  const _TransactionHistory({
    required this.providers,
    required this.transactions,
    required this.loading,
    required this.error,
    required this.busy,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Recent transactions',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                ),
                if (loading)
                  const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (error != null)
              Text(
                'History unavailable: $error',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              )
            else if (!loading && transactions.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 28),
                child: Center(child: Text('No mobile-service transactions.')),
              )
            else
              for (final transaction in transactions)
                _TransactionTile(
                  transaction: transaction,
                  providerName:
                      providers
                          .where(
                            (provider) => provider.id == transaction.providerId,
                          )
                          .firstOrNull
                          ?.name ??
                      'Provider',
                  busy: busy,
                ),
          ],
        ),
      ),
    );
  }
}

class _TransactionTile extends ConsumerWidget {
  final MobileServiceTransactionModel transaction;
  final String providerName;
  final bool busy;

  const _TransactionTile({
    required this.transaction,
    required this.providerName,
    required this.busy,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isSend = transaction.operation == MobileServiceOperation.send;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        child: Icon(
          isSend ? Icons.north_east_rounded : Icons.south_west_rounded,
        ),
      ),
      title: Text('$providerName • ${transaction.operation.label}'),
      subtitle: Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          Text(_dateTime(transaction.transactionAt)),
          _StatusChip(status: transaction.status),
          Text('Profit Rs ${_money(transaction.profitAmount)}'),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Rs ${_money(transaction.serviceAmount)}',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          if (transaction.status == MobileServiceTransactionStatus.completed)
            PopupMenuButton<String>(
              enabled: !busy,
              onSelected: (_) => _showVoidDialog(context, ref, transaction.id),
              itemBuilder:
                  (_) => const [
                    PopupMenuItem(value: 'void', child: Text('Void')),
                  ],
            ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final MobileServiceTransactionStatus status;

  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      MobileServiceTransactionStatus.completed => ('Completed', Colors.green),
      MobileServiceTransactionStatus.pendingSync => (
        'Pending sync',
        Colors.orange,
      ),
      MobileServiceTransactionStatus.voided => ('Voided', Colors.red),
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        child: Text(label, style: TextStyle(color: color, fontSize: 12)),
      ),
    );
  }
}

Future<void> _showVoidDialog(
  BuildContext context,
  WidgetRef ref,
  String transactionId,
) async {
  final reason = TextEditingController();
  final confirmed = await showDialog<bool>(
    context: context,
    builder:
        (dialogContext) => AlertDialog(
          title: const Text('Void transaction'),
          content: TextField(
            controller: reason,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Reason',
              helperText: 'Cash, wallet and profit will be reversed.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Void'),
            ),
          ],
        ),
  );
  if (confirmed != true || !context.mounted) {
    reason.dispose();
    return;
  }

  final success = await ref
      .read(mobileServiceActionControllerProvider.notifier)
      .voidTransaction(transactionId: transactionId, reason: reason.text);
  reason.dispose();
  if (!context.mounted) return;
  final state = ref.read(mobileServiceActionControllerProvider);
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        success
            ? 'Transaction voided.'
            : state.error?.toString() ?? 'Void failed.',
      ),
    ),
  );
}

String _money(double value) => value.toStringAsFixed(2);

String _dateTime(DateTime value) {
  final local = value.toLocal();
  String two(int number) => number.toString().padLeft(2, '0');
  return '${two(local.day)}/${two(local.month)}/${local.year} '
      '${two(local.hour)}:${two(local.minute)}';
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) => ListView(
    physics: const AlwaysScrollableScrollPhysics(),
    padding: const EdgeInsets.all(24),
    children: [
      const SizedBox(height: 100),
      const Icon(Icons.error_outline_rounded, size: 48),
      const SizedBox(height: 12),
      Text(message, textAlign: TextAlign.center),
      const SizedBox(height: 12),
      Center(
        child: OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
      ),
    ],
  );
}
