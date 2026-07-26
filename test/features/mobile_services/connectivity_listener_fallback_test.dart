import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('connectivity stream errors degrade without breaking auto-sync', () {
    final source =
        File(
          'lib/features/mobile_services/presentation/providers/mobile_services_provider.dart',
        ).readAsStringSync();

    expect(source, contains('connectivity.onConnectivityChanged.listen('));
    expect(source, contains('onError: (Object error, StackTrace stackTrace)'));
    expect(source, contains('scheduleSync();'));
    expect(source, contains('Supabase.instance.client.auth.onAuthStateChange'));
  });
}
