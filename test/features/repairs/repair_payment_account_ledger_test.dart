import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobileshop_saas/core/local/local_database.dart';
import 'package:mobileshop_saas/features/accounts/data/local/accounts_local_store.dart';
import 'package:mobileshop_saas/features/accounts/data/models/account_models.dart';
import 'package:mobileshop_saas/features/repairs/data/local/repair_payment_local_committer.dart';
import 'package:mobileshop_saas/features/repairs/data/models/repair_payment_model.dart';

const _pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');
const _tenantId = 'repair-payment-tenant';
const _branchId = 'repair-payment-branch';
const _ticketId = 'repair-payment-ticket';
const _accountId = 'repair-payment-cash';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory databaseDirectory;

  setUpAll(() async {
    databaseDirectory = Directory.systemTemp.createTempSync('repair-pay-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathProviderChannel, (call) async {
          if (call.method == 'getApplicationSupportDirectory') {
            return databaseDirectory.path;
          }
          return null;
        });
    await LocalDatabase.initialize();
    await AccountsLocalStore.saveAccount(
      const AccountModel(
        id: _accountId,
        tenantId: _tenantId,
        branchId: _branchId,
        name: 'Cash in Shop',
        currentBalance: 1000,
      ),
    );
    await LocalDatabase.execute(
      '''
      INSERT INTO repair_tickets(
        id, tenant_id, branch_id, ticket_no, customer_name, device_brand,
        device_model, fault_description, status, total_cost, created_by
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'completed', 500, ?)
      ''',
      [
        _ticketId,
        _tenantId,
        _branchId,
        'REP-1',
        'Customer',
        'Brand',
        'Model',
        'Fault',
        'owner',
      ],
    );
  });

  setUp(() async {
    await LocalDatabase.execute('DELETE FROM repair_payments');
    await LocalDatabase.execute(
      "DELETE FROM account_transactions WHERE reference_type = 'repair_payment'",
    );
    await LocalDatabase.execute(
      "UPDATE repair_tickets SET status = 'completed', total_cost = 500 WHERE id = ?",
      [_ticketId],
    );
    await LocalDatabase.execute(
      'UPDATE accounts SET current_balance = 1000 WHERE id = ?',
      [_accountId],
    );
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathProviderChannel, null);
  });

  test('payment retry increases receiving account exactly once', () async {
    final payment = _payment();
    await RepairPaymentLocalCommitter.commit(payment);
    await RepairPaymentLocalCommitter.commit(payment);

    final account = await AccountsLocalStore.loadAccountById(_accountId);
    final ledger = await LocalDatabase.select(
      "SELECT * FROM account_transactions WHERE reference_type = 'repair_payment'",
    );
    expect(account?.currentBalance, 1300);
    expect(ledger, hasLength(1));
    expect(ledger.single['source_event_key'], 'repair:payment:payment-1');
  });

  test('partial payments cannot exceed final repair charge', () async {
    await RepairPaymentLocalCommitter.commit(_payment());
    await expectLater(
      RepairPaymentLocalCommitter.commit(
        _payment(id: 'payment-2', ledgerId: 'ledger-2', amount: 201),
      ),
      throwsStateError,
    );

    expect(
      (await AccountsLocalStore.loadAccountById(_accountId))?.currentBalance,
      1300,
    );
    expect(
      await LocalDatabase.select('SELECT * FROM repair_payments'),
      hasLength(1),
    );
  });

  test('cancelled repair rejects payment without cash mutation', () async {
    await LocalDatabase.execute(
      "UPDATE repair_tickets SET status = 'cancelled' WHERE id = ?",
      [_ticketId],
    );
    await expectLater(
      RepairPaymentLocalCommitter.commit(_payment()),
      throwsStateError,
    );
    expect(
      (await AccountsLocalStore.loadAccountById(_accountId))?.currentBalance,
      1000,
    );
  });

  test('remote migration separates charge from explicit cash receipt', () {
    final sql =
        File(
          'supabase/migrations/20260728001000_repair_payment_account_ledger.sql',
        ).readAsStringSync().toLowerCase();

    expect(sql, contains('create table if not exists public.repair_payments'));
    expect(sql, contains('function public.record_repair_payment_v2'));
    expect(sql, contains("'repair.payment.create'"));
    expect(sql, contains('payment exceeds the repair balance'));
    expect(sql, contains('current_balance = current_balance + p_amount'));
    expect(sql, contains("'repair:payment:' || p_payment_id::text"));
  });
}

RepairPaymentModel _payment({
  String id = 'payment-1',
  String ledgerId = 'ledger-1',
  double amount = 300,
}) {
  return RepairPaymentModel(
    id: id,
    tenantId: _tenantId,
    branchId: _branchId,
    ticketId: _ticketId,
    amount: amount,
    method: 'cash',
    accountId: _accountId,
    ledgerTransactionId: ledgerId,
    receivedBy: 'owner',
    receivedAt: DateTime(2026, 7, 28, 17),
    createdAt: DateTime(2026, 7, 28, 17),
  );
}
