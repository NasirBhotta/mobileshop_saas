import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String router;

  setUpAll(() {
    router = File('lib/config/router/app_router.dart').readAsStringSync();
  });

  test('router never force-casts state.extra', () {
    expect(
      RegExp(r'state\.extra\s+as\s+\w+').hasMatch(router),
      isFalse,
      reason: 'Browser refresh can remove state.extra; use a type guard.',
    );
  });

  test('required object routes have safe redirect guards', () {
    for (final route in const [
      '/customers/detail',
      '/inventory/edit',
      '/inventory/adjust',
      '/pos/complete',
      '/purchase-orders/receive',
      '/purchase-orders/export',
    ]) {
      final start = router.indexOf("path: '$route'");
      expect(start, greaterThanOrEqualTo(0), reason: '$route must exist');
      final nextRoute = router.indexOf('GoRoute(', start + 1);
      final definition = router.substring(
        start,
        nextRoute < 0 ? router.length : nextRoute,
      );
      expect(
        definition,
        contains('redirect:'),
        reason: '$route must redirect when required extra is unavailable',
      );
      expect(
        definition,
        contains('state.extra is'),
        reason: '$route must validate the runtime type of extra',
      );
    }
  });
}
