import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobileshop_saas/features/accounts/data/models/account_models.dart';
import 'package:mobileshop_saas/features/accounts/presentation/providers/accounts_provider.dart';
import 'package:mobileshop_saas/features/mobile_services/data/models/mobile_service_models.dart';
import 'package:mobileshop_saas/features/mobile_services/data/remote/mobile_services_remote_data_source.dart';
import 'package:mobileshop_saas/features/mobile_services/data/repositories/mobile_services_repository.dart';
import 'package:mobileshop_saas/features/mobile_services/presentation/providers/mobile_services_provider.dart';
import 'package:mobileshop_saas/features/mobile_services/presentation/screens/mobile_services_screen.dart';

void main() {
  testWidgets('empty screen guides the user to configure providers', (
    tester,
  ) async {
    await _pumpScreen(tester);

    expect(find.text('Mobile Services'), findsOneWidget);
    expect(find.text('Configure Easypaisa or JazzCash'), findsOneWidget);
    expect(find.text('Cash account required'), findsNothing);
  });

  testWidgets('entered amount displays calculated send preview', (
    tester,
  ) async {
    final provider = MobileServiceProviderModel.fromMap(_providerMap());
    final rule = MobileServiceChargeRuleModel.fromMap(_ruleMap());
    const accounts = [
      AccountModel(
        id: 'cash-1',
        tenantId: 'tenant-1',
        branchId: 'branch-1',
        name: 'Cash in Shop',
        currentBalance: 2000,
        isDefault: true,
      ),
      AccountModel(
        id: 'wallet-1',
        tenantId: 'tenant-1',
        branchId: 'branch-1',
        name: 'Easypaisa Wallet',
        type: AccountType.mobileWallet,
        currentBalance: 5000,
      ),
    ];
    await _pumpScreen(
      tester,
      providers: [provider],
      rules: [rule],
      accounts: accounts,
    );

    await tester.enterText(
      find.widgetWithText(TextField, 'Amount to send'),
      '800',
    );
    await tester.pump();

    expect(find.text('Customer pays'), findsOneWidget);
    expect(find.text('Rs 820.00'), findsWidgets);
    expect(find.text('Rs 20.00'), findsWidgets);
    expect(find.textContaining('Rs 2000.00 → Rs 2820.00'), findsOneWidget);
    expect(find.textContaining('Rs 5000.00 → Rs 4200.00'), findsOneWidget);
  });
}

Future<void> _pumpScreen(
  WidgetTester tester, {
  List<MobileServiceProviderModel> providers = const [],
  List<MobileServiceChargeRuleModel> rules = const [],
  List<AccountModel> accounts = const [],
  List<MobileServiceTransactionModel> transactions = const [],
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        mobileServicesRepositoryProvider.overrideWithValue(
          MobileServicesRepository(remote: _NoopRemote()),
        ),
        mobileServiceProvidersProvider.overrideWith((ref) async => providers),
        mobileServiceChargeRulesProvider.overrideWith((ref) async => rules),
        accountsProvider.overrideWith((ref) async => accounts),
        mobileServiceTransactionsProvider(
          100,
        ).overrideWith((ref) async => transactions),
      ],
      child: const MaterialApp(home: MobileServicesScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

class _NoopRemote implements MobileServicesRemoteDataSource {
  Never _unused() => throw UnimplementedError();

  @override
  Future<List<Map<String, dynamic>>> fetchChargeRules(String branchId) =>
      _unused();

  @override
  Future<List<Map<String, dynamic>>> fetchProviders(String branchId) =>
      _unused();

  @override
  Future<Map<String, dynamic>> fetchTransactionById(String transactionId) =>
      _unused();

  @override
  Future<List<Map<String, dynamic>>> fetchTransactions(
    String branchId, {
    required int limit,
  }) => _unused();

  @override
  Future<Map<String, dynamic>> invokeMapRpc(
    String functionName,
    Map<String, dynamic> params,
  ) => _unused();

  @override
  Future<String> invokeUuidRpc(
    String functionName,
    Map<String, dynamic> params,
  ) => _unused();

  @override
  Future<void> invokeVoidRpc(
    String functionName,
    Map<String, dynamic> params,
  ) => _unused();
}

Map<String, dynamic> _providerMap() => {
  'id': 'provider-1',
  'tenant_id': 'tenant-1',
  'branch_id': 'branch-1',
  'category': 'money_transfer',
  'code': 'easypaisa',
  'name': 'Easypaisa',
  'provider_account_id': 'wallet-1',
  'is_active': true,
  'created_by': 'user-1',
  'created_at': '2026-07-25T10:00:00Z',
  'updated_at': '2026-07-25T10:00:00Z',
};

Map<String, dynamic> _ruleMap() => {
  'id': 'rule-1',
  'tenant_id': 'tenant-1',
  'branch_id': 'branch-1',
  'provider_id': 'provider-1',
  'operation': 'send',
  'calculation_method': 'full_slab',
  'rate_amount': 20,
  'per_amount': 1000,
  'minimum_fee': null,
  'maximum_fee': null,
  'is_active': true,
  'created_by': 'user-1',
  'created_at': '2026-07-25T10:00:00Z',
  'updated_at': '2026-07-25T10:00:00Z',
};
