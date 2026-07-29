import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('supplier reads and uniqueness are branch scoped', () {
    final repository =
        File(
          'lib/features/suppliers/data/repositories/'
          'procurement_repository.dart',
        ).readAsStringSync();
    final local =
        File(
          'lib/features/suppliers/data/local/procurement_local_store.dart',
        ).readAsStringSync();
    final migration =
        File(
          'supabase/migrations/'
          '20260729000900_supplier_branch_isolation.sql',
        ).readAsStringSync().toLowerCase();

    expect(repository, contains(".eq('branch_id', branchId)"));
    expect(local, contains('AND branch_id = ?'));
    expect(
      migration,
      contains('on public.suppliers(tenant_id, branch_id, lower(name))'),
    );
    expect(migration, contains('current_user_can_access_branch(branch_id)'));
  });
}
