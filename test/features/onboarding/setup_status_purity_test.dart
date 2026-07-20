import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String repository;
  late String setupController;
  late String authProvider;
  late String router;

  setUpAll(() {
    repository =
        File(
          'lib/features/onboarding/data/repositories/setup_flow_repository.dart',
        ).readAsStringSync();
    setupController =
        File(
          'lib/features/onboarding/presentation/providers/shop_setup_provider.dart',
        ).readAsStringSync();
    authProvider =
        File(
          'lib/features/auth/presentation/providers/auth_provider.dart',
        ).readAsStringSync();
    router = File('lib/config/router/app_router.dart').readAsStringSync();
  });

  test('setup status resolution contains no workflow or sync writes', () {
    final start = repository.indexOf('Future<SetupFlowStatus> loadStatus');
    final end = repository.indexOf(
      'Future<Map<String, dynamic>?> loadProfile',
      start,
    );
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    final body = repository.substring(start, end);

    expect(body, isNot(contains('markSetupComplete(')));
    expect(body, isNot(contains('selectBranch(')));
    expect(body, isNot(contains('requestOfflineMutationSync(')));
    expect(body, isNot(contains('syncOfflineMutations(')));
  });

  test('writes remain in explicit lifecycle and setup actions', () {
    expect(authProvider, contains('.requestOfflineMutationSync('));
    expect(setupController, contains('markSetupComplete('));
    expect(setupController, contains('selectBranch('));
  });

  test('router coalesces concurrent setup status reads', () {
    expect(router, contains('Future<SetupFlowStatus>? setupLoadInFlight'));
    expect(router, contains('if (pending != null) return pending'));
    expect(router, contains('identical(setupLoadInFlight, load)'));
  });

  test('router resolves onboarding before subscription access', () {
    final setupRedirect = router.indexOf(
      'setupStatus.target == SetupRouteTarget.setup',
    );
    final accessLookup = router.indexOf(
      'ref.read(tenantAccessProvider.future)',
      setupRedirect,
    );

    expect(setupRedirect, greaterThanOrEqualTo(0));
    expect(accessLookup, greaterThan(setupRedirect));
  });
}
