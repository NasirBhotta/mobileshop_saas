import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class RouterErrorScreen extends StatelessWidget {
  final Object? error;
  final String? attemptedLocation;

  const RouterErrorScreen({this.error, this.attemptedLocation, super.key});

  @override
  Widget build(BuildContext context) {
    final retryLocation = _safeRetryLocation(attemptedLocation);
    return Scaffold(
      appBar: AppBar(title: const Text('Page unavailable')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.error_outline,
                        size: 64,
                        color: Theme.of(context).colorScheme.error,
                      ),
                      const SizedBox(height: 18),
                      Text(
                        'We could not open this page',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'The link may be invalid, or the page could not be '
                        'loaded right now. You can try again or return to the '
                        'dashboard.',
                        textAlign: TextAlign.center,
                      ),
                      if (kDebugMode && error != null) ...[
                        const SizedBox(height: 14),
                        SelectableText(
                          error.toString(),
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                      const SizedBox(height: 24),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        alignment: WrapAlignment.center,
                        children: [
                          if (retryLocation != null)
                            OutlinedButton.icon(
                              onPressed: () => context.go(retryLocation),
                              icon: const Icon(Icons.refresh),
                              label: const Text('Try again'),
                            ),
                          FilledButton.icon(
                            onPressed: () => context.go('/dashboard'),
                            icon: const Icon(Icons.dashboard_outlined),
                            label: const Text('Go to dashboard'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String? _safeRetryLocation(String? location) {
  if (location == null ||
      !location.startsWith('/') ||
      location.startsWith('//') ||
      location.startsWith('/router-error')) {
    return null;
  }
  return location;
}
