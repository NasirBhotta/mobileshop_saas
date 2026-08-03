import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('restore reactivates wallet and configure reuses archived provider', () {
    final migration = File(
      'supabase/migrations/20260802000300_mobile_service_provider_restore_lifecycle.sql',
    ).readAsStringSync();

    expect(
      migration,
      contains(
        'on conflict on constraint mobile_service_providers_code_unique',
      ),
    );
    expect(migration, contains('provider_account_id = excluded.provider_account_id'));
    expect(migration, contains('update public.accounts'));
    expect(migration, contains('set is_active = true'));
    expect(migration, contains('for update'));
  });
}
