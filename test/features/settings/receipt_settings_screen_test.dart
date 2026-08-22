import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobileshop_saas/features/settings/data/models/receipt_configuration_model.dart';
import 'package:mobileshop_saas/features/settings/presentation/providers/receipt_settings_provider.dart';
import 'package:mobileshop_saas/features/settings/presentation/screens/receipt_settings_screen.dart';

class FakeReceiptSettingsController extends StateNotifier<AsyncValue<ReceiptConfigurationModel?>>
    implements ReceiptSettingsController {
  FakeReceiptSettingsController() : super(const AsyncValue.data(null));

  @override
  Future<bool> saveConfiguration(ReceiptConfigurationModel config) async => true;

  @override
  Future<ReceiptConfigurationModel?> resetToDefault() async =>
      ReceiptConfigurationModel.defaultConfig();

  @override
  Future<void> sync() async {}
}

void main() {
  testWidgets('ReceiptSettingsScreen renders shop info, toggles, and preview card', (tester) async {
    final fakeConfig = ReceiptConfigurationModel.defaultConfig(
      shopName: 'Galaxy Repair Center',
      phone: '0300-7654321',
      address: 'Shop 10, Metro Mall',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          receiptConfigurationProvider.overrideWith((ref) => Future.value(fakeConfig)),
          receiptSettingsControllerProvider.overrideWith((ref) => FakeReceiptSettingsController()),
        ],
        child: const MaterialApp(
          home: ReceiptSettingsScreen(),
        ),
      ),
    );

    // Initial pump and settle
    await tester.pumpAndSettle();

    // Verify app bar title
    expect(find.text('Receipt & Printer Layout'), findsOneWidget);

    // Verify paper format options
    expect(find.text('80mm (Standard POS)'), findsOneWidget);
    expect(find.text('58mm (Mini POS)'), findsOneWidget);

    // Verify shop name textfield has initial data
    expect(find.text('Galaxy Repair Center'), findsWidgets);

    // Verify toggles
    expect(find.text('Print Barcode (Code128)'), findsOneWidget);
    expect(find.text('Customer Phone Number'), findsOneWidget);
    expect(find.text('Device IMEI / Serial Number'), findsOneWidget);

    // Verify action buttons
    expect(find.text('Reset to Default'), findsOneWidget);
    expect(find.text('Save Configuration'), findsOneWidget);
  });
}
