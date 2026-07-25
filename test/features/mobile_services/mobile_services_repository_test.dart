import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobileshop_saas/core/offline/offline_store.dart';
import 'package:mobileshop_saas/features/mobile_services/data/local/mobile_services_local_store.dart';
import 'package:mobileshop_saas/features/mobile_services/data/local/mobile_services_mutation_queue.dart';
import 'package:mobileshop_saas/features/mobile_services/data/models/mobile_service_commands.dart';
import 'package:mobileshop_saas/features/mobile_services/data/models/mobile_service_models.dart';
import 'package:mobileshop_saas/features/mobile_services/data/remote/mobile_services_remote_data_source.dart';
import 'package:mobileshop_saas/features/mobile_services/data/repositories/mobile_services_repository.dart';
import 'package:mobileshop_saas/features/mobile_services/domain/mobile_service_types.dart';

void main() {
  late _FakeRemote remote;
  late _FakeLocal local;
  late _FakeMutationQueue mutationQueue;
  late MobileServicesRepository repository;

  setUp(() {
    remote = _FakeRemote();
    local = _FakeLocal();
    mutationQueue = _FakeMutationQueue();
    repository = MobileServicesRepository(
      remote: remote,
      local: local,
      mutationQueue: mutationQueue,
    );
  });

  test('fetch providers converts remote rows to typed models', () async {
    remote.providers = [_providerMap()];

    final providers = await repository.fetchProviders('branch-1');

    expect(providers, hasLength(1));
    expect(providers.single.code, MobileServiceProviderCode.easypaisa);
    expect(remote.lastBranchId, 'branch-1');
    expect(local.providers, hasLength(1));
  });

  test('fetch providers falls back to the branch cache', () async {
    remote.error = TimeoutException('offline');
    local.providers = [MobileServiceProviderModel.fromMap(_providerMap())];

    final providers = await repository.fetchProviders('branch-1');

    expect(providers.single.code, MobileServiceProviderCode.easypaisa);
    expect(local.lastBranchId, 'branch-1');
  });

  test('repository builds preview only with matching active rule', () {
    final rule = MobileServiceChargeRuleModel.fromMap(_ruleMap());

    final preview = repository.buildPreview(
      operation: MobileServiceOperation.send,
      serviceAmount: 800,
      rule: rule,
    );

    expect(preview.calculatedFee, 20);
    expect(preview.customerCashAmount, 820);

    expect(
      () => repository.buildPreview(
        operation: MobileServiceOperation.receive,
        serviceAmount: 800,
        rule: rule,
      ),
      throwsArgumentError,
    );
  });

  test('record transaction sends stable IDs then fetches saved row', () async {
    remote.transaction = _transactionMap();
    final command = RecordMobileServiceTransactionCommand(
      transactionId: 'transaction-1',
      cashLedgerTransactionId: 'cash-ledger-1',
      providerLedgerTransactionId: 'wallet-ledger-1',
      providerId: 'provider-1',
      cashAccountId: 'cash-1',
      operation: MobileServiceOperation.send,
      serviceAmount: 800,
      chargedFee: 15,
      transactionAt: _transactionTime,
    );

    final transaction = await repository.recordTransaction(command);

    expect(remote.lastFunctionName, 'record_mobile_service_transaction');
    expect(remote.lastParams?['p_transaction_id'], 'transaction-1');
    expect(remote.lastParams?['p_cash_ledger_transaction_id'], 'cash-ledger-1');
    expect(remote.lastParams?['p_charged_fee'], 15);
    expect(transaction.id, 'transaction-1');
  });

  test('archive uses a void RPC and never directly edits a table', () async {
    await repository.archiveProvider('provider-1');

    expect(remote.lastFunctionName, 'archive_mobile_service_provider');
    expect(remote.lastParams, {'p_provider_id': 'provider-1'});
    expect(remote.voidRpcCalls, 1);
  });

  test('report JSON is converted to a typed summary', () async {
    remote.mapResult = {
      'transaction_count': 3,
      'send_count': 2,
      'receive_count': 1,
      'sent_amount': '1800.00',
      'received_amount': '800.00',
      'customer_cash_in': '1840.00',
      'customer_cash_out': '780.00',
      'profit': '60.00',
    };

    final report = await repository.fetchReportSummary(
      branchId: 'branch-1',
      from: DateTime.utc(2026, 7, 25),
      to: DateTime.utc(2026, 7, 26),
    );

    expect(report.transactionCount, 3);
    expect(report.sentAmount, 1800);
    expect(report.profit, 60);
    expect(remote.lastFunctionName, 'mobile_service_report_summary');
  });

  test('failed transaction is queued with the same stable IDs', () async {
    remote.error = TimeoutException('offline');
    final provider = MobileServiceProviderModel.fromMap(_providerMap());
    final rule = MobileServiceChargeRuleModel.fromMap(_ruleMap());
    final command = RecordMobileServiceTransactionCommand(
      transactionId: 'offline-transaction-1',
      cashLedgerTransactionId: 'offline-cash-ledger-1',
      providerLedgerTransactionId: 'offline-wallet-ledger-1',
      providerId: 'provider-1',
      cashAccountId: 'cash-1',
      operation: MobileServiceOperation.send,
      serviceAmount: 800,
      transactionAt: _transactionTime,
    );

    await expectLater(
      repository.recordTransaction(
        command,
        queueForUserId: 'user-1',
        provider: provider,
        rule: rule,
      ),
      throwsA(
        isA<MobileServiceQueuedOfflineException>().having(
          (error) => error.transactionId,
          'transactionId',
          'offline-transaction-1',
        ),
      ),
    );

    expect(mutationQueue.mutations, hasLength(1));
    expect(local.transactions.single.isPendingSync, isTrue);
    expect(
      mutationQueue.mutations.single.payload['p_transaction_id'],
      'offline-transaction-1',
    );
  });

  test(
    'sync sends only mobile-service mutations and preserves others',
    () async {
      mutationQueue.mutations = [
        OfflineMutation(
          id: 'mobile-mutation',
          type: MobileServicesRepository.recordTransactionMutation,
          payload: {
            'p_transaction_id': 'transaction-1',
            'p_cash_ledger_transaction_id': 'cash-ledger-1',
            'p_provider_ledger_transaction_id': 'wallet-ledger-1',
          },
          createdAt: _transactionTime,
        ),
        OfflineMutation(
          id: 'other-mutation',
          type: 'upsert_account',
          payload: const {},
          createdAt: _transactionTime,
        ),
      ];
      remote.transaction = _transactionMap();

      await repository.syncOfflineMutations('user-1');

      expect(local.transactions, hasLength(1));
      expect(mutationQueue.mutations, hasLength(1));
      expect(mutationQueue.mutations.single.id, 'other-mutation');
    },
  );
}

final _transactionTime = DateTime.utc(2026, 7, 25, 11);

class _FakeRemote implements MobileServicesRemoteDataSource {
  List<Map<String, dynamic>> providers = [];
  List<Map<String, dynamic>> rules = [];
  List<Map<String, dynamic>> transactions = [];
  Map<String, dynamic> transaction = {};
  Map<String, dynamic> mapResult = {};
  String? lastBranchId;
  String? lastFunctionName;
  Map<String, dynamic>? lastParams;
  int voidRpcCalls = 0;
  Object? error;

  void _throwIfNeeded() {
    final value = error;
    if (value != null) throw value;
  }

  @override
  Future<List<Map<String, dynamic>>> fetchProviders(String branchId) async {
    _throwIfNeeded();
    lastBranchId = branchId;
    return providers;
  }

  @override
  Future<List<Map<String, dynamic>>> fetchChargeRules(String branchId) async {
    _throwIfNeeded();
    lastBranchId = branchId;
    return rules;
  }

  @override
  Future<List<Map<String, dynamic>>> fetchTransactions(
    String branchId, {
    required int limit,
  }) async {
    _throwIfNeeded();
    lastBranchId = branchId;
    return transactions;
  }

  @override
  Future<Map<String, dynamic>> fetchTransactionById(
    String transactionId,
  ) async {
    _throwIfNeeded();
    return transaction;
  }

  @override
  Future<Map<String, dynamic>> invokeMapRpc(
    String functionName,
    Map<String, dynamic> params,
  ) async {
    _throwIfNeeded();
    lastFunctionName = functionName;
    lastParams = params;
    return mapResult;
  }

  @override
  Future<String> invokeUuidRpc(
    String functionName,
    Map<String, dynamic> params,
  ) async {
    _throwIfNeeded();
    lastFunctionName = functionName;
    lastParams = params;
    return params['p_transaction_id'] as String? ?? 'saved-id';
  }

  @override
  Future<void> invokeVoidRpc(
    String functionName,
    Map<String, dynamic> params,
  ) async {
    _throwIfNeeded();
    lastFunctionName = functionName;
    lastParams = params;
    voidRpcCalls++;
  }
}

class _FakeLocal implements MobileServicesLocalDataSource {
  List<MobileServiceProviderModel> providers = [];
  List<MobileServiceChargeRuleModel> rules = [];
  List<MobileServiceTransactionModel> transactions = [];
  String? lastBranchId;

  @override
  Future<List<MobileServiceProviderModel>> loadProviders(
    String branchId,
  ) async {
    lastBranchId = branchId;
    return providers;
  }

  @override
  Future<void> saveProviders(List<MobileServiceProviderModel> providers) async {
    this.providers = providers;
  }

  @override
  Future<List<MobileServiceChargeRuleModel>> loadChargeRules(
    String branchId,
  ) async {
    lastBranchId = branchId;
    return rules;
  }

  @override
  Future<void> saveChargeRules(List<MobileServiceChargeRuleModel> rules) async {
    this.rules = rules;
  }

  @override
  Future<List<MobileServiceTransactionModel>> loadTransactions(
    String branchId, {
    required int limit,
  }) async {
    lastBranchId = branchId;
    return transactions.take(limit).toList();
  }

  @override
  Future<void> saveTransaction(
    MobileServiceTransactionModel transaction,
  ) async {
    transactions.removeWhere((item) => item.id == transaction.id);
    transactions.add(transaction);
  }

  @override
  Future<void> applyPendingTransaction(
    MobileServiceTransactionModel transaction,
  ) async {
    await saveTransaction(transaction);
  }
}

class _FakeMutationQueue implements MobileServicesMutationQueue {
  List<OfflineMutation> mutations = [];

  @override
  Future<void> enqueue({
    required String userId,
    required String type,
    required Map<String, dynamic> payload,
  }) async {
    mutations.add(
      OfflineMutation(
        id: 'queued-${mutations.length + 1}',
        type: type,
        payload: payload,
        createdAt: _transactionTime,
      ),
    );
  }

  @override
  Future<List<OfflineMutation>> load(String userId) async {
    return List.of(mutations);
  }

  @override
  Future<void> saveSyncResult({
    required String userId,
    required List<OfflineMutation> snapshot,
    required List<OfflineMutation> remaining,
  }) async {
    mutations = List.of(remaining);
  }
}

Map<String, dynamic> _providerMap() => {
  'id': 'provider-1',
  'tenant_id': 'tenant-1',
  'branch_id': 'branch-1',
  'category': 'money_transfer',
  'code': 'easypaisa',
  'name': 'Main Easypaisa',
  'provider_account_id': 'wallet-1',
  'is_active': true,
  'created_by': 'user-1',
  'created_at': '2026-07-25T10:00:00Z',
  'updated_at': '2026-07-25T10:00:00Z',
};

Map<String, dynamic> _ruleMap() => {
  'id': 'rule-1',
  'tenant_id': 'tenant-1',
  'branch_id': 'branch-1',
  'provider_id': 'provider-1',
  'operation': 'send',
  'calculation_method': 'full_slab',
  'rate_amount': 20,
  'per_amount': 1000,
  'minimum_fee': null,
  'maximum_fee': null,
  'is_active': true,
  'created_by': 'user-1',
  'created_at': '2026-07-25T10:00:00Z',
  'updated_at': '2026-07-25T10:00:00Z',
};

Map<String, dynamic> _transactionMap() => {
  'id': 'transaction-1',
  'tenant_id': 'tenant-1',
  'branch_id': 'branch-1',
  'provider_id': 'provider-1',
  'charge_rule_id': 'rule-1',
  'service_category': 'money_transfer',
  'operation': 'send',
  'service_amount': 800,
  'calculation_method': 'full_slab',
  'applied_rate': 20,
  'applied_per_amount': 1000,
  'calculated_fee': 20,
  'charged_fee': 15,
  'customer_cash_amount': 815,
  'profit_amount': 15,
  'cash_account_id': 'cash-1',
  'provider_account_id': 'wallet-1',
  'cash_ledger_transaction_id': 'cash-ledger-1',
  'provider_ledger_transaction_id': 'wallet-ledger-1',
  'status': 'completed',
  'transaction_at': '2026-07-25T11:00:00Z',
  'created_by': 'user-1',
  'created_at': '2026-07-25T11:00:01Z',
};
