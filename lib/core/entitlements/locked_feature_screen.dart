import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class LockedFeatureScreen extends StatelessWidget {
  final String featureKey;
  const LockedFeatureScreen({required this.featureKey, super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Feature unavailable')),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.lock_outline,
                  size: 56,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 20),
                Text(
                  'This feature is not included in your current package.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 12),
                Text(
                  'This module remains visible so you can discover it, but it '
                  'is currently locked. Contact support to upgrade your package '
                  'or enable $featureKey.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: () => context.go('/dashboard'),
                  icon: const Icon(Icons.dashboard_outlined),
                  label: const Text('Back to dashboard'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
