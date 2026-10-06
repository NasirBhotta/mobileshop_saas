import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobileshop_saas/core/platform/web_device_policy.dart';

void main() {
  group('web device policy', () {
    test('allows iPhone/iPad and Mac browsers', () {
      expect(
        isSupportedWebDevice(isWeb: true, platform: TargetPlatform.iOS),
        isTrue,
      );
      expect(
        isSupportedWebDevice(isWeb: true, platform: TargetPlatform.macOS),
        isTrue,
      );
    });

    test('blocks other web platforms', () {
      for (final platform in [
        TargetPlatform.android,
        TargetPlatform.windows,
        TargetPlatform.linux,
        TargetPlatform.fuchsia,
      ]) {
        expect(
          isSupportedWebDevice(isWeb: true, platform: platform),
          isFalse,
          reason: '$platform should not run the web client',
        );
      }
    });

    test('does not restrict native app builds', () {
      for (final platform in TargetPlatform.values) {
        expect(
          isSupportedWebDevice(isWeb: false, platform: platform),
          isTrue,
          reason: 'Native $platform behavior must remain available',
        );
      }
    });
  });
}
