import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobileshop_saas/features/onboarding/data/models/intro_page_model.dart';
import 'package:mobileshop_saas/features/onboarding/presentation/screens/app_intro_screen.dart';

void main() {
  testWidgets('AppIntroScreen renders pages and handles Next/Get Started navigation',
      (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: AppIntroScreen(),
        ),
      ),
    );

    // Initial page check
    expect(find.text('Skip'), findsOneWidget);
    expect(find.text(IntroData.pages.first.title), findsOneWidget);
    expect(find.text('Next'), findsOneWidget);

    // Verify all 6 pages exist in IntroData
    expect(IntroData.pages.length, 6);

    // Tap Next button multiple times to reach the last page
    for (int i = 0; i < 5; i++) {
      final nextBtn = find.text('Next');
      expect(nextBtn, findsOneWidget);
      await tester.tap(nextBtn);
      await tester.pumpAndSettle();
    }

    // On last page (page 5): CTA button should change to "Get Started"
    expect(find.text('Get Started'), findsOneWidget);
    expect(find.text(IntroData.pages.last.title), findsOneWidget);
  });
}
