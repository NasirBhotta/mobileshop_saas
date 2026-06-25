import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobileshop_saas/features/auth/presentation/screens/login_screen.dart';

void main() {
  testWidgets('shows login screen', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: LoginScreen())),
    );

    expect(find.text('MobileShop SaaS'), findsOneWidget);
    expect(find.text('Sign in'), findsAtLeastNWidgets(1));
  });
}
