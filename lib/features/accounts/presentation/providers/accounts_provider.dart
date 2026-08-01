import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:mobileshop_saas/core/authorization/branch_permission_shadow_provider.dart';
import 'package:mobileshop_saas/core/entitlements/entitlement_evaluator.dart';
import 'package:mobileshop_saas/core/entitlements/entitlement_provider.dart';
import 'package:mobileshop_saas/features/accounts/data/models/account_models.dart';
import 'package:mobileshop_saas/features/accounts/data/repositories/accounts_repository.dart';

final accountsRepositoryProvider = Provider<AccountsRepository>((ref) {
  return AccountsRepository(
    entitlementEvaluator: ref.watch(entitlementEvaluatorProvider),
    permissionGuard: (permissionKey) async {
      final allowed = await ref.read(
        branchAwarePermissionProvider(permissionKey).future,
      );
      if (!allowed) {
        throw AccountPermissionDeniedException(permissionKey);
      }
    },
  );
});

Future<void> _requireAccount(
  Ref ref,
  String feature, {
  required String permissionKey,
}) async {
  if (!await hasFeatureWithCompatibility(
    ref.read(entitlementEvaluatorProvider),
    feature,
  )) {
    throw EntitlementDeniedException(feature);
  }
  final allowed = await ref.read(
    branchAwarePermissionProvider(permissionKey).future,
  );
  if (!allowed) throw AccountPermissionDeniedException(permissionKey);
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
      await _requireAccount(
        _ref,
        'accounts.core',
        permissionKey: 'account.account.create',
      );
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

  Future<bool> updateAccount({
    required String accountId,
    required String name,
    required AccountType type,
    String? note,
  }) async {
    state = const AsyncLoading();
    try {
      await _requireAccount(
        _ref,
        'accounts.core',
        permissionKey: 'account.account.update',
      );
      await _ref
          .read(accountsRepositoryProvider)
          .updateAccount(
            accountId: accountId,
            name: name,
            type: type,
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

  Future<bool> deleteAccount(String accountId) async {
    state = const AsyncLoading();
    try {
      await _requireAccount(
        _ref,
        'accounts.core',
        permissionKey: 'account.account.update',
      );
      await _ref.read(accountsRepositoryProvider).deactivateAccount(accountId);
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
      await _requireAccount(
        _ref,
        'accounts.core',
        permissionKey: 'account.transaction.create',
      );
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
      await _requireAccount(
        _ref,
        'accounts.transfers',
        permissionKey: 'account.transaction.create',
      );
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
      final repository = _ref.read(accountsRepositoryProvider);
      await repository.syncOfflineMutations();

      Future<void> safelyRefresh(Future<Object?> refresh) async {
        try {
          await refresh;
        } catch (_) {
          // Preserve the current local account data when remote is unavailable.
        }
      }

      await Future.wait([
        safelyRefresh(
          repository.refreshCurrentAccountsCache(
            timeout: const Duration(seconds: 10),
          ),
        ),
        safelyRefresh(
          repository.refreshCurrentTransactionsCache(
            timeout: const Duration(seconds: 10),
          ),
        ),
      ]);

      _ref
        ..invalidate(accountsProvider)
        ..invalidate(accountTransactionsProvider);
      await Future.wait([
        safelyRefresh(_ref.read(accountsProvider.future)),
        safelyRefresh(_ref.read(accountTransactionsProvider.future)),
      ]);

      state = const AsyncData(null);
    } catch (e, st) {
      state = AsyncError(e, st);
    }
  }
}
