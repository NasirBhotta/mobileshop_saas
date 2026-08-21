import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobileshop_saas/core/constants/app_colors.dart';
import 'package:mobileshop_saas/features/accounts/data/models/account_models.dart';
import 'package:mobileshop_saas/features/accounts/presentation/providers/accounts_provider.dart';
import 'package:mobileshop_saas/features/mobile_services/data/models/mobile_service_commands.dart';
import 'package:mobileshop_saas/features/mobile_services/data/models/mobile_service_models.dart';
import 'package:mobileshop_saas/features/mobile_services/domain/mobile_service_types.dart';
import 'package:mobileshop_saas/features/mobile_services/presentation/providers/mobile_services_provider.dart';
import 'package:mobileshop_saas/features/onboarding/data/repositories/setup_flow_repository.dart';

class MobileServiceSettingsScreen extends ConsumerWidget {
  const MobileServiceSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final providersAsync = ref.watch(mobileServiceProvidersProvider);
    final rulesAsync = ref.watch(mobileServiceChargeRulesProvider);
    final accountsAsync = ref.watch(accountsProvider);
    final action = ref.watch(mobileServiceSettingsControllerProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            ref
              ..invalidate(mobileServiceProvidersProvider)
              ..invalidate(mobileServiceChargeRulesProvider)
              ..invalidate(accountsProvider);
            await Future.wait([
              ref.read(mobileServiceProvidersProvider.future),
              ref.read(mobileServiceChargeRulesProvider.future),
              ref.read(accountsProvider.future),
            ]);
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
              return _SettingsContent(
                providers: providers,
                rules: rulesAsync.value ?? const [],
                accounts: accountsAsync.value ?? const [],
                saving: action.isLoading,
              );
            },
          ),
        ),
      ),
    );
  }
}

class _SettingsContent extends ConsumerWidget {
  final List<MobileServiceProviderModel> providers;
  final List<MobileServiceChargeRuleModel> rules;
  final List<AccountModel> accounts;
  final bool saving;

  const _SettingsContent({
    required this.providers,
    required this.rules,
    required this.accounts,
    required this.saving,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final walletsById = <String, AccountModel>{};
    final bankAccountsById = <String, AccountModel>{};
    for (final account in accounts) {
      if (account.type == AccountType.mobileWallet && account.isActive) {
        walletsById.putIfAbsent(account.id, () => account);
      } else if (account.type == AccountType.bank && account.isActive) {
        bankAccountsById.putIfAbsent(account.id, () => account);
      }
    }
    final wallets = walletsById.values.toList();
    final bankAccounts = bankAccountsById.values.toList();

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Mobile Service Settings',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
                  ),
                  SizedBox(height: 4),
                  Text('Link wallets/bank accounts and configure Send/Receive charges.'),
                ],
              ),
            ),
            if (saving)
              const SizedBox.square(
                dimension: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
          ],
        ),
        const SizedBox(height: 16),
        if (wallets.isEmpty && bankAccounts.isEmpty)
          Card(
            child: ListTile(
              leading: const Icon(Icons.warning_amber_rounded),
              title: const Text('Create a mobile-wallet or bank account first'),
              subtitle: const Text(
                'Accounts mein Easypaisa, JazzCash wallet ya Bank account create karein.',
              ),
            ),
          ),
        for (final code in MobileServiceProviderCode.values) ...[
          _ProviderSettingsCard(
            code: code,
            provider:
                providers
                    .where((provider) => provider.code == code)
                    .firstOrNull,
            rules: rules,
            availableAccounts:
                code == MobileServiceProviderCode.bank ? bankAccounts : wallets,
            saving: saving,
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _ProviderSettingsCard extends ConsumerWidget {
  final MobileServiceProviderCode code;
  final MobileServiceProviderModel? provider;
  final List<MobileServiceChargeRuleModel> rules;
  final List<AccountModel> availableAccounts;
  final bool saving;

  const _ProviderSettingsCard({
    required this.code,
    required this.provider,
    required this.rules,
    required this.availableAccounts,
    required this.saving,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final item = provider;
    final linkedAccount =
        item == null
            ? null
            : availableAccounts
                .where((account) => account.id == item.providerAccountId)
                .firstOrNull;
    final isBank = code == MobileServiceProviderCode.bank;
    final iconData = isBank
        ? Icons.account_balance_rounded
        : code == MobileServiceProviderCode.easypaisa
        ? Icons.account_balance_wallet_rounded
        : Icons.wallet_rounded;
    final accountLabel = isBank ? 'Bank Account' : 'Wallet';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  child: Icon(iconData),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        code.label,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        item == null
                            ? 'Not configured'
                            : item.isActive
                            ? '$accountLabel: ${linkedAccount?.name ?? 'Unavailable'}'
                            : 'Archived',
                      ),
                    ],
                  ),
                ),
                if (item == null || item.isActive)
                  OutlinedButton.icon(
                    onPressed:
                        saving || availableAccounts.isEmpty
                            ? null
                            : () => _showProviderDialog(
                              context,
                              ref,
                              code: code,
                              provider: item,
                              accounts: availableAccounts,
                            ),
                    icon: Icon(item == null ? Icons.add : Icons.edit),
                    label: Text(item == null ? 'Configure' : 'Edit'),
                  )
                else
                  OutlinedButton(
                    onPressed:
                        saving
                            ? null
                            : () => _restoreProvider(context, ref, item.id),
                    child: const Text('Restore'),
                  ),
              ],
            ),
            if (item != null && item.isActive) ...[
              const Divider(height: 28),
              for (final operation in MobileServiceOperation.values)
                _RuleTile(
                  operation: operation,
                  rule:
                      rules
                          .where(
                            (rule) =>
                                rule.providerId == item.id &&
                                rule.operation == operation,
                          )
                          .firstOrNull,
                  provider: item,
                  saving: saving,
                ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed:
                      saving
                          ? null
                          : () => _archiveProvider(context, ref, item.id),
                  icon: const Icon(Icons.archive_outlined),
                  label: const Text('Archive provider'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _RuleTile extends ConsumerWidget {
  final MobileServiceOperation operation;
  final MobileServiceChargeRuleModel? rule;
  final MobileServiceProviderModel provider;
  final bool saving;

  const _RuleTile({
    required this.operation,
    required this.rule,
    required this.provider,
    required this.saving,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final item = rule;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        operation == MobileServiceOperation.send
            ? Icons.north_east_rounded
            : Icons.south_west_rounded,
      ),
      title: Text(operation.label),
      subtitle: Text(_ruleDescription(item)),
      trailing:
          item != null && !item.isActive
              ? TextButton(
                onPressed:
                    saving ? null : () => _restoreRule(context, ref, item.id),
                child: const Text('Restore'),
              )
              : IconButton(
                tooltip: item == null ? 'Configure rule' : 'Edit rule',
                onPressed:
                    saving
                        ? null
                        : () => _showRuleDialog(
                          context,
                          ref,
                          provider: provider,
                          operation: operation,
                          rule: item,
                        ),
                icon: Icon(
                  item == null ? Icons.add_circle_outline : Icons.edit,
                ),
              ),
    );
  }

  String _ruleDescription(MobileServiceChargeRuleModel? rule) {
    if (rule == null) return 'Not configured';
    if (!rule.isActive) return 'Archived';
    switch (rule.calculationMethod) {
      case ServiceChargeCalculationMethod.fullSlab:
        return 'Rs ${_money(rule.rateAmount)} per started Rs ${_money(rule.perAmount ?? 0)}';
      case ServiceChargeCalculationMethod.proportional:
        return 'Rs ${_money(rule.rateAmount)} per Rs ${_money(rule.perAmount ?? 0)} proportionally';
      case ServiceChargeCalculationMethod.fixed:
        return 'Fixed Rs ${_money(rule.rateAmount)}';
      case ServiceChargeCalculationMethod.manual:
        return 'Fee entered on every transaction';
    }
  }
}

Future<void> _showProviderDialog(
  BuildContext context,
  WidgetRef ref, {
  required MobileServiceProviderCode code,
  required MobileServiceProviderModel? provider,
  required List<AccountModel> accounts,
}) async {
  final nameController = TextEditingController(
    text: provider?.name ?? code.label,
  );
  final linkedAccountId = provider?.providerAccountId;
  var accountId =
      linkedAccountId != null &&
              accounts.any((account) => account.id == linkedAccountId)
          ? linkedAccountId
          : accounts.first.id;
  final isBank = code == MobileServiceProviderCode.bank;
  final dialogTitle = isBank ? '${code.label} account' : '${code.label} wallet';
  final dropdownLabel =
      isBank ? 'Linked bank account' : 'Linked wallet account';

  final submitted = await showDialog<bool>(
    context: context,
    builder:
        (dialogContext) => StatefulBuilder(
          builder:
              (context, setState) => AlertDialog(
                title: Text(dialogTitle),
                content: SizedBox(
                  width: 420,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: nameController,
                        decoration: const InputDecoration(
                          labelText: 'Display name',
                        ),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: accountId,
                        decoration: InputDecoration(
                          labelText: dropdownLabel,
                        ),
                        items: [
                          for (final account in accounts)
                            DropdownMenuItem(
                              value: account.id,
                              child: Text(account.name),
                            ),
                        ],
                        onChanged:
                            (value) => setState(() => accountId = value!),
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext, false),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(dialogContext, true),
                    child: const Text('Save'),
                  ),
                ],
              ),
        ),
  );

  if (submitted != true || !context.mounted) {
    nameController.dispose();
    return;
  }
  final branchId = await ref.read(selectedBranchIdProvider.future);
  final success = await ref
      .read(mobileServiceSettingsControllerProvider.notifier)
      .saveProvider(
        SaveMobileServiceProviderCommand(
          providerId: provider?.id,
          branchId: branchId,
          code: code,
          name: nameController.text,
          providerAccountId: accountId,
        ),
      );
  nameController.dispose();
  if (context.mounted) _showResult(context, ref, success, 'Provider saved.');
}

Future<void> _showRuleDialog(
  BuildContext context,
  WidgetRef ref, {
  required MobileServiceProviderModel provider,
  required MobileServiceOperation operation,
  required MobileServiceChargeRuleModel? rule,
}) async {
  var method =
      rule?.calculationMethod ?? ServiceChargeCalculationMethod.fullSlab;
  final rate = TextEditingController(
    text: rule == null ? '20' : _money(rule.rateAmount),
  );
  final per = TextEditingController(
    text: rule?.perAmount == null ? '1000' : _money(rule!.perAmount!),
  );
  final minimum = TextEditingController(
    text: rule?.minimumFee == null ? '' : _money(rule!.minimumFee!),
  );
  final maximum = TextEditingController(
    text: rule?.maximumFee == null ? '' : _money(rule!.maximumFee!),
  );

  final submitted = await showDialog<bool>(
    context: context,
    builder:
        (dialogContext) => StatefulBuilder(
          builder: (context, setState) {
            final needsPer =
                method == ServiceChargeCalculationMethod.fullSlab ||
                method == ServiceChargeCalculationMethod.proportional;
            return AlertDialog(
              title: Text('${provider.name} • ${operation.label}'),
              content: SizedBox(
                width: 440,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      DropdownButtonFormField<ServiceChargeCalculationMethod>(
                        initialValue: method,
                        decoration: const InputDecoration(
                          labelText: 'Calculation method',
                        ),
                        items: [
                          for (final value
                              in ServiceChargeCalculationMethod.values)
                            DropdownMenuItem(
                              value: value,
                              child: Text(_methodLabel(value)),
                            ),
                        ],
                        onChanged: (value) => setState(() => method = value!),
                      ),
                      const SizedBox(height: 12),
                      if (method != ServiceChargeCalculationMethod.manual)
                        TextField(
                          controller: rate,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Rate / fee (Rs)',
                          ),
                        ),
                      if (needsPer) ...[
                        const SizedBox(height: 12),
                        TextField(
                          controller: per,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Per amount (Rs)',
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: minimum,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: const InputDecoration(
                                labelText: 'Minimum fee',
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: maximum,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: const InputDecoration(
                                labelText: 'Maximum fee',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                if (rule != null && rule.isActive)
                  TextButton(
                    onPressed: () async {
                      Navigator.pop(dialogContext, false);
                      await _archiveRule(context, ref, rule.id);
                    },
                    child: const Text('Archive'),
                  ),
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: const Text('Save'),
                ),
              ],
            );
          },
        ),
  );

  if (submitted == true && context.mounted) {
    final success = await ref
        .read(mobileServiceSettingsControllerProvider.notifier)
        .saveRule(
          SaveMobileServiceChargeRuleCommand(
            ruleId: rule?.id,
            providerId: provider.id,
            operation: operation,
            calculationMethod: method,
            rateAmount:
                method == ServiceChargeCalculationMethod.manual
                    ? 0
                    : double.tryParse(rate.text.trim()) ?? -1,
            perAmount:
                method == ServiceChargeCalculationMethod.fullSlab ||
                        method == ServiceChargeCalculationMethod.proportional
                    ? double.tryParse(per.text.trim())
                    : null,
            minimumFee: _optionalNumber(minimum.text),
            maximumFee: _optionalNumber(maximum.text),
          ),
        );
    if (context.mounted) _showResult(context, ref, success, 'Rule saved.');
  }
  rate.dispose();
  per.dispose();
  minimum.dispose();
  maximum.dispose();
}

Future<void> _archiveProvider(
  BuildContext context,
  WidgetRef ref,
  String id,
) async {
  final success = await ref
      .read(mobileServiceSettingsControllerProvider.notifier)
      .archiveProvider(id);
  if (context.mounted) _showResult(context, ref, success, 'Provider archived.');
}

Future<void> _restoreProvider(
  BuildContext context,
  WidgetRef ref,
  String id,
) async {
  final success = await ref
      .read(mobileServiceSettingsControllerProvider.notifier)
      .restoreProvider(id);
  if (context.mounted) _showResult(context, ref, success, 'Provider restored.');
}

Future<void> _archiveRule(
  BuildContext context,
  WidgetRef ref,
  String id,
) async {
  final success = await ref
      .read(mobileServiceSettingsControllerProvider.notifier)
      .archiveRule(id);
  if (context.mounted) _showResult(context, ref, success, 'Rule archived.');
}

Future<void> _restoreRule(
  BuildContext context,
  WidgetRef ref,
  String id,
) async {
  final success = await ref
      .read(mobileServiceSettingsControllerProvider.notifier)
      .restoreRule(id);
  if (context.mounted) _showResult(context, ref, success, 'Rule restored.');
}

void _showResult(
  BuildContext context,
  WidgetRef ref,
  bool success,
  String successMessage,
) {
  final state = ref.read(mobileServiceSettingsControllerProvider);
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        success ? successMessage : state.error?.toString() ?? 'Action failed.',
      ),
    ),
  );
}

double? _optionalNumber(String value) {
  final text = value.trim();
  return text.isEmpty ? null : double.tryParse(text);
}

String _methodLabel(ServiceChargeCalculationMethod method) {
  switch (method) {
    case ServiceChargeCalculationMethod.fullSlab:
      return 'Full slab';
    case ServiceChargeCalculationMethod.proportional:
      return 'Proportional';
    case ServiceChargeCalculationMethod.fixed:
      return 'Fixed fee';
    case ServiceChargeCalculationMethod.manual:
      return 'Manual fee';
  }
}

String _money(double value) {
  return value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(2);
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return ListView(
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
}
