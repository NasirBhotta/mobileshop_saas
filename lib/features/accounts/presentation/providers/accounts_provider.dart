import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:mobileshop_saas/core/entitlements/entitlement_evaluator.dart';
import 'package:mobileshop_saas/core/entitlements/entitlement_provider.dart';
import 'package:mobileshop_saas/features/accounts/data/models/account_models.dart';
import 'package:mobileshop_saas/features/accounts/data/repositories/accounts_repository.dart';

final accountsRepositoryProvider = Provider<AccountsRepository>((ref) {
  return AccountsRepository(
    entitlementEvaluator: ref.watch(entitlementEvaluatorProvider),
  );
});

Future<void> _requireAccount(Ref ref, String feature) async {
  if (!await ref.read(entitlementEvaluatorProvider).hasFeature(feature)) {
    throw EntitlementDeniedException(feature);
  }
}

final accountsProvider = FutureProvider.autoDispose<List<AccountModel>>((ref) {
  return ref.read(accountsRepositoryProvider).fetchAccounts();
});

final accountTransactionsProvider =
    FutureProvider.autoDispose<List<AccountTransactionModel>>((ref) {
      return ref.read(accountsRepositoryProvider).fetchTransactions();
    });

final accountControllerProvider =
    StateNotifierProvider<AccountController, AsyncValue<void>>((ref) {
      return AccountController(ref);
    });

class AccountController extends StateNotifier<AsyncValue<void>> {
  final Ref _ref;

  AccountController(this._ref) : super(const AsyncData(null));

  Future<bool> createAccount({
    required String name,
    required AccountType type,
    double openingBalance = 0,
    String? note,
  }) async {
    state = const AsyncLoading();

    try {
      await _requireAccount(_ref, 'accounts.core');
      await _ref
          .read(accountsRepositoryProvider)
          .createAccount(
            name: name,
            type: type,
            openingBalance: openingBalance,
            note: note,
          );
      state = const AsyncData(null);
      _invalidate();
      return true;
    } catch (e, st) {
      state = AsyncError(e, st);
      return false;
    }
  }

  Future<bool> recordTransaction({
    required String accountId,
    required AccountTransactionDirection direction,
    required AccountTransactionType type,
    required double amount,
    String? description,
  }) async {
    state = const AsyncLoading();

    try {
      await _requireAccount(_ref, 'accounts.core');
      await _ref
          .read(accountsRepositoryProvider)
          .recordTransaction(
            accountId: accountId,
            direction: direction,
            type: type,
            amount: amount,
            description: description,
          );
      state = const AsyncData(null);
      _invalidate();
      return true;
    } catch (e, st) {
      state = AsyncError(e, st);
      return false;
    }
  }

  Future<bool> transfer({
    required String fromAccountId,
    required String toAccountId,
    required double amount,
    String? description,
  }) async {
    state = const AsyncLoading();

    try {
      await _requireAccount(_ref, 'accounts.transfers');
      await _ref
          .read(accountsRepositoryProvider)
          .transfer(
            fromAccountId: fromAccountId,
            toAccountId: toAccountId,
            amount: amount,
            description: description,
          );
      state = const AsyncData(null);
      _invalidate();
      return true;
    } catch (e, st) {
      state = AsyncError(e, st);
      return false;
    }
  }

  void _invalidate() {
    _ref.invalidate(accountsProvider);
    _ref.invalidate(accountTransactionsProvider);
  }
}

final accountsSyncControllerProvider =
    StateNotifierProvider<AccountsSyncController, AsyncValue<void>>((ref) {
      return AccountsSyncController(ref);
    });

class AccountsSyncController extends StateNotifier<AsyncValue<void>> {
  final Ref _ref;

  AccountsSyncController(this._ref) : super(const AsyncData(null));

  Future<void> sync() async {
    state = const AsyncLoading();

    try {
      await _ref.read(accountsRepositoryProvider).syncOfflineMutations();
      state = const AsyncData(null);
      _ref.invalidate(accountsProvider);
      _ref.invalidate(accountTransactionsProvider);
    } catch (e, st) {
      state = AsyncError(e, st);
    }
  }
}
