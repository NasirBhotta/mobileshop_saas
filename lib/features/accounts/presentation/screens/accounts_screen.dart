import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobileshop_saas/core/constants/app_colors.dart';
import 'package:mobileshop_saas/core/entitlements/entitlement_provider.dart';
import 'package:mobileshop_saas/features/accounts/data/models/account_models.dart';
import 'package:mobileshop_saas/features/accounts/presentation/providers/accounts_provider.dart';

class AccountsScreen extends ConsumerWidget {
  const AccountsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accountsAsync = ref.watch(accountsProvider);
    final transactionsAsync = ref.watch(accountTransactionsProvider);
    final syncState = ref.watch(accountsSyncControllerProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            await ref.read(accountsSyncControllerProvider.notifier).sync();
          },
          child: accountsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error:
                (error, _) => _AccountsErrorView(
                  message: error.toString(),
                  onRetry: () => ref.invalidate(accountsProvider),
                ),
            data: (accounts) {
              return transactionsAsync.when(
                loading:
                    () => _AccountsContent(
                      accounts: accounts,
                      transactions: const [],
                      syncing: syncState.isLoading,
                      loadingTransactions: true,
                      onSync:
                          () =>
                              ref
                                  .read(accountsSyncControllerProvider.notifier)
                                  .sync(),
                    ),
                error:
                    (_, _) => _AccountsContent(
                      accounts: accounts,
                      transactions: const [],
                      syncing: syncState.isLoading,
                      onSync:
                          () =>
                              ref
                                  .read(accountsSyncControllerProvider.notifier)
                                  .sync(),
                    ),
                data:
                    (transactions) => _AccountsContent(
                      accounts: accounts,
                      transactions: transactions,
                      syncing: syncState.isLoading,
                      onSync:
                          () =>
                              ref
                                  .read(accountsSyncControllerProvider.notifier)
                                  .sync(),
                    ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _AccountsContent extends ConsumerWidget {
  final List<AccountModel> accounts;
  final List<AccountTransactionModel> transactions;
  final bool syncing;
  final bool loadingTransactions;
  final VoidCallback onSync;

  const _AccountsContent({
    required this.accounts,
    required this.transactions,
    required this.syncing,
    required this.onSync,
    this.loadingTransactions = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final totalBalance = accounts.fold<double>(
      0,
      (sum, account) => sum + account.currentBalance,
    );
    final transfersEnabled =
        ref.watch(featureEntitlementProvider('accounts.transfers')).value !=
        false;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 920;
        final content = <Widget>[
          _AccountsHeader(
            syncing: syncing,
            onSync: onSync,
            onAddAccount: () => _showAccountDialog(context, ref),
            onAddEntry:
                accounts.isEmpty
                    ? null
                    : () => _showEntryDialog(context, ref, accounts),
            onTransfer:
                accounts.length < 2 || !transfersEnabled
                    ? null
                    : () => _showTransferDialog(context, ref, accounts),
          ),
          const SizedBox(height: 12),
          _BalanceSummary(totalBalance: totalBalance, accounts: accounts),
          const SizedBox(height: 12),
        ];

        if (isWide) {
          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: [
              ...content,
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 5, child: _AccountsPanel(accounts: accounts)),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 6,
                    child: _TransactionsPanel(
                      transactions: transactions,
                      loading: loadingTransactions,
                    ),
                  ),
                ],
              ),
            ],
          );
        }

        return ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(12),
          children: [
            ...content,
            _AccountsPanel(accounts: accounts),
            const SizedBox(height: 12),
            _TransactionsPanel(
              transactions: transactions,
              loading: loadingTransactions,
            ),
          ],
        );
      },
    );
  }
}

class _AccountsHeader extends StatelessWidget {
  final bool syncing;
  final VoidCallback onSync;
  final VoidCallback onAddAccount;
  final VoidCallback? onAddEntry;
  final VoidCallback? onTransfer;

  const _AccountsHeader({
    required this.syncing,
    required this.onSync,
    required this.onAddAccount,
    required this.onAddEntry,
    required this.onTransfer,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 520;
        final syncButton = IconButton(
          tooltip: 'Sync',
          onPressed: syncing ? null : onSync,
          icon:
              syncing
                  ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                  : const Icon(Icons.sync_rounded),
        );
        final actions = [
          if (onTransfer != null)
            OutlinedButton.icon(
              onPressed: onTransfer,
              icon: const Icon(Icons.swap_horiz_rounded, size: 18),
              label: const Text('Transfer'),
            ),
          OutlinedButton.icon(
            onPressed: onAddAccount,
            icon: const Icon(Icons.account_balance_wallet_rounded, size: 18),
            label: const Text('Account'),
          ),
          FilledButton.icon(
            onPressed: onAddEntry,
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Entry'),
          ),
        ];

        if (compact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [const Expanded(child: _AccountsTitle()), syncButton],
              ),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: actions),
            ],
          );
        }

        return Row(
          children: [
            const Expanded(child: _AccountsTitle()),
            syncButton,
            const SizedBox(width: 8),
            ...actions.expand((button) => [button, const SizedBox(width: 8)]),
          ],
        );
      },
    );
  }
}

class _AccountsTitle extends StatelessWidget {
  const _AccountsTitle();

  @override
  Widget build(BuildContext context) {
    return const Text(
      'Accounts',
      style: TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.bold,
        color: AppColors.textPrimary,
      ),
    );
  }
}

class _BalanceSummary extends StatelessWidget {
  final double totalBalance;
  final List<AccountModel> accounts;

  const _BalanceSummary({required this.totalBalance, required this.accounts});

  @override
  Widget build(BuildContext context) {
    final cash = _sumByType(AccountType.cash);
    final bank = _sumByType(AccountType.bank);
    final wallets = accounts
        .where((account) => account.type == AccountType.mobileWallet)
        .fold<double>(0, (sum, account) => sum + account.currentBalance);

    return LayoutBuilder(
      builder: (context, constraints) {
        final width =
            constraints.maxWidth >= 760
                ? (constraints.maxWidth - 24) / 4
                : constraints.maxWidth >= 420
                ? (constraints.maxWidth - 12) / 2
                : constraints.maxWidth;

        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _SummaryTile(
              width: width,
              label: 'Total Balance',
              value: _money(totalBalance),
              icon: Icons.account_balance_wallet_rounded,
            ),
            _SummaryTile(
              width: width,
              label: 'Cash',
              value: _money(cash),
              icon: Icons.payments_rounded,
            ),
            _SummaryTile(
              width: width,
              label: 'Bank',
              value: _money(bank),
              icon: Icons.account_balance_rounded,
            ),
            _SummaryTile(
              width: width,
              label: 'Wallets',
              value: _money(wallets),
              icon: Icons.phone_android_rounded,
            ),
          ],
        );
      },
    );
  }

  double _sumByType(AccountType type) {
    return accounts
        .where((account) => account.type == type)
        .fold<double>(0, (sum, account) => sum + account.currentBalance);
  }
}

class _SummaryTile extends StatelessWidget {
  final double width;
  final String label;
  final String value;
  final IconData icon;

  const _SummaryTile({
    required this.width,
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Card(
        elevation: 0,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                foregroundColor: AppColors.primary,
                child: Icon(icon, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AccountsPanel extends StatelessWidget {
  final List<AccountModel> accounts;

  const _AccountsPanel({required this.accounts});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Accounts',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            if (accounts.isEmpty)
              const _EmptyLine(text: 'No account created yet.')
            else
              for (final account in accounts) _AccountTile(account: account),
          ],
        ),
      ),
    );
  }
}

class _AccountTile extends StatelessWidget {
  final AccountModel account;

  const _AccountTile({required this.account});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: AppColors.primary.withValues(alpha: 0.1),
            foregroundColor: AppColors.primary,
            child: Icon(_iconForType(account.type), size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  account.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                Text(
                  account.type.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _money(account.currentBalance),
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _TransactionsPanel extends StatelessWidget {
  final List<AccountTransactionModel> transactions;
  final bool loading;

  const _TransactionsPanel({required this.transactions, this.loading = false});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Recent Ledger',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (loading)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            if (transactions.isEmpty)
              const _EmptyLine(text: 'No ledger entries yet.')
            else
              for (final transaction in transactions)
                _TransactionTile(transaction: transaction),
          ],
        ),
      ),
    );
  }
}

class _TransactionTile extends StatelessWidget {
  final AccountTransactionModel transaction;

  const _TransactionTile({required this.transaction});

  @override
  Widget build(BuildContext context) {
    final isIn = transaction.direction == AccountTransactionDirection.moneyIn;
    final color = isIn ? AppColors.success : AppColors.error;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: color.withValues(alpha: 0.1),
            foregroundColor: color,
            child: Icon(isIn ? Icons.south_west : Icons.north_east, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  transaction.description ?? transaction.type.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                Text(
                  '${transaction.type.label} • ${_dateText(transaction.transactionAt)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${isIn ? '+' : '-'}${_money(transaction.amount)}',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _AccountsErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _AccountsErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 120),
        const Icon(
          Icons.error_outline_rounded,
          size: 52,
          color: AppColors.error,
        ),
        const SizedBox(height: 12),
        Text(
          'Accounts load nahi ho sake',
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Text(message, textAlign: TextAlign.center),
        const SizedBox(height: 16),
        Center(
          child: OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Retry'),
          ),
        ),
      ],
    );
  }
}

class _EmptyLine extends StatelessWidget {
  final String text;

  const _EmptyLine({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Center(
        child: Text(
          text,
          style: const TextStyle(color: AppColors.textSecondary),
        ),
      ),
    );
  }
}

Future<void> _showAccountDialog(BuildContext context, WidgetRef ref) async {
  final nameController = TextEditingController();
  final balanceController = TextEditingController(text: '0');
  final noteController = TextEditingController();
  var type = AccountType.cash;

  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text('Add Account'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: 'Account name',
                    ),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<AccountType>(
                    initialValue: type,
                    decoration: const InputDecoration(labelText: 'Type'),
                    items:
                        AccountType.values
                            .map(
                              (item) => DropdownMenuItem(
                                value: item,
                                child: Text(item.label),
                              ),
                            )
                            .toList(),
                    onChanged: (value) {
                      if (value != null) setState(() => type = value);
                    },
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: balanceController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Opening balance',
                      prefixText: 'Rs ',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: noteController,
                    decoration: const InputDecoration(
                      labelText: 'Note optional',
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () async {
                  final name = nameController.text.trim();
                  if (name.isEmpty) return;
                  final balance =
                      double.tryParse(balanceController.text.trim()) ?? 0;
                  final ok = await ref
                      .read(accountControllerProvider.notifier)
                      .createAccount(
                        name: name,
                        type: type,
                        openingBalance: balance,
                        note: noteController.text,
                      );
                  if (ok && dialogContext.mounted) {
                    Navigator.of(dialogContext).pop();
                  } else if (dialogContext.mounted) {
                    _showAccountActionError(dialogContext, ref);
                  }
                },
                child: const Text('Save'),
              ),
            ],
          );
        },
      );
    },
  );

  nameController.dispose();
  balanceController.dispose();
  noteController.dispose();
}

Future<void> _showEntryDialog(
  BuildContext context,
  WidgetRef ref,
  List<AccountModel> accounts,
) async {
  final amountController = TextEditingController();
  final noteController = TextEditingController();
  var accountId = accounts.first.id;
  var direction = AccountTransactionDirection.moneyOut;
  var type = AccountTransactionType.expense;

  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text('Add Ledger Entry'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: accountId,
                    decoration: const InputDecoration(labelText: 'Account'),
                    items:
                        accounts
                            .map(
                              (account) => DropdownMenuItem(
                                value: account.id,
                                child: Text(account.name),
                              ),
                            )
                            .toList(),
                    onChanged: (value) {
                      if (value != null) setState(() => accountId = value);
                    },
                  ),
                  const SizedBox(height: 10),
                  SegmentedButton<AccountTransactionDirection>(
                    segments:
                        AccountTransactionDirection.values
                            .map(
                              (item) => ButtonSegment(
                                value: item,
                                label: Text(item.label),
                              ),
                            )
                            .toList(),
                    selected: {direction},
                    onSelectionChanged: (values) {
                      final selected = values.first;
                      setState(() {
                        direction = selected;
                        type =
                            selected == AccountTransactionDirection.moneyIn
                                ? AccountTransactionType.other
                                : AccountTransactionType.expense;
                      });
                    },
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<AccountTransactionType>(
                    initialValue: type,
                    decoration: const InputDecoration(labelText: 'Entry type'),
                    items:
                        _entryTypes(direction)
                            .map(
                              (item) => DropdownMenuItem(
                                value: item,
                                child: Text(item.label),
                              ),
                            )
                            .toList(),
                    onChanged: (value) {
                      if (value != null) setState(() => type = value);
                    },
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: amountController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Amount',
                      prefixText: 'Rs ',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: noteController,
                    decoration: const InputDecoration(labelText: 'Description'),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () async {
                  final amount =
                      double.tryParse(amountController.text.trim()) ?? 0;
                  if (amount <= 0) return;
                  final ok = await ref
                      .read(accountControllerProvider.notifier)
                      .recordTransaction(
                        accountId: accountId,
                        direction: direction,
                        type: type,
                        amount: amount,
                        description: noteController.text,
                      );
                  if (ok && dialogContext.mounted) {
                    Navigator.of(dialogContext).pop();
                  } else if (dialogContext.mounted) {
                    _showAccountActionError(dialogContext, ref);
                  }
                },
                child: const Text('Save'),
              ),
            ],
          );
        },
      );
    },
  );

  amountController.dispose();
  noteController.dispose();
}

Future<void> _showTransferDialog(
  BuildContext context,
  WidgetRef ref,
  List<AccountModel> accounts,
) async {
  final amountController = TextEditingController();
  final noteController = TextEditingController();
  var fromAccountId = accounts.first.id;
  var toAccountId = accounts.firstWhere((e) => e.id != fromAccountId).id;

  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text('Transfer Funds'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: fromAccountId,
                    decoration: const InputDecoration(labelText: 'From'),
                    items: _accountItems(accounts),
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() {
                        fromAccountId = value;
                        if (toAccountId == fromAccountId) {
                          toAccountId =
                              accounts.firstWhere((e) => e.id != value).id;
                        }
                      });
                    },
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: toAccountId,
                    decoration: const InputDecoration(labelText: 'To'),
                    items:
                        accounts
                            .where((account) => account.id != fromAccountId)
                            .map(
                              (account) => DropdownMenuItem(
                                value: account.id,
                                child: Text(account.name),
                              ),
                            )
                            .toList(),
                    onChanged: (value) {
                      if (value != null) setState(() => toAccountId = value);
                    },
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: amountController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Amount',
                      prefixText: 'Rs ',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: noteController,
                    decoration: const InputDecoration(
                      labelText: 'Note optional',
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () async {
                  final amount =
                      double.tryParse(amountController.text.trim()) ?? 0;
                  if (amount <= 0) return;
                  final ok = await ref
                      .read(accountControllerProvider.notifier)
                      .transfer(
                        fromAccountId: fromAccountId,
                        toAccountId: toAccountId,
                        amount: amount,
                        description: noteController.text,
                      );
                  if (ok && dialogContext.mounted) {
                    Navigator.of(dialogContext).pop();
                  } else if (dialogContext.mounted) {
                    _showAccountActionError(dialogContext, ref);
                  }
                },
                child: const Text('Transfer'),
              ),
            ],
          );
        },
      );
    },
  );

  amountController.dispose();
  noteController.dispose();
}

void _showAccountActionError(BuildContext context, WidgetRef ref) {
  final state = ref.read(accountControllerProvider);
  final message =
      state.hasError
          ? state.error.toString().replaceFirst('Exception: ', '')
          : 'Could not save. Please try again.';
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

List<DropdownMenuItem<String>> _accountItems(List<AccountModel> accounts) {
  return accounts
      .map(
        (account) =>
            DropdownMenuItem(value: account.id, child: Text(account.name)),
      )
      .toList();
}

List<AccountTransactionType> _entryTypes(
  AccountTransactionDirection direction,
) {
  if (direction == AccountTransactionDirection.moneyIn) {
    return const [
      AccountTransactionType.sale,
      AccountTransactionType.customerPayment,
      AccountTransactionType.adjustment,
      AccountTransactionType.other,
    ];
  }

  return const [
    AccountTransactionType.expense,
    AccountTransactionType.purchase,
    AccountTransactionType.supplierPayment,
    AccountTransactionType.adjustment,
    AccountTransactionType.other,
  ];
}

IconData _iconForType(AccountType type) {
  switch (type) {
    case AccountType.cash:
      return Icons.payments_rounded;
    case AccountType.bank:
      return Icons.account_balance_rounded;
    case AccountType.mobileWallet:
      return Icons.phone_android_rounded;
    case AccountType.card:
      return Icons.credit_card_rounded;
    case AccountType.other:
      return Icons.account_balance_wallet_rounded;
  }
}

String _money(double value) {
  return 'Rs ${value.toStringAsFixed(0)}';
}

String _dateText(DateTime date) {
  final day = date.day.toString().padLeft(2, '0');
  final month = date.month.toString().padLeft(2, '0');
  return '$day-$month-${date.year}';
}
