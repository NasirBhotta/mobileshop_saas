import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:mobileshop_saas/features/accounts/presentation/providers/accounts_provider.dart';
import 'package:mobileshop_saas/features/dashboard/presentation/providers/dashboard_provider.dart';
import 'package:mobileshop_saas/features/mobile_services/data/models/mobile_service_commands.dart';
import 'package:mobileshop_saas/features/mobile_services/data/models/mobile_service_models.dart';
import 'package:mobileshop_saas/features/mobile_services/data/repositories/mobile_services_repository.dart';
import 'package:mobileshop_saas/features/mobile_services/domain/mobile_service_types.dart';
import 'package:mobileshop_saas/features/onboarding/data/repositories/setup_flow_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final mobileServicesRepositoryProvider = Provider<MobileServicesRepository>((
  ref,
) {
  return MobileServicesRepository();
});

final mobileServiceCurrentUserIdProvider = Provider<String?>((ref) {
  return Supabase.instance.client.auth.currentUser?.id;
});

/// Keeps the existing shared offline queue moving without requiring the
/// Mobile Services screen to be open. Connectivity is only a retry signal;
/// failed attempts remain queued by the repository.
final mobileServiceAutoSyncProvider = Provider<void>((ref) {
  final connectivity = Connectivity();
  Timer? debounce;
  var disposed = false;

  Future<void> attemptSync() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null || disposed) return;

    try {
      await ref
          .read(mobileServicesRepositoryProvider)
          .syncOfflineMutations(userId);
      if (disposed) return;

      final accountsRepository = ref.read(accountsRepositoryProvider);
      try {
        await Future.wait([
          accountsRepository.refreshCurrentAccountsCache(
            timeout: const Duration(seconds: 10),
          ),
          accountsRepository.refreshCurrentTransactionsCache(
            timeout: const Duration(seconds: 10),
          ),
        ]);
      } catch (_) {
        // The queue has already synced. Normal cache refresh can retry later.
      }

      if (disposed) return;
      ref
        ..invalidate(mobileServiceTransactionsProvider)
        ..invalidate(mobileServiceReportProvider)
        ..invalidate(accountsProvider)
        ..invalidate(accountTransactionsProvider)
        ..invalidate(dashboardStatsProvider);
    } catch (error) {
      // Offline-first: a failed reconnect probe must not surface as an app
      // error or remove the queued mutation.
      debugPrint('Mobile Services auto-sync deferred: $error');
    }
  }

  void scheduleSync() {
    debounce?.cancel();
    debounce = Timer(const Duration(milliseconds: 750), () {
      unawaited(attemptSync());
    });
  }

  final connectivitySubscription = connectivity.onConnectivityChanged.listen(
    (results) {
      if (results.any((result) => result != ConnectivityResult.none)) {
        scheduleSync();
      }
    },
    onError: (Object error, StackTrace stackTrace) {
      // Some Windows NetworkManager configurations cannot activate the
      // native event stream. Startup and auth-triggered sync remain active,
      // so this optional reconnect signal can safely degrade.
      debugPrint('Connectivity retry signal unavailable: $error');
    },
  );
  final authSubscription = Supabase.instance.client.auth.onAuthStateChange
      .listen((authState) {
        if (authState.session != null) scheduleSync();
      });

  // Covers an already-restored session on application startup.
  scheduleSync();

  ref.onDispose(() {
    disposed = true;
    debounce?.cancel();
    unawaited(connectivitySubscription.cancel());
    unawaited(authSubscription.cancel());
  });
});

final mobileServiceProvidersProvider =
    FutureProvider.autoDispose<List<MobileServiceProviderModel>>((ref) async {
      final branchId = await ref.watch(selectedBranchIdProvider.future);
      return ref
          .read(mobileServicesRepositoryProvider)
          .fetchProviders(branchId);
    });

final mobileServiceChargeRulesProvider =
    FutureProvider.autoDispose<List<MobileServiceChargeRuleModel>>((ref) async {
      final branchId = await ref.watch(selectedBranchIdProvider.future);
      return ref
          .read(mobileServicesRepositoryProvider)
          .fetchChargeRules(branchId);
    });

final mobileServiceTransactionsProvider = FutureProvider.autoDispose
    .family<List<MobileServiceTransactionModel>, int>((ref, limit) async {
      final branchId = await ref.watch(selectedBranchIdProvider.future);
      return ref
          .read(mobileServicesRepositoryProvider)
          .fetchTransactions(branchId, limit: limit);
    });

class MobileServiceReportFilter {
  final DateTime from;
  final DateTime to;
  final String? providerId;

  const MobileServiceReportFilter({
    required this.from,
    required this.to,
    this.providerId,
  });

  MobileServiceReportFilter copyWith({
    DateTime? from,
    DateTime? to,
    String? providerId,
    bool clearProvider = false,
  }) {
    return MobileServiceReportFilter(
      from: from ?? this.from,
      to: to ?? this.to,
      providerId: clearProvider ? null : providerId ?? this.providerId,
    );
  }
}

final mobileServiceReportFilterProvider =
    StateProvider.autoDispose<MobileServiceReportFilter>((ref) {
      final now = DateTime.now();
      return MobileServiceReportFilter(
        from: DateTime(now.year, now.month, 1),
        to: DateTime(now.year, now.month, now.day),
      );
    });

final mobileServiceReportProvider =
    FutureProvider.autoDispose<MobileServiceReportSummary>((ref) async {
      final branchId = await ref.watch(selectedBranchIdProvider.future);
      final filter = ref.watch(mobileServiceReportFilterProvider);
      return ref
          .read(mobileServicesRepositoryProvider)
          .fetchReportSummary(
            branchId: branchId,
            from: filter.from,
            to: filter.to.add(const Duration(days: 1)),
            providerId: filter.providerId,
          );
    });

class MobileServiceFormState {
  static const _unset = Object();

  final MobileServiceOperation operation;
  final String? providerId;
  final double? serviceAmount;
  final double? chargedFeeOverride;
  final MobileServiceTransactionPreview? preview;
  final String? validationMessage;

  const MobileServiceFormState({
    this.operation = MobileServiceOperation.send,
    this.providerId,
    this.serviceAmount,
    this.chargedFeeOverride,
    this.preview,
    this.validationMessage,
  });

  bool get canSubmit =>
      providerId != null &&
      serviceAmount != null &&
      preview != null &&
      validationMessage == null;

  MobileServiceFormState copyWith({
    MobileServiceOperation? operation,
    Object? providerId = _unset,
    Object? serviceAmount = _unset,
    Object? chargedFeeOverride = _unset,
    Object? preview = _unset,
    Object? validationMessage = _unset,
  }) {
    return MobileServiceFormState(
      operation: operation ?? this.operation,
      providerId:
          identical(providerId, _unset)
              ? this.providerId
              : providerId as String?,
      serviceAmount:
          identical(serviceAmount, _unset)
              ? this.serviceAmount
              : serviceAmount as double?,
      chargedFeeOverride:
          identical(chargedFeeOverride, _unset)
              ? this.chargedFeeOverride
              : chargedFeeOverride as double?,
      preview:
          identical(preview, _unset)
              ? this.preview
              : preview as MobileServiceTransactionPreview?,
      validationMessage:
          identical(validationMessage, _unset)
              ? this.validationMessage
              : validationMessage as String?,
    );
  }
}

final mobileServiceFormControllerProvider = StateNotifierProvider.autoDispose<
  MobileServiceFormController,
  MobileServiceFormState
>((ref) {
  return MobileServiceFormController(
    repository: ref.read(mobileServicesRepositoryProvider),
    readProviders:
        () => ref.read(mobileServiceProvidersProvider).value ?? const [],
    readRules:
        () => ref.read(mobileServiceChargeRulesProvider).value ?? const [],
  );
});

class MobileServiceFormController
    extends StateNotifier<MobileServiceFormState> {
  final MobileServicesRepository _repository;
  final List<MobileServiceProviderModel> Function() _readProviders;
  final List<MobileServiceChargeRuleModel> Function() _readRules;

  MobileServiceFormController({
    required MobileServicesRepository repository,
    required List<MobileServiceProviderModel> Function() readProviders,
    required List<MobileServiceChargeRuleModel> Function() readRules,
  }) : _repository = repository,
       _readProviders = readProviders,
       _readRules = readRules,
       super(const MobileServiceFormState());

  void selectOperation(MobileServiceOperation operation) {
    state = state.copyWith(
      operation: operation,
      chargedFeeOverride: null,
      preview: null,
      validationMessage: null,
    );
    _recalculate();
  }

  void selectProvider(String? providerId) {
    state = state.copyWith(
      providerId: providerId,
      chargedFeeOverride: null,
      preview: null,
      validationMessage: null,
    );
    _recalculate();
  }

  void enterAmount(double? amount) {
    state = state.copyWith(
      serviceAmount: amount,
      preview: null,
      validationMessage: null,
    );
    _recalculate();
  }

  void overrideFee(double? fee) {
    state = state.copyWith(
      chargedFeeOverride: fee,
      preview: null,
      validationMessage: null,
    );
    _recalculate();
  }

  void reset({MobileServiceOperation? operation}) {
    state = MobileServiceFormState(
      operation: operation ?? state.operation,
      providerId: state.providerId,
    );
  }

  MobileServiceProviderModel? get selectedProvider {
    final providerId = state.providerId;
    if (providerId == null) return null;
    return _readProviders().where((item) => item.id == providerId).firstOrNull;
  }

  MobileServiceChargeRuleModel? get selectedRule {
    final providerId = state.providerId;
    if (providerId == null) return null;
    return _readRules()
        .where(
          (rule) =>
              rule.providerId == providerId &&
              rule.operation == state.operation &&
              rule.isActive,
        )
        .firstOrNull;
  }

  void _recalculate() {
    final amount = state.serviceAmount;
    if (state.providerId == null || amount == null) return;

    final provider = selectedProvider;
    final rule = selectedRule;
    if (provider == null || !provider.isActive) {
      state = state.copyWith(
        preview: null,
        validationMessage: 'Select an active provider.',
      );
      return;
    }
    if (rule == null) {
      state = state.copyWith(
        preview: null,
        validationMessage: 'Configure a charge rule for this operation.',
      );
      return;
    }

    try {
      final preview = _repository.buildPreview(
        operation: state.operation,
        serviceAmount: amount,
        rule: rule,
        chargedFeeOverride: state.chargedFeeOverride,
      );
      state = state.copyWith(preview: preview, validationMessage: null);
    } catch (error) {
      state = state.copyWith(
        preview: null,
        validationMessage: error.toString(),
      );
    }
  }
}

enum MobileServiceSubmissionResult { completed, queued }

final mobileServiceActionControllerProvider = StateNotifierProvider<
  MobileServiceActionController,
  AsyncValue<MobileServiceSubmissionResult?>
>((ref) {
  return MobileServiceActionController(ref);
});

final mobileServiceSettingsControllerProvider =
    StateNotifierProvider<MobileServiceSettingsController, AsyncValue<void>>((
      ref,
    ) {
      return MobileServiceSettingsController(ref);
    });

class MobileServiceSettingsController extends StateNotifier<AsyncValue<void>> {
  final Ref _ref;

  MobileServiceSettingsController(this._ref) : super(const AsyncData(null));

  Future<bool> saveProvider(SaveMobileServiceProviderCommand command) async {
    return _run(() async {
      await _ref.read(mobileServicesRepositoryProvider).saveProvider(command);
      _ref.invalidate(mobileServiceProvidersProvider);
    });
  }

  Future<bool> saveRule(SaveMobileServiceChargeRuleCommand command) async {
    return _run(() async {
      await _ref.read(mobileServicesRepositoryProvider).saveChargeRule(command);
      _ref.invalidate(mobileServiceChargeRulesProvider);
    });
  }

  Future<bool> archiveProvider(String providerId) async {
    return _run(() async {
      await _ref
          .read(mobileServicesRepositoryProvider)
          .archiveProvider(providerId);
      _ref
        ..invalidate(mobileServiceProvidersProvider)
        ..invalidate(mobileServiceChargeRulesProvider);
    });
  }

  Future<bool> restoreProvider(String providerId) async {
    return _run(() async {
      await _ref
          .read(mobileServicesRepositoryProvider)
          .restoreProvider(providerId);
      try {
        await _ref
            .read(accountsRepositoryProvider)
            .refreshCurrentAccountsCache();
      } catch (_) {
        // The restore is authoritative. A cache refresh failure must not turn
        // a successful atomic server restore into a misleading UI failure.
      }
      _ref
        ..invalidate(mobileServiceProvidersProvider)
        ..invalidate(mobileServiceChargeRulesProvider)
        ..invalidate(accountsProvider);
    });
  }

  Future<bool> archiveRule(String ruleId) async {
    return _run(() async {
      await _ref
          .read(mobileServicesRepositoryProvider)
          .archiveChargeRule(ruleId);
      _ref.invalidate(mobileServiceChargeRulesProvider);
    });
  }

  Future<bool> restoreRule(String ruleId) async {
    return _run(() async {
      await _ref
          .read(mobileServicesRepositoryProvider)
          .restoreChargeRule(ruleId);
      _ref.invalidate(mobileServiceChargeRulesProvider);
    });
  }

  Future<bool> _run(Future<void> Function() action) async {
    state = const AsyncLoading();
    try {
      await action();
      state = const AsyncData(null);
      return true;
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      return false;
    }
  }
}

class MobileServiceActionController
    extends StateNotifier<AsyncValue<MobileServiceSubmissionResult?>> {
  final Ref _ref;

  MobileServiceActionController(this._ref) : super(const AsyncData(null));

  Future<bool> submit({
    required String cashAccountId,
    String? phoneNumber,
    String? referenceNumber,
    String? description,
  }) async {
    final userId = _ref.read(mobileServiceCurrentUserIdProvider);
    if (userId == null) {
      state = AsyncError(StateError('User not logged in.'), StackTrace.current);
      return false;
    }

    final formController = _ref.read(
      mobileServiceFormControllerProvider.notifier,
    );
    final form = formController.state;
    final provider = formController.selectedProvider;
    final rule = formController.selectedRule;
    if (!form.canSubmit || provider == null || rule == null) {
      state = AsyncError(
        StateError(form.validationMessage ?? 'Complete the transaction form.'),
        StackTrace.current,
      );
      return false;
    }
    final preview = form.preview!;
    final accounts = _ref.read(accountsProvider).value ?? const [];
    final cashAccount =
        accounts.where((account) => account.id == cashAccountId).firstOrNull;
    final walletAccount =
        accounts
            .where((account) => account.id == provider.providerAccountId)
            .firstOrNull;
    final insufficientMessage =
        form.operation == MobileServiceOperation.send &&
                walletAccount != null &&
                walletAccount.currentBalance + 0.01 < preview.serviceAmount
            ? 'Insufficient provider wallet balance. Available '
                'Rs ${walletAccount.currentBalance.toStringAsFixed(2)}, '
                'required Rs ${preview.serviceAmount.toStringAsFixed(2)}.'
            : form.operation == MobileServiceOperation.receive &&
                cashAccount != null &&
                cashAccount.currentBalance + 0.01 < preview.customerCashAmount
            ? 'Insufficient cash balance. Available '
                'Rs ${cashAccount.currentBalance.toStringAsFixed(2)}, '
                'required Rs ${preview.customerCashAmount.toStringAsFixed(2)}.'
            : null;
    if (insufficientMessage != null) {
      state = AsyncError(StateError(insufficientMessage), StackTrace.current);
      return false;
    }

    state = const AsyncLoading();
    final command = RecordMobileServiceTransactionCommand.create(
      providerId: provider.id,
      cashAccountId: cashAccountId,
      operation: form.operation,
      serviceAmount: form.serviceAmount!,
      chargedFee: form.chargedFeeOverride,
      phoneNumber: phoneNumber,
      referenceNumber: referenceNumber,
      description: description,
    );

    try {
      await _ref
          .read(mobileServicesRepositoryProvider)
          .recordTransaction(
            command,
            queueForUserId: userId,
            provider: provider,
            rule: rule,
          );
      state = const AsyncData(MobileServiceSubmissionResult.completed);
      await _afterFinancialChange(refreshAccountCache: true);
      formController.reset();
      return true;
    } on MobileServiceQueuedOfflineException {
      state = const AsyncData(MobileServiceSubmissionResult.queued);
      await _afterFinancialChange(refreshAccountCache: false);
      formController.reset();
      return true;
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      return false;
    }
  }

  Future<bool> voidTransaction({
    required String transactionId,
    required String reason,
  }) async {
    state = const AsyncLoading();
    try {
      final command = VoidMobileServiceTransactionCommand.create(
        transactionId: transactionId,
        reason: reason,
      );
      await _ref
          .read(mobileServicesRepositoryProvider)
          .voidTransaction(command);
      state = const AsyncData(MobileServiceSubmissionResult.completed);
      await _afterFinancialChange(refreshAccountCache: true);
      return true;
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      return false;
    }
  }

  Future<void> sync() async {
    final userId = _ref.read(mobileServiceCurrentUserIdProvider);
    if (userId == null) return;

    state = const AsyncLoading();
    try {
      await _ref
          .read(mobileServicesRepositoryProvider)
          .syncOfflineMutations(userId);
      state = const AsyncData(MobileServiceSubmissionResult.completed);
      await _afterFinancialChange(refreshAccountCache: true);
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
    }
  }

  void clearResult() {
    state = const AsyncData(null);
  }

  Future<void> _afterFinancialChange({
    required bool refreshAccountCache,
  }) async {
    if (refreshAccountCache) {
      final accountsRepository = _ref.read(accountsRepositoryProvider);
      try {
        await Future.wait([
          accountsRepository.refreshCurrentAccountsCache(
            timeout: const Duration(seconds: 10),
          ),
          accountsRepository.refreshCurrentTransactionsCache(
            timeout: const Duration(seconds: 10),
          ),
        ]);
      } catch (_) {
        // The financial RPC already succeeded. Keep the successful result and
        // let the normal account refresh/realtime path retry stale cache data.
      }
    }
    _ref
      ..invalidate(mobileServiceTransactionsProvider)
      ..invalidate(mobileServiceReportProvider)
      ..invalidate(accountsProvider)
      ..invalidate(accountTransactionsProvider)
      ..invalidate(dashboardStatsProvider);
  }
}
