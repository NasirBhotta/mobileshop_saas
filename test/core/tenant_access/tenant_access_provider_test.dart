import 'package:flutter_test/flutter_test.dart';
import 'package:mobileshop_saas/core/tenant_access/tenant_access_provider.dart';

void main() {
  test('suspended tenant is blocked regardless of status casing', () {
    expect(resolveTenantAccessState('SUSPENDED'), TenantAccessState.suspended);
  });

  test('active and legacy missing status remain accessible', () {
    expect(resolveTenantAccessState('active'), TenantAccessState.active);
    expect(resolveTenantAccessState(null), TenantAccessState.active);
  });

  test('completed setup without a subscription requires activation', () {
    expect(
      resolveTenantAccessState('active', requireSubscription: true),
      TenantAccessState.activationRequired,
    );
    expect(
      resolveTenantAccessState(
        'active',
        subscription: {'status': 'pending_activation'},
      ),
      TenantAccessState.activationRequired,
    );
  });

  test('valid trial and grace periods remain accessible', () {
    final now = DateTime.utc(2026, 7, 16, 12);
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
    final now = DateTime.utc(2026, 7, 16, 12);
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
}
