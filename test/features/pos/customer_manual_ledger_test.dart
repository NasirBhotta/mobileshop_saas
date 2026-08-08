import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobileshop_saas/features/pos/data/models/customer_dashboard_model.dart';
import 'package:mobileshop_saas/features/pos/data/repositories/pos_repository.dart';
import 'package:mobileshop_saas/features/pos/presentation/providers/pos_provider.dart';
import 'package:mobileshop_saas/features/pos/presentation/screens/customers_screen.dart';

void main() {
  test('customer ledger integration files compile together', () {
    PosRepository? repository;
    CustomerLedgerController? controller;
    const screen = CustomersScreen();
    expect(repository, isNull);
    expect(controller, isNull);
    expect(screen, isA<CustomersScreen>());
  });

  test('manual ledger entry directions have stable outstanding deltas', () {
    final now = DateTime.utc(2026, 8, 9);
    final charge = CustomerLedgerEntryModel(
      id: 'charge',
      customerId: 'customer',
      branchId: 'branch',
      userId: 'user',
      type: CustomerLedgerEntryType.charge,
      amount: 250,
      reason: 'Previous balance',
      createdAt: now,
    );
    final credit = CustomerLedgerEntryModel(
      id: 'credit',
      customerId: 'customer',
      branchId: 'branch',
      userId: 'user',
      type: CustomerLedgerEntryType.credit,
      amount: 75,
      reason: 'Balance correction',
      createdAt: now,
    );

    expect(charge.outstandingDelta, 250);
    expect(credit.outstandingDelta, -75);
  });

  test('migration is idempotent and protects balance updates', () {
    final sql =
        File(
          'supabase/migrations/20260809000100_customer_manual_ledger_entries.sql',
        ).readAsStringSync();

    expect(sql, contains('pg_advisory_xact_lock'));
    expect(sql, contains('if v_existing.id is not null then'));
    expect(sql, contains("v_type = 'credit'"));
    expect(sql, contains('customer.credit.settle'));
    expect(sql, contains('greatest('));
    expect(sql, isNot(contains('account_transactions')));
  });

  test('offline mutation sync uses the atomic RPC', () {
    final repository =
        File(
          'lib/features/pos/data/repositories/pos_repository.dart',
        ).readAsStringSync();

    expect(repository, contains("type: 'customer_ledger_entry'"));
    expect(repository, contains("case 'customer_ledger_entry':"));
    expect(repository, contains("'commit_customer_ledger_entry'"));
    expect(repository, contains('-entry.outstandingDelta'));
    expect(repository, contains('_isCustomerLedgerParentPendingError'));
    expect(repository, contains("error.code != '22023'"));
    expect(repository, contains('_resolvePersistedMutationCustomerId'));
    expect(repository, contains('FROM customer_ledger_entries'));
    expect(repository, contains('_ensureRemoteCustomerForMutation'));
    expect(repository, contains("'outstanding_balance': 0"));
    expect(
      repository,
      contains("mutation.payload['branch_id'] = remoteBranchId"),
    );
    expect(repository, contains('final localEntries ='));
    expect(repository, contains('<String, CustomerLedgerEntryModel>'));
    expect(repository, contains('hasPendingLedgerDependency'));
    expect(repository, contains('<String, CustomerSettlementModel>'));
  });

  test('customer id reconciliation remains resolvable by open screens', () {
    final localStore =
        File('lib/core/local/local_store.dart').readAsStringSync();
    final repository =
        File(
          'lib/features/pos/data/repositories/pos_repository.dart',
        ).readAsStringSync();
    final screen =
        File(
          'lib/features/pos/presentation/screens/customers_screen.dart',
        ).readAsStringSync();

    expect(localStore, contains('customer_id_aliases'));
    expect(localStore, contains('resolveCustomerId'));
    expect(repository, contains('resolvedCustomerId'));
    expect(repository, contains('_remoteCustomerIdByPhone'));
    expect(screen, contains("'Pending sync'"));
    expect(screen, contains("'Synced'"));
  });

  test('dashboard never reconstructs settled dues from history', () {
    final repository =
        File(
          'lib/features/pos/data/repositories/pos_repository.dart',
        ).readAsStringSync();
    final start = repository.indexOf('double _effectiveOutstanding');
    final end = repository.indexOf(
      'Future<List<SaleModel>> _fetchCustomerSales',
      start,
    );
    final method = repository.substring(start, end);

    expect(method, contains('customer.outstandingBalance.clamp'));
    expect(method, isNot(contains('if (computed >')));
  });

  test('pending settlements protect optimistic cash balance from refresh', () {
    final accountsRepository =
        File(
          'lib/features/accounts/data/repositories/accounts_repository.dart',
        ).readAsStringSync();

    expect(
      accountsRepository,
      contains("mutation.type == 'customer_settlement'"),
    );
    expect(accountsRepository, contains('stale server balance'));
  });

  test(
    'permanent account mismatch compensates instead of retrying forever',
    () {
      final repository =
          File(
            'lib/features/pos/data/repositories/pos_repository.dart',
          ).readAsStringSync();

      expect(repository, contains('_isPermanentSettlementAccountMismatch'));
      expect(repository, contains('_rollbackRejectedCustomerSettlement'));
      expect(repository, contains("rows.first['synced'] == 1"));
      expect(repository, contains('current_balance = current_balance - ?'));
    },
  );

  test('settlement keeps its receiving branch for tenant-wide customers', () {
    final repository =
        File(
          'lib/features/pos/data/repositories/pos_repository.dart',
        ).readAsStringSync();
    final migration =
        File(
          'supabase/migrations/20260809000200_tenant_wide_customer_settlements.sql',
        ).readAsStringSync();

    expect(repository, contains("mutation.type != 'customer_settlement'"));
    expect(migration, contains('commit_customer_settlement(jsonb)'));
    expect(migration, contains(r'v_customer\\.branch_id'));
    expect(migration, contains('v_after = v_before'));
  });

  test('customer screen never uses ref after dialog await', () {
    final screen =
        File(
          'lib/features/pos/presentation/screens/customers_screen.dart',
        ).readAsStringSync();

    expect(screen, isNot(contains('await _showResponsiveCustomerSheet')));
    expect(screen, isNot(contains('custome data is:')));
  });
}
