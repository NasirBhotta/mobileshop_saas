import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobileshop_saas/features/accounts/data/models/account_models.dart';
import 'package:mobileshop_saas/features/accounts/presentation/providers/accounts_provider.dart';
import 'package:mobileshop_saas/features/mobile_services/data/models/mobile_service_models.dart';
import 'package:mobileshop_saas/features/mobile_services/presentation/providers/mobile_services_provider.dart';
import 'package:mobileshop_saas/features/mobile_services/presentation/screens/mobile_service_settings_screen.dart';

void main() {
  testWidgets('settings screen shows both providers and wallet guidance', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          mobileServiceProvidersProvider.overrideWith(
            (ref) async => const <MobileServiceProviderModel>[],
          ),
          mobileServiceChargeRulesProvider.overrideWith(
            (ref) async => const <MobileServiceChargeRuleModel>[],
          ),
          accountsProvider.overrideWith((ref) async => const <AccountModel>[]),
        ],
        child: const MaterialApp(home: MobileServiceSettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Mobile Service Settings'), findsOneWidget);
    expect(find.text('Easypaisa'), findsOneWidget);
    expect(find.text('JazzCash'), findsOneWidget);
    expect(find.text('Create a mobile-wallet account first'), findsOneWidget);
  });

  testWidgets('configured provider displays its linked wallet', (tester) async {
    final provider = MobileServiceProviderModel.fromMap(_providerMap());
    const wallet = AccountModel(
      id: 'wallet-1',
      tenantId: 'tenant-1',
      branchId: 'branch-1',
      name: 'Easypaisa Wallet',
      type: AccountType.mobileWallet,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          mobileServiceProvidersProvider.overrideWith(
            (ref) async => [provider],
          ),
          mobileServiceChargeRulesProvider.overrideWith(
            (ref) async => const <MobileServiceChargeRuleModel>[],
          ),
          accountsProvider.overrideWith((ref) async => const [wallet]),
        ],
        child: const MaterialApp(home: MobileServiceSettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Wallet: Easypaisa Wallet'), findsOneWidget);
    expect(find.text('Send Money'), findsOneWidget);
    expect(find.text('Receive Money'), findsOneWidget);
    expect(find.text('Not configured'), findsNWidgets(3));
  });
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
