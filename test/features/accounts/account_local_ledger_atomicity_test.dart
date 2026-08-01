import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobileshop_saas/core/local/local_database.dart';
import 'package:mobileshop_saas/features/accounts/data/local/accounts_local_store.dart';
import 'package:mobileshop_saas/features/accounts/data/models/account_models.dart';

const _tenantId = 'ledger-atomicity-tenant';
const _branchId = 'ledger-atomicity-branch';
const _cashAccountId = 'ledger-atomicity-cash';
const _walletAccountId = 'ledger-atomicity-wallet';
const _pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late String store;
  late Directory databaseDirectory;

  setUpAll(() async {
    databaseDirectory = Directory.systemTemp.createTempSync(
      'mobileshop-ledger-atomicity-',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathProviderChannel, (call) async {
          if (call.method == 'getApplicationSupportDirectory') {
            return databaseDirectory.path;
          }
          return null;
        });

    store =
        File(
          'lib/features/accounts/data/local/accounts_local_store.dart',
        ).readAsStringSync();

    await LocalDatabase.initialize();
    await LocalDatabase.execute('PRAGMA foreign_keys = OFF');
    try {
      await AccountsLocalStore.saveAccount(
        const AccountModel(
          id: _cashAccountId,
          tenantId: _tenantId,
          branchId: _branchId,
          name: 'Atomicity Cash',
        ),
      );
      await AccountsLocalStore.saveAccount(
        const AccountModel(
          id: _walletAccountId,
          tenantId: _tenantId,
          branchId: _branchId,
          name: 'Atomicity Wallet',
          type: AccountType.mobileWallet,
        ),
      );
    } finally {
      await LocalDatabase.execute('PRAGMA foreign_keys = ON');
    }
  });

  setUp(() async {
    await LocalDatabase.deleteRows(
      table: 'account_transactions',
      whereColumn: 'branch_id',
      equals: _branchId,
    );
    await LocalDatabase.execute(
      '''
      UPDATE accounts
      SET opening_balance = 0, current_balance = 0
      WHERE id IN (?, ?)
      ''',
      [_cashAccountId, _walletAccountId],
    );
  });

  test(
    'account names are matched across case, spacing, and inactive rows',
    () async {
      const inactiveId = 'ledger-inactive-duplicate-name';
      await AccountsLocalStore.saveAccount(
        const AccountModel(
          id: inactiveId,
          tenantId: _tenantId,
          branchId: _branchId,
          name: '  Reserve   Wallet  ',
          isActive: false,
        ),
      );
      try {
        expect(
          await AccountsLocalStore.accountNameExists(
            branchId: _branchId,
            name: 'reserve wallet',
          ),
          isTrue,
        );
        expect(
          await AccountsLocalStore.accountNameExists(
            branchId: _branchId,
            name: 'RESERVE     WALLET',
            excludingAccountId: inactiveId,
          ),
          isFalse,
        );
      } finally {
        await LocalDatabase.deleteRowById(table: 'accounts', id: inactiveId);
      }
    },
  );

  test('safe cash cleanup hides only an empty duplicate', () async {
    const keeperId = 'cash-cleanup-keeper';
    const emptyDuplicateId = 'cash-cleanup-empty';
    const fundedDuplicateId = 'cash-cleanup-funded';
    final accounts = [
      const AccountModel(
        id: keeperId,
        tenantId: _tenantId,
        branchId: _branchId,
        name: 'Cash in Shop',
        isDefault: true,
      ),
      const AccountModel(
        id: emptyDuplicateId,
        tenantId: _tenantId,
        branchId: _branchId,
        name: ' cash   IN shop ',
      ),
      const AccountModel(
        id: fundedDuplicateId,
        tenantId: _tenantId,
        branchId: _branchId,
        name: 'CASH IN SHOP',
        currentBalance: 50,
      ),
    ];
    for (final account in accounts) {
      await AccountsLocalStore.saveAccount(account);
    }
    try {
      final cleaned =
          await AccountsLocalStore.deactivateSafeDuplicateCashAccounts(
            _branchId,
          );
      expect(cleaned.map((account) => account.id), [emptyDuplicateId]);
      expect(
        (await AccountsLocalStore.loadAccountById(emptyDuplicateId))!.isActive,
        isFalse,
      );
      expect(
        (await AccountsLocalStore.loadAccountById(fundedDuplicateId))!.isActive,
        isTrue,
      );
    } finally {
      for (final account in accounts) {
        await LocalDatabase.deleteRowById(table: 'accounts', id: account.id);
      }
    }
  });

  tearDownAll(() async {
    await LocalDatabase.deleteRows(
      table: 'account_transactions',
      whereColumn: 'branch_id',
      equals: _branchId,
    );
    await LocalDatabase.deleteRowById(table: 'accounts', id: _cashAccountId);
    await LocalDatabase.deleteRowById(table: 'accounts', id: _walletAccountId);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathProviderChannel, null);
  });

  test('single ledger application is atomic and duplicate-safe', () {
    final applyTransaction = _between(
      store,
      'static Future<void> applyTransaction(',
      'static Future<void> applyTransfer(',
    );

    expect(applyTransaction, contains('LocalDatabase.runInTransaction'));
    expect(applyTransaction, contains('_transactionExists(transaction.id)'));
    expect(
      applyTransaction,
      contains('_requireAccount(transaction.accountId)'),
    );
    expect(applyTransaction, contains('_insertTransaction(transaction)'));
    expect(applyTransaction, contains('updateAccountBalance('));
    expect(applyTransaction, isNot(contains('saveTransaction(transaction)')));
  });

  test('transfer applies both legs and balances in one transaction', () {
    final applyTransfer = _between(
      store,
      'static Future<void> applyTransfer(',
      'static Future<bool> _transactionExists(',
    );

    expect(applyTransfer, contains('LocalDatabase.runInTransaction'));
    expect(applyTransfer, contains('_insertTransaction(outgoing)'));
    expect(applyTransfer, contains('_insertTransaction(incoming)'));
    expect(
      RegExp('updateAccountBalance\\(').allMatches(applyTransfer),
      hasLength(2),
    );
  });

  test('transfer retry and partial local state are handled explicitly', () {
    final applyTransfer = _between(
      store,
      'static Future<void> applyTransfer(',
      'static Future<bool> _transactionExists(',
    );

    expect(applyTransfer, contains('if (outgoingExists && incomingExists)'));
    expect(applyTransfer, contains('if (outgoingExists != incomingExists)'));
    expect(
      applyTransfer,
      contains(
        'Local account transfer is incomplete and requires reconciliation.',
      ),
    );
  });

  test('financial application uses insert-only ledger semantics', () {
    final insertTransaction = _between(
      store,
      'static Future<void> _insertTransaction(',
      'static Future<void> updateAccountBalance(',
    );

    expect(insertTransaction, contains('INSERT INTO account_transactions'));
    expect(insertTransaction, isNot(contains('OR REPLACE')));
  });

  test('replaying the same transaction changes its balance once', () async {
    final transaction = _transaction(
      id: 'ledger-atomicity-entry',
      accountId: _cashAccountId,
      direction: AccountTransactionDirection.moneyIn,
      amount: 100,
    );

    await AccountsLocalStore.applyTransaction(transaction);
    await AccountsLocalStore.applyTransaction(transaction);

    expect(await _balance(_cashAccountId), 100);
    expect(await _transactionCount(transaction.id), 1);
  });

  test('replaying the same transfer changes each balance once', () async {
    await _setBalance(_cashAccountId, 100);
    final transfer = _transfer();

    await AccountsLocalStore.applyTransfer(
      outgoing: transfer.outgoing,
      incoming: transfer.incoming,
    );
    await AccountsLocalStore.applyTransfer(
      outgoing: transfer.outgoing,
      incoming: transfer.incoming,
    );

    expect(await _balance(_cashAccountId), 70);
    expect(await _balance(_walletAccountId), 30);
    expect(await _transactionCount(transfer.outgoing.id), 1);
    expect(await _transactionCount(transfer.incoming.id), 1);
  });

  test(
    'one pre-existing transfer leg blocks mutation for reconciliation',
    () async {
      await _setBalance(_cashAccountId, 100);
      final transfer = _transfer();
      await AccountsLocalStore.saveTransaction(transfer.incoming);

      await expectLater(
        AccountsLocalStore.applyTransfer(
          outgoing: transfer.outgoing,
          incoming: transfer.incoming,
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'Local account transfer is incomplete and requires reconciliation.',
          ),
        ),
      );

      expect(await _balance(_cashAccountId), 100);
      expect(await _balance(_walletAccountId), 0);
      expect(await _transactionCount(transfer.outgoing.id), 0);
      expect(await _transactionCount(transfer.incoming.id), 1);
    },
  );

  test('insufficient source balance is rejected before mutation', () async {
    await _setBalance(_cashAccountId, 20);
    final transfer = _transfer();

    await expectLater(
      AccountsLocalStore.applyTransfer(
        outgoing: transfer.outgoing,
        incoming: transfer.incoming,
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'Insufficient source account balance.',
        ),
      ),
    );

    expect(await _balance(_cashAccountId), 20);
    expect(await _balance(_walletAccountId), 0);
    expect(await _transactionCount(transfer.outgoing.id), 0);
  });

  test('mismatched transfer legs are rejected before mutation', () async {
    await _setBalance(_cashAccountId, 100);
    final transfer = _transfer(incomingAmount: 29);

    await expectLater(
      AccountsLocalStore.applyTransfer(
        outgoing: transfer.outgoing,
        incoming: transfer.incoming,
      ),
      throwsA(isA<ArgumentError>()),
    );

    expect(await _balance(_cashAccountId), 100);
    expect(await _balance(_walletAccountId), 0);
    expect(await _transactionCount(transfer.outgoing.id), 0);
  });

  test(
    'same source event with a different UUID changes balance once',
    () async {
      final first = _transaction(
        id: 'ledger-source-first',
        accountId: _cashAccountId,
        direction: AccountTransactionDirection.moneyIn,
        amount: 80,
        sourceEventKey: 'pos:sale-1:cash',
      );
      final replay = _transaction(
        id: 'ledger-source-replay',
        accountId: _cashAccountId,
        direction: AccountTransactionDirection.moneyIn,
        amount: 80,
        sourceEventKey: 'pos:sale-1:cash',
      );

      await AccountsLocalStore.applyTransaction(first);
      await AccountsLocalStore.applyTransaction(replay);

      expect(await _balance(_cashAccountId), 80);
      expect(await _transactionCount(first.id), 1);
      expect(await _transactionCount(replay.id), 0);
    },
  );

  test('valid reversal restores balance and records its original', () async {
    final original = _transaction(
      id: 'ledger-reversal-original',
      accountId: _cashAccountId,
      direction: AccountTransactionDirection.moneyIn,
      amount: 60,
      sourceEventKey: 'expense-refund:original',
    );
    final reversal = _transaction(
      id: 'ledger-reversal-entry',
      accountId: _cashAccountId,
      direction: AccountTransactionDirection.moneyOut,
      amount: 60,
      sourceEventKey: 'expense-refund:reversal',
      reversalOfTransactionId: original.id,
    );

    await AccountsLocalStore.applyTransaction(original);
    await AccountsLocalStore.applyTransaction(reversal);

    expect(await _balance(_cashAccountId), 0);
    expect(await _reversalTarget(reversal.id), original.id);
  });

  test('invalid reversal amount is rejected without balance change', () async {
    final original = _transaction(
      id: 'ledger-invalid-reversal-original',
      accountId: _cashAccountId,
      direction: AccountTransactionDirection.moneyIn,
      amount: 60,
    );
    final reversal = _transaction(
      id: 'ledger-invalid-reversal-entry',
      accountId: _cashAccountId,
      direction: AccountTransactionDirection.moneyOut,
      amount: 59,
      reversalOfTransactionId: original.id,
    );

    await AccountsLocalStore.applyTransaction(original);
    await expectLater(
      AccountsLocalStore.applyTransaction(reversal),
      throwsA(isA<StateError>()),
    );

    expect(await _balance(_cashAccountId), 60);
    expect(await _transactionCount(reversal.id), 0);
  });

  test('reconciliation matches opening balance plus ledger movement', () async {
    await _setOpeningAndCurrentBalance(_cashAccountId, 100);
    await AccountsLocalStore.applyTransaction(
      _transaction(
        id: 'ledger-reconcile-in',
        accountId: _cashAccountId,
        direction: AccountTransactionDirection.moneyIn,
        amount: 40,
      ),
    );
    await AccountsLocalStore.applyTransaction(
      _transaction(
        id: 'ledger-reconcile-out',
        accountId: _cashAccountId,
        direction: AccountTransactionDirection.moneyOut,
        amount: 25,
      ),
    );

    final reconciliation = (await AccountsLocalStore.reconcileBranch(
      _branchId,
    )).firstWhere((entry) => entry.accountId == _cashAccountId);

    expect(reconciliation.openingBalance, 100);
    expect(reconciliation.expectedBalance, 115);
    expect(reconciliation.storedBalance, 115);
    expect(reconciliation.difference, 0);
    expect(reconciliation.isReconciled, isTrue);
    expect(reconciliation.ledgerEntryCount, 2);
  });

  test('reconciliation reports discrepancy without repairing it', () async {
    await _setOpeningAndCurrentBalance(_cashAccountId, 100);
    await _setBalance(_cashAccountId, 117);

    final reconciliation = (await AccountsLocalStore.reconcileBranch(
      _branchId,
    )).firstWhere((entry) => entry.accountId == _cashAccountId);

    expect(reconciliation.expectedBalance, 100);
    expect(reconciliation.storedBalance, 117);
    expect(reconciliation.difference, 17);
    expect(reconciliation.isReconciled, isFalse);
    expect(await _balance(_cashAccountId), 117);
  });
}

String _between(String source, String start, String end) {
  final startIndex = source.indexOf(start);
  final endIndex = source.indexOf(end, startIndex + start.length);
  expect(startIndex, greaterThanOrEqualTo(0), reason: 'Missing start: $start');
  expect(endIndex, greaterThan(startIndex), reason: 'Missing end: $end');
  return source.substring(startIndex, endIndex);
}

AccountTransactionModel _transaction({
  required String id,
  required String accountId,
  required AccountTransactionDirection direction,
  required double amount,
  AccountTransactionType type = AccountTransactionType.adjustment,
  String? relatedAccountId,
  String? transferGroupId,
  String? sourceEventKey,
  String? reversalOfTransactionId,
}) {
  return AccountTransactionModel(
    id: id,
    tenantId: _tenantId,
    branchId: _branchId,
    accountId: accountId,
    relatedAccountId: relatedAccountId,
    transferGroupId: transferGroupId,
    type: type,
    direction: direction,
    amount: amount,
    sourceEventKey: sourceEventKey,
    reversalOfTransactionId: reversalOfTransactionId,
    transactionAt: DateTime.utc(2026, 7, 27),
  );
}

({AccountTransactionModel outgoing, AccountTransactionModel incoming})
_transfer({double incomingAmount = 30}) {
  const groupId = 'ledger-atomicity-transfer';
  return (
    outgoing: _transaction(
      id: 'ledger-atomicity-transfer-out',
      accountId: _cashAccountId,
      relatedAccountId: _walletAccountId,
      transferGroupId: groupId,
      type: AccountTransactionType.transferOut,
      direction: AccountTransactionDirection.moneyOut,
      amount: 30,
    ),
    incoming: _transaction(
      id: 'ledger-atomicity-transfer-in',
      accountId: _walletAccountId,
      relatedAccountId: _cashAccountId,
      transferGroupId: groupId,
      type: AccountTransactionType.transferIn,
      direction: AccountTransactionDirection.moneyIn,
      amount: incomingAmount,
    ),
  );
}

Future<double> _balance(String accountId) async {
  final rows = await LocalDatabase.select(
    'SELECT current_balance FROM accounts WHERE id = ?',
    [accountId],
  );
  return (rows.single['current_balance'] as num).toDouble();
}

Future<void> _setBalance(String accountId, double balance) {
  return LocalDatabase.execute(
    'UPDATE accounts SET current_balance = ? WHERE id = ?',
    [balance, accountId],
  );
}

Future<void> _setOpeningAndCurrentBalance(String accountId, double balance) {
  return LocalDatabase.execute(
    '''
    UPDATE accounts
    SET opening_balance = ?, current_balance = ?
    WHERE id = ?
    ''',
    [balance, balance, accountId],
  );
}

Future<int> _transactionCount(String transactionId) async {
  final rows = await LocalDatabase.select(
    'SELECT COUNT(*) AS total FROM account_transactions WHERE id = ?',
    [transactionId],
  );
  return (rows.single['total'] as num).toInt();
}

Future<String?> _reversalTarget(String transactionId) async {
  final rows = await LocalDatabase.select(
    '''
    SELECT reversal_of_transaction_id
    FROM account_transactions
    WHERE id = ?
    ''',
    [transactionId],
  );
  return rows.single['reversal_of_transaction_id'] as String?;
}
