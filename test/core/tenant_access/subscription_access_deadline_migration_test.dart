import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String migration;
  late String adminBillingUi;

  setUpAll(() {
    migration =
        File(
          'supabase/migrations/20260718000100_enforce_subscription_access_deadlines.sql',
        ).readAsStringSync().toLowerCase();
    adminBillingUi =
        File(
          'admin_portal_export/lib/src/billing/presentation/tenant_billing_section.dart',
        ).readAsStringSync().toLowerCase();
  });

  test('access-bearing statuses require their deadline columns', () {
    expect(
      migration,
      contains("normalized_status = 'trialing' and new.trial_ends_at is null"),
    );
    expect(
      migration,
      contains(
        "normalized_status = 'grace_period' and new.grace_ends_at is null",
      ),
    );
    expect(
      migration,
      contains("normalized_status = 'active' and new.expires_at is null"),
    );
  });

  test('only trial and grace actions request an end date in the admin UI', () {
    expect(
      adminBillingUi,
      contains("['trial_start', 'trial_extend', 'grace'].contains(action)"),
    );
    expect(adminBillingUi, contains('until: until'));
    expect(
      adminBillingUi,
      contains("action == 'activate' || action == 'renew'"),
    );
    expect(adminBillingUi, contains('? billingcycle'));
  });

  test('activation and renewal deadlines are calculated by the database', () {
    expect(
      migration,
      contains("if action = 'activate' then\n    calculated_until"),
    );
    expect(migration, contains("when 'annual' then interval '1 year'"));
    expect(migration, contains("else interval '1 month'"));
    expect(
      migration,
      contains(
        'renewal_start := greatest(p_effective_at, coalesce(s.expires_at, p_effective_at))',
      ),
    );
  });
}
