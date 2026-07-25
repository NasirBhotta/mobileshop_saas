import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobileshop_saas/features/mobile_services/data/models/mobile_service_models.dart';
import 'package:mobileshop_saas/features/mobile_services/presentation/providers/mobile_services_provider.dart';
import 'package:mobileshop_saas/features/mobile_services/presentation/screens/mobile_service_report_screen.dart';

void main() {
  testWidgets('report shows transaction totals and profit', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          mobileServiceProvidersProvider.overrideWith((ref) async => const []),
          mobileServiceReportProvider.overrideWith(
            (ref) async => const MobileServiceReportSummary(
              transactionCount: 4,
              sendCount: 3,
              receiveCount: 1,
              sentAmount: 3000,
              receivedAmount: 1000,
              customerCashIn: 3060,
              customerCashOut: 980,
              profit: 80,
            ),
          ),
        ],
        child: const MaterialApp(home: MobileServiceReportScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Mobile Services Report'), findsOneWidget);
    expect(find.text('Transactions'), findsOneWidget);
    expect(find.text('4'), findsOneWidget);
    expect(find.text('Profit'), findsOneWidget);
    expect(find.text('Rs. 80'), findsOneWidget);
  });
}
