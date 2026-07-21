import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('subscription realtime refreshes the dedicated plan revision', () {
    final source =
        File(
          'lib/core/tenant_access/tenant_access_provider.dart',
        ).readAsStringSync();

    expect(source, contains('callback: handleSubscriptionChange'));
    expect(
      source,
      contains('ref.read(tenantPlanRevisionProvider.notifier).refresh();'),
    );

    final settingsProvider =
        File(
          'lib/features/settings/presentation/providers/account_settings_provider.dart',
        ).readAsStringSync();
    expect(settingsProvider, contains('ref.watch(tenantPlanRevisionProvider)'));
    expect(settingsProvider, contains('loadSettings(refreshTenant: true)'));
  });
}
