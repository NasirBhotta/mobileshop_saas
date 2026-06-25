import 'package:flutter_test/flutter_test.dart';

import 'package:mobileshop_saas/main.dart';

void main() {
  testWidgets('shows login screen', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());

    expect(find.text('MobileShop SaaS'), findsOneWidget);
    expect(find.text('Sign in'), findsAtLeastNWidgets(1));
  });
}
