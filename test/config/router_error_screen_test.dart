import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mobileshop_saas/config/router/router_error_screen.dart';

void main() {
  testWidgets('router error screen offers retry and dashboard recovery', (
    tester,
  ) async {
    final router = GoRouter(
      initialLocation: '/router-error',
      routes: [
        GoRoute(
          path: '/router-error',
          builder:
              (_, _) => const RouterErrorScreen(
                error: 'test error',
                attemptedLocation: '/inventory',
              ),
        ),
        GoRoute(
          path: '/inventory',
          builder: (_, _) => const Scaffold(body: Text('Inventory page')),
        ),
        GoRoute(
          path: '/dashboard',
          builder: (_, _) => const Scaffold(body: Text('Dashboard page')),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    expect(find.text('We could not open this page'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    expect(find.text('Go to dashboard'), findsOneWidget);

    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('Inventory page'), findsOneWidget);
  });

  testWidgets('router error screen does not retry its own route', (
    tester,
  ) async {
    final router = GoRouter(
      initialLocation: '/router-error',
      routes: [
        GoRoute(
          path: '/router-error',
          builder:
              (_, _) => const RouterErrorScreen(
                attemptedLocation: '/router-error?from=/inventory',
              ),
        ),
        GoRoute(
          path: '/dashboard',
          builder: (_, _) => const Scaffold(body: Text('Dashboard page')),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    expect(find.text('Try again'), findsNothing);
    await tester.tap(find.text('Go to dashboard'));
    await tester.pumpAndSettle();
    expect(find.text('Dashboard page'), findsOneWidget);
  });
}
