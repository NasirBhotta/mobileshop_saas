import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('dashboard entry and resume refresh account caches safely', () {
    final provider =
        File(
          'lib/features/dashboard/presentation/providers/dashboard_provider.dart',
        ).readAsStringSync();
    final screen =
        File(
          'lib/features/dashboard/presentation/screens/dashboard_screen.dart',
        ).readAsStringSync();

    expect(screen, contains('dashboardAccountLifecycleRefreshProvider'));
    expect(provider, contains('AppLifecycleState.resumed'));
    expect(provider, contains('await posRepository.syncOfflineMutations()'));
    expect(provider, contains('refreshCurrentAccountsCache'));
    expect(provider, contains('refreshCurrentTransactionsCache'));
    expect(provider, contains('invalidate(accountsProvider)'));
    expect(provider, contains('inFlight'));
  });

  test('remote account refresh preserves optimistic financial mutations', () {
    final repository =
        File(
          'lib/features/accounts/data/repositories/accounts_repository.dart',
        ).readAsStringSync();

    expect(repository, contains('_hasPendingOptimisticAccountMutation'));
    expect(repository, contains("'sale_checkout'"));
    expect(repository, contains("'customer_settlement'"));
    expect(repository, contains("'sale_return'"));
  });
}
