import 'package:mobileshop_saas/core/offline/offline_store.dart';
import 'package:mobileshop_saas/core/utils/offline_error_classifier.dart';
import 'package:mobileshop_saas/features/mobile_services/data/local/mobile_services_local_store.dart';
import 'package:mobileshop_saas/features/mobile_services/data/local/mobile_services_mutation_queue.dart';
import 'package:mobileshop_saas/features/mobile_services/data/models/mobile_service_commands.dart';
import 'package:mobileshop_saas/features/mobile_services/data/models/mobile_service_models.dart';
import 'package:mobileshop_saas/features/mobile_services/data/remote/mobile_services_remote_data_source.dart';
import 'package:mobileshop_saas/features/mobile_services/domain/mobile_service_types.dart';
import 'package:mobileshop_saas/features/mobile_services/domain/service_charge_calculator.dart';

class MobileServicesRepository {
  static const recordTransactionMutation = 'record_mobile_service_transaction';

  final MobileServicesRemoteDataSource _remote;
  final MobileServicesLocalDataSource _local;
  final MobileServicesMutationQueue _mutationQueue;

  MobileServicesRepository({
    MobileServicesRemoteDataSource? remote,
    MobileServicesLocalDataSource? local,
    MobileServicesMutationQueue? mutationQueue,
  }) : _remote = remote ?? SupabaseMobileServicesRemoteDataSource(),
       _local = local ?? const MobileServicesLocalStore(),
       _mutationQueue =
           mutationQueue ?? const OfflineStoreMobileServicesMutationQueue();

  Future<List<MobileServiceProviderModel>> fetchProviders(
    String branchId,
  ) async {
    try {
      final rows = await _remote.fetchProviders(branchId);
      final providers = rows.map(MobileServiceProviderModel.fromMap).toList();
      try {
        await _local.saveProviders(providers);
      } catch (_) {}
      return providers;
    } catch (error) {
      OfflineErrorClassifier.rethrowIfTerminal(error);
      return _local.loadProviders(branchId);
    }
  }

  Future<List<MobileServiceChargeRuleModel>> fetchChargeRules(
    String branchId,
  ) async {
    try {
      final rows = await _remote.fetchChargeRules(branchId);
      final rules = rows.map(MobileServiceChargeRuleModel.fromMap).toList();
      try {
        await _local.saveChargeRules(rules);
      } catch (_) {}
      return rules;
    } catch (error) {
      OfflineErrorClassifier.rethrowIfTerminal(error);
      return _local.loadChargeRules(branchId);
    }
  }

  Future<List<MobileServiceTransactionModel>> fetchTransactions(
    String branchId, {
    int limit = 80,
  }) async {
    if (limit <= 0) throw ArgumentError.value(limit, 'limit');
    try {
      final rows = await _remote.fetchTransactions(branchId, limit: limit);
      final transactions =
          rows.map(MobileServiceTransactionModel.fromMap).toList();
      try {
        for (final transaction in transactions) {
          await _local.saveTransaction(transaction);
        }
      } catch (_) {}
      return transactions;
    } catch (error) {
      OfflineErrorClassifier.rethrowIfTerminal(error);
      return _local.loadTransactions(branchId, limit: limit);
    }
  }

  MobileServiceTransactionPreview buildPreview({
    required MobileServiceOperation operation,
    required double serviceAmount,
    required MobileServiceChargeRuleModel rule,
    double? chargedFeeOverride,
  }) {
    if (rule.operation != operation) {
      throw ArgumentError('The selected charge rule has another operation.');
    }
    if (!rule.isActive) {
      throw StateError('The selected charge rule is archived.');
    }
    return ServiceChargeCalculator.buildPreview(
      operation: operation,
      serviceAmount: serviceAmount,
      rule: rule.toDomainRule(),
      chargedFeeOverride: chargedFeeOverride,
    );
  }

  Future<String> saveProvider(SaveMobileServiceProviderCommand command) {
    return _remote.invokeUuidRpc(
      'save_mobile_service_provider',
      command.toRpcParams(),
    );
  }

  Future<String> saveChargeRule(SaveMobileServiceChargeRuleCommand command) {
    return _remote.invokeUuidRpc(
      'save_mobile_service_charge_rule',
      command.toRpcParams(),
    );
  }

  Future<MobileServiceTransactionModel> recordTransaction(
    RecordMobileServiceTransactionCommand command, {
    String? queueForUserId,
    MobileServiceProviderModel? provider,
    MobileServiceChargeRuleModel? rule,
  }) async {
    try {
      final transaction = await _sendTransaction(command.toRpcParams());
      await _local.saveTransaction(transaction);
      return transaction;
    } catch (error) {
      if (queueForUserId == null) rethrow;
      OfflineErrorClassifier.rethrowIfTerminal(error);
      if (provider == null || rule == null) {
        throw StateError(
          'Provider and charge rule are required for an offline transaction.',
        );
      }

      final pending = _buildPendingTransaction(
        command: command,
        userId: queueForUserId,
        provider: provider,
        rule: rule,
      );
      await _local.applyPendingTransaction(pending);
      await _mutationQueue.enqueue(
        userId: queueForUserId,
        type: recordTransactionMutation,
        payload: command.toRpcParams(),
      );
      throw MobileServiceQueuedOfflineException(
        transactionId: command.transactionId,
        cause: error,
      );
    }
  }

  Future<MobileServiceTransactionModel> voidTransaction(
    VoidMobileServiceTransactionCommand command,
  ) async {
    final id = await _remote.invokeUuidRpc(
      'void_mobile_service_transaction',
      command.toRpcParams(),
    );
    final row = await _remote.fetchTransactionById(id);
    final transaction = MobileServiceTransactionModel.fromMap(row);
    await _local.saveTransaction(transaction);
    return transaction;
  }

  Future<void> archiveProvider(String providerId) async {
    await _remote.invokeVoidRpc('archive_mobile_service_provider', {
      'p_provider_id': providerId,
    });
  }

  Future<void> restoreProvider(String providerId) async {
    await _remote.invokeVoidRpc('restore_mobile_service_provider', {
      'p_provider_id': providerId,
    });
  }

  Future<void> archiveChargeRule(String ruleId) async {
    await _remote.invokeVoidRpc('archive_mobile_service_charge_rule', {
      'p_rule_id': ruleId,
    });
  }

  Future<void> restoreChargeRule(String ruleId) async {
    await _remote.invokeVoidRpc('restore_mobile_service_charge_rule', {
      'p_rule_id': ruleId,
    });
  }

  Future<MobileServiceReportSummary> fetchReportSummary({
    required String branchId,
    required DateTime from,
    required DateTime to,
    String? providerId,
  }) async {
    final map = await _remote.invokeMapRpc('mobile_service_report_summary', {
      'p_branch_id': branchId,
      'p_from': from.toIso8601String(),
      'p_to': to.toIso8601String(),
      'p_provider_id': providerId,
    });
    return MobileServiceReportSummary.fromMap(map);
  }

  Future<MobileServiceProfitSummary> fetchProfitSummary({
    required String branchId,
    required DateTime dayStart,
    required DateTime dayEnd,
  }) async {
    try {
      final map = await _remote.invokeMapRpc('mobile_service_profit_summary', {
        'p_branch_id': branchId,
        'p_day_start': dayStart.toIso8601String(),
        'p_day_end': dayEnd.toIso8601String(),
      });
      return MobileServiceProfitSummary.fromMap(map);
    } catch (error) {
      OfflineErrorClassifier.rethrowIfTerminal(error);
      return _local.loadProfitSummary(
        branchId: branchId,
        dayStart: dayStart,
        dayEnd: dayEnd,
      );
    }
  }

  Future<void> syncOfflineMutations(String userId) async {
    final snapshot = await _mutationQueue.load(userId);
    if (snapshot.isEmpty) return;

    final remaining = <OfflineMutation>[];
    Object? firstError;

    for (final mutation in snapshot) {
      if (mutation.type != recordTransactionMutation) {
        remaining.add(mutation);
        continue;
      }

      try {
        final transaction = await _sendTransaction(mutation.payload);
        await _local.saveTransaction(transaction);
      } catch (error) {
        remaining.add(mutation);
        firstError ??= error;
      }
    }

    await _mutationQueue.saveSyncResult(
      userId: userId,
      snapshot: snapshot,
      remaining: remaining,
    );

    if (firstError != null) {
      throw Exception(
        'Mobile-service transactions could not sync: $firstError',
      );
    }
  }

  Future<MobileServiceTransactionModel> _sendTransaction(
    Map<String, dynamic> params,
  ) async {
    final id = await _remote.invokeUuidRpc(
      'record_mobile_service_transaction',
      params,
    );
    final row = await _remote.fetchTransactionById(id);
    return MobileServiceTransactionModel.fromMap(row);
  }

  MobileServiceTransactionModel _buildPendingTransaction({
    required RecordMobileServiceTransactionCommand command,
    required String userId,
    required MobileServiceProviderModel provider,
    required MobileServiceChargeRuleModel rule,
  }) {
    if (!provider.isActive ||
        provider.id != command.providerId ||
        provider.branchId != rule.branchId ||
        provider.tenantId != rule.tenantId ||
        provider.id != rule.providerId) {
      throw StateError('Provider and rule do not match the transaction.');
    }

    final preview = buildPreview(
      operation: command.operation,
      serviceAmount: command.serviceAmount,
      rule: rule,
      chargedFeeOverride: command.chargedFee,
    );
    final now = DateTime.now();

    return MobileServiceTransactionModel(
      id: command.transactionId,
      tenantId: provider.tenantId,
      branchId: provider.branchId,
      providerId: provider.id,
      chargeRuleId: rule.id,
      serviceCategory: provider.category,
      operation: command.operation,
      serviceAmount: preview.serviceAmount,
      calculationMethod: rule.calculationMethod,
      appliedRate: rule.rateAmount,
      appliedPerAmount: rule.perAmount,
      calculatedFee: preview.calculatedFee,
      chargedFee: preview.chargedFee,
      customerCashAmount: preview.customerCashAmount,
      profitAmount: preview.profitAmount,
      cashAccountId: command.cashAccountId,
      providerAccountId: provider.providerAccountId,
      cashLedgerTransactionId: command.cashLedgerTransactionId,
      providerLedgerTransactionId: command.providerLedgerTransactionId,
      phoneNumber: command.phoneNumber,
      referenceNumber: command.referenceNumber,
      description: command.description,
      status: MobileServiceTransactionStatus.pendingSync,
      transactionAt: command.transactionAt,
      createdBy: userId,
      createdAt: now,
    );
  }
}

class MobileServiceQueuedOfflineException implements Exception {
  final String transactionId;
  final Object cause;

  const MobileServiceQueuedOfflineException({
    required this.transactionId,
    required this.cause,
  });

  @override
  String toString() {
    return 'Transaction $transactionId was queued for sync.';
  }
}
