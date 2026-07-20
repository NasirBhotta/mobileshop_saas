import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobileshop_saas/core/tenant_access/tenant_access_provider.dart';
import 'package:mobileshop_saas/features/auth/presentation/providers/auth_provider.dart';

class TenantSuspendedScreen extends ConsumerWidget {
  const TenantSuspendedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final signingOut = ref.watch(authControllerProvider).isLoading;
    final accessState = ref.watch(tenantAccessProvider);
    final access = accessState.asData?.value;

    if (accessState.isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final content = _contentFor(access);
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
                  content.title,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 12),
                Text(content.message, textAlign: TextAlign.center),
                const SizedBox(height: 24),
                if (access ==
                    TenantAccessState.offlineVerificationRequired) ...[
                  FilledButton.icon(
                    onPressed: () {
                      ref.invalidate(tenantAccessProvider);
                      ref.read(tenantAccessRefreshProvider).refresh();
                    },
                    icon: const Icon(Icons.refresh),
                    label: const Text('Try again'),
                  ),
                  const SizedBox(height: 12),
                ],
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

({String title, String message}) _contentFor(TenantAccessState? state) {
  return switch (state) {
    TenantAccessState.activationRequired => (
      title: 'Account activation required',
      message:
          'Your shop setup is complete, but no trial or subscription is active. Contact support to start your trial.',
    ),
    TenantAccessState.cancelled => (
      title: 'Subscription cancelled',
      message:
          'Your subscription has been cancelled. Contact support to restore access.',
    ),
    TenantAccessState.trialExpired => (
      title: 'Trial expired',
      message:
          'Your trial period has ended. Choose a plan or contact support to continue.',
    ),
    TenantAccessState.graceExpired => (
      title: 'Grace period ended',
      message:
          'Your payment grace period has ended. Contact support to restore access.',
    ),
    TenantAccessState.subscriptionExpired => (
      title: 'Subscription expired',
      message:
          'Your subscription has expired. Renew it to continue using the app.',
    ),
    TenantAccessState.offlineVerificationRequired => (
      title: 'Internet connection required',
      message:
          'Connect to the internet so we can verify your shop subscription, then try again.',
    ),
    _ => (
      title: 'Account suspended',
      message:
          'Your shop account is currently suspended. Contact support or your administrator to restore access.',
    ),
  };
}
