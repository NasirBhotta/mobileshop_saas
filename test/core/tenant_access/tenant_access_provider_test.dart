import 'package:flutter_test/flutter_test.dart';
import 'package:mobileshop_saas/core/tenant_access/tenant_access_provider.dart';

void main() {
  final now = DateTime.utc(2026, 7, 16, 12);

  test('suspended tenant is blocked regardless of status casing', () {
    expect(
      resolveTenantAccessState('SUSPENDED', now: now),
      TenantAccessState.suspended,
    );
  });

  test('unknown or missing tenant status fails closed', () {
    expect(
      resolveTenantAccessState('unknown', now: now),
      TenantAccessState.accessConfigurationError,
    );
    expect(
      resolveTenantAccessState(null, now: now),
      TenantAccessState.accessConfigurationError,
    );
  });

  test('completed setup without a subscription requires activation', () {
    expect(
      resolveTenantAccessState('active', requireSubscription: true, now: now),
      TenantAccessState.activationRequired,
    );
    expect(
      resolveTenantAccessState(
        'active',
        subscription: {'status': 'pending_activation'},
        now: now,
      ),
      TenantAccessState.activationRequired,
    );
  });

  test('valid trial and grace periods remain accessible', () {
    expect(
      resolveTenantAccessState(
        'active',
        subscription: {
          'status': 'trialing',
          'trial_ends_at': now.add(const Duration(days: 1)).toIso8601String(),
        },
        now: now,
      ),
      TenantAccessState.active,
    );
    expect(
      resolveTenantAccessState(
        'active',
        subscription: {
          'status': 'grace_period',
          'grace_ends_at': now.add(const Duration(hours: 1)).toIso8601String(),
        },
        now: now,
      ),
      TenantAccessState.active,
    );
  });

  test('expired trial, grace, cancellation and expiry are blocked', () {
    TenantAccessState resolve(String status, String dateKey) =>
        resolveTenantAccessState(
          'active',
          subscription: {
            'status': status,
            dateKey: now.subtract(const Duration(seconds: 1)).toIso8601String(),
          },
          now: now,
        );

    expect(
      resolve('trialing', 'trial_ends_at'),
      TenantAccessState.trialExpired,
    );
    expect(
      resolve('grace_period', 'grace_ends_at'),
      TenantAccessState.graceExpired,
    );
    expect(
      resolveTenantAccessState(
        'active',
        subscription: {'status': 'cancelled'},
        now: now,
      ),
      TenantAccessState.cancelled,
    );
    expect(
      resolve('active', 'expires_at'),
      TenantAccessState.subscriptionExpired,
    );
  });

  test('missing required subscription deadlines fail closed', () {
    for (final status in const ['trialing', 'grace_period', 'active']) {
      expect(
        resolveTenantAccessState(
          'active',
          subscription: {'status': status},
          now: now,
        ),
        TenantAccessState.accessConfigurationError,
      );
    }
  });

  test('unknown subscription status fails closed', () {
    expect(
      resolveTenantAccessState(
        'active',
        subscription: {'status': 'unexpected'},
        now: now,
      ),
      TenantAccessState.accessConfigurationError,
    );
  });
}
