import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobileshop_saas/features/auth/presentation/providers/auth_provider.dart';

class TenantSuspendedScreen extends ConsumerWidget {
  const TenantSuspendedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final signingOut = ref.watch(authControllerProvider).isLoading;
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.lock_clock_outlined, size: 64),
                const SizedBox(height: 20),
                Text(
                  'Account suspended',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Your shop account is currently suspended. Contact support or your administrator to restore access.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                FilledButton.tonalIcon(
                  onPressed:
                      signingOut
                          ? null
                          : () async {
                            final ok =
                                await ref
                                    .read(authControllerProvider.notifier)
                                    .logoutLocally();
                            if (!context.mounted) return;
                            if (ok) {
                              context.go('/login');
                              return;
                            }
                            final error =
                                ref.read(authControllerProvider).error;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  error?.toString() ?? 'Could not sign out.',
                                ),
                              ),
                            );
                          },
                  icon: const Icon(Icons.logout),
                  label: Text(signingOut ? 'Signing out...' : 'Sign out'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
