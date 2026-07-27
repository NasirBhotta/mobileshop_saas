import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:mobileshop_saas/core/entitlements/entitlement_provider.dart';
import 'package:mobileshop_saas/core/entitlements/entitlement_evaluator.dart';
import 'package:mobileshop_saas/core/authorization/branch_permission_shadow_provider.dart';
import 'package:mobileshop_saas/features/expenses/data/models/expense_models.dart';
import 'package:mobileshop_saas/features/expenses/data/repositories/expense_repository.dart';

class ExpenseDateRange {
  final DateTime from;
  final DateTime to;

  const ExpenseDateRange({required this.from, required this.to});

  ExpenseDateRange copyWith({DateTime? from, DateTime? to}) {
    return ExpenseDateRange(from: from ?? this.from, to: to ?? this.to);
  }
}

Future<void> _requireExpense(
  Ref ref,
  String feature, {
  String? permissionKey,
}) async {
  if (!await hasFeatureWithCompatibility(
    ref.read(entitlementEvaluatorProvider),
    feature,
  )) {
    throw EntitlementDeniedException(feature);
  }
  if (permissionKey != null) {
    final allowed = await ref.read(
      branchAwarePermissionProvider(permissionKey).future,
    );
    if (!allowed) {
      throw StateError('Permission required: $permissionKey');
    }
  }
}

final expenseRepositoryProvider = Provider<ExpenseRepository>((ref) {
  return ExpenseRepository(
    entitlements: ref.watch(entitlementEvaluatorProvider),
  );
});

final expenseHistoryLimitProvider = FutureProvider<num?>((ref) {
  return ref
      .watch(entitlementEvaluatorProvider)
      .getLimit('expenses.history_days');
});

// ════════════════════════════════════════
// FILTERS
// ════════════════════════════════════════

final expenseDateRangeProvider = StateProvider<ExpenseDateRange>((ref) {
  final now = DateTime.now();

  return ExpenseDateRange(
    from: DateTime(now.year, now.month, 1),
    to: DateTime(now.year, now.month, now.day),
  );
});

final selectedExpenseCategoryProvider = StateProvider<String?>((ref) {
  return null;
});

final selectedExpenseStatusProvider = StateProvider<ExpenseStatus?>((ref) {
  return null;
});

final selectedExpenseSourceProvider = StateProvider<ExpenseSource?>((ref) {
  return null;
});

// ════════════════════════════════════════
// READ PROVIDERS
// ════════════════════════════════════════

final expenseCategoriesProvider =
    FutureProvider.autoDispose<List<ExpenseCategoryModel>>((ref) async {
      final repository = ref.read(expenseRepositoryProvider);

      return repository.fetchCategories();
    });

final expensesProvider = FutureProvider.autoDispose<List<ExpenseModel>>((
  ref,
) async {
  final repository = ref.read(expenseRepositoryProvider);

  if (await hasFeatureWithCompatibility(
    ref.read(entitlementEvaluatorProvider),
    'expenses.recurring',
  )) {
    await repository.generateDueRecurringDrafts();
  }

  final range = ref.watch(expenseDateRangeProvider);
  final categoryId = ref.watch(selectedExpenseCategoryProvider);
  final status = ref.watch(selectedExpenseStatusProvider);
  final source = ref.watch(selectedExpenseSourceProvider);

  return repository.fetchExpenses(
    dateFrom: range.from,
    dateTo: range.to,
    categoryId: categoryId,
    status: status,
    source: source,
  );
});

final recurringExpenseRulesProvider =
    FutureProvider.autoDispose<List<RecurringExpenseRuleModel>>((ref) async {
      final repository = ref.read(expenseRepositoryProvider);

      return repository.fetchRecurringRules();
    });

final activeRecurringExpenseRulesProvider =
    FutureProvider.autoDispose<List<RecurringExpenseRuleModel>>((ref) async {
      final repository = ref.read(expenseRepositoryProvider);

      return repository.fetchRecurringRules(activeOnly: true);
    });

final expenseReportProvider =
    FutureProvider.autoDispose<ExpenseProfitReportModel>((ref) async {
      final repository = ref.read(expenseRepositoryProvider);

      if (await hasFeatureWithCompatibility(
        ref.read(entitlementEvaluatorProvider),
        'expenses.recurring',
      )) {
        await repository.generateDueRecurringDrafts();
      }

      final range = ref.watch(expenseDateRangeProvider);
      final categoryId = ref.watch(selectedExpenseCategoryProvider);

      return repository.fetchReport(
        dateFrom: range.from,
        dateTo: range.to,
        categoryId: categoryId,
      );
    });

// ════════════════════════════════════════
// CATEGORY CONTROLLER
// ════════════════════════════════════════

final expenseCategoryControllerProvider = StateNotifierProvider<
  ExpenseCategoryController,
  AsyncValue<ExpenseCategoryModel?>
>((ref) {
  return ExpenseCategoryController(ref);
});

class ExpenseCategoryController
    extends StateNotifier<AsyncValue<ExpenseCategoryModel?>> {
  final Ref _ref;

  ExpenseCategoryController(this._ref) : super(const AsyncData(null));

  Future<ExpenseCategoryModel?> createCategory({
    required String name,
    String? description,
  }) async {
    if (state.isLoading) return null;
    state = const AsyncLoading();

    try {
      await _requireExpense(
        _ref,
        'expenses.core',
        permissionKey: 'expense.category.manage',
      );
      final repository = _ref.read(expenseRepositoryProvider);

      final category = await repository.createCategory(
        name: name,
        description: description,
      );

      state = AsyncData(category);

      _ref.invalidate(expenseCategoriesProvider);

      return category;
    } catch (e, st) {
      state = AsyncError(e, st);
      return null;
    }
  }

  void reset() {
    state = const AsyncData(null);
  }
}

// ════════════════════════════════════════
// EXPENSE CONTROLLER
// ════════════════════════════════════════

final expenseControllerProvider =
    StateNotifierProvider<ExpenseController, AsyncValue<ExpenseModel?>>((ref) {
      return ExpenseController(ref);
    });

class ExpenseController extends StateNotifier<AsyncValue<ExpenseModel?>> {
  final Ref _ref;

  ExpenseController(this._ref) : super(const AsyncData(null));

  Future<ExpenseModel?> createExpense({
    required String title,
    required DateTime expenseDate,
    required double amount,
    String? categoryId,
    String? categoryName,
    ExpensePaymentMode paymentMode = ExpensePaymentMode.cash,
    String? accountId,
    String? payee,
    String? notes,
    String? localReceiptPath,
    ExpenseStatus status = ExpenseStatus.confirmed,
  }) async {
    state = const AsyncLoading();

    try {
      await _requireExpense(
        _ref,
        'expenses.core',
        permissionKey: 'expense.expense.create',
      );
      if (localReceiptPath?.trim().isNotEmpty == true) {
        await _requireExpense(_ref, 'expenses.receipts');
      }
      final repository = _ref.read(expenseRepositoryProvider);

      final expense = await repository.createExpense(
        title: title,
        expenseDate: expenseDate,
        amount: amount,
        categoryId: categoryId,
        categoryName: categoryName,
        paymentMode: paymentMode,
        accountId: accountId,
        payee: payee,
        notes: notes,
        localReceiptPath: localReceiptPath,
        status: status,
      );

      state = AsyncData(expense);

      _refreshExpenseReads();

      return expense;
    } catch (e, st) {
      state = AsyncError(e, st);
      return null;
    }
  }

  Future<bool> confirmExpense({
    required ExpenseModel expense,
    required String accountId,
    double? actualAmount,
    String? localReceiptPath,
  }) async {
    state = const AsyncLoading();

    try {
      await _requireExpense(
        _ref,
        'expenses.core',
        permissionKey: 'expense.expense.update',
      );
      if (localReceiptPath?.trim().isNotEmpty == true) {
        await _requireExpense(_ref, 'expenses.receipts');
      }
      final repository = _ref.read(expenseRepositoryProvider);

      await repository.confirmExpense(
        expense: expense,
        accountId: accountId,
        actualAmount: actualAmount,
        localReceiptPath: localReceiptPath,
      );

      state = AsyncData(
        expense.copyWith(
          status: ExpenseStatus.confirmed,
          amount: actualAmount ?? expense.amount,
          localReceiptPath: localReceiptPath ?? expense.localReceiptPath,
          confirmedAt: DateTime.now(),
        ),
      );

      _refreshExpenseReads();

      return true;
    } catch (e, st) {
      state = AsyncError(e, st);
      return false;
    }
  }

  Future<bool> voidExpense(ExpenseModel expense) async {
    state = const AsyncLoading();

    try {
      await _requireExpense(
        _ref,
        'expenses.core',
        permissionKey: 'expense.expense.void',
      );
      final repository = _ref.read(expenseRepositoryProvider);

      await repository.voidExpense(expense);

      state = AsyncData(
        expense.copyWith(
          status: ExpenseStatus.voided,
          updatedAt: DateTime.now(),
        ),
      );

      _refreshExpenseReads();

      return true;
    } catch (e, st) {
      state = AsyncError(e, st);
      return false;
    }
  }

  void reset() {
    state = const AsyncData(null);
  }

  void _refreshExpenseReads() {
    _ref.invalidate(expensesProvider);
    _ref.invalidate(expenseReportProvider);
  }
}

// ════════════════════════════════════════
// RECURRING EXPENSE CONTROLLER
// ════════════════════════════════════════

final recurringExpenseControllerProvider = StateNotifierProvider<
  RecurringExpenseController,
  AsyncValue<RecurringExpenseRuleModel?>
>((ref) {
  return RecurringExpenseController(ref);
});

class RecurringExpenseController
    extends StateNotifier<AsyncValue<RecurringExpenseRuleModel?>> {
  final Ref _ref;

  RecurringExpenseController(this._ref) : super(const AsyncData(null));

  Future<RecurringExpenseRuleModel?> createRule({
    required String title,
    required String categoryName,
    String? categoryId,
    required double estimatedAmount,
    ExpensePaymentMode paymentMode = ExpensePaymentMode.cash,
    String? payee,
    String? note,
    RecurringExpenseFrequency frequency = RecurringExpenseFrequency.monthly,
    int intervalCount = 1,
    required DateTime startDate,
    DateTime? endDate,
    int reminderDaysBefore = 3,
  }) async {
    state = const AsyncLoading();

    try {
      await _requireExpense(_ref, 'expenses.recurring');
      final repository = _ref.read(expenseRepositoryProvider);

      final rule = await repository.createRecurringRule(
        title: title,
        categoryName: categoryName,
        categoryId: categoryId,
        estimatedAmount: estimatedAmount,
        paymentMode: paymentMode,
        payee: payee,
        note: note,
        frequency: frequency,
        intervalCount: intervalCount,
        startDate: startDate,
        endDate: endDate,
        reminderDaysBefore: reminderDaysBefore,
      );

      await repository.generateDueRecurringDrafts();

      state = AsyncData(rule);

      _ref.invalidate(recurringExpenseRulesProvider);
      _ref.invalidate(activeRecurringExpenseRulesProvider);
      _ref.invalidate(expensesProvider);
      _ref.invalidate(expenseReportProvider);

      return rule;
    } catch (e, st) {
      state = AsyncError(e, st);
      return null;
    }
  }

  Future<bool> updateStatus({
    required RecurringExpenseRuleModel rule,
    required String status,
  }) async {
    state = const AsyncLoading();

    try {
      await _requireExpense(_ref, 'expenses.recurring');
      final repository = _ref.read(expenseRepositoryProvider);

      await repository.updateRecurringRuleStatus(rule: rule, status: status);

      state = AsyncData(rule);

      _ref.invalidate(recurringExpenseRulesProvider);
      _ref.invalidate(activeRecurringExpenseRulesProvider);

      return true;
    } catch (e, st) {
      state = AsyncError(e, st);
      return false;
    }
  }

  Future<int> generateDueDrafts() async {
    state = const AsyncLoading();

    try {
      await _requireExpense(_ref, 'expenses.recurring');
      final repository = _ref.read(expenseRepositoryProvider);

      final count = await repository.generateDueRecurringDrafts();

      state = const AsyncData(null);

      _ref.invalidate(expensesProvider);
      _ref.invalidate(expenseReportProvider);
      _ref.invalidate(recurringExpenseRulesProvider);
      _ref.invalidate(activeRecurringExpenseRulesProvider);

      return count;
    } catch (e, st) {
      state = AsyncError(e, st);
      return 0;
    }
  }

  void reset() {
    state = const AsyncData(null);
  }
}

// ════════════════════════════════════════
// SYNC CONTROLLER
// ════════════════════════════════════════

final expenseSyncControllerProvider =
    StateNotifierProvider<ExpenseSyncController, AsyncValue<void>>((ref) {
      return ExpenseSyncController(ref);
    });

class ExpenseSyncController extends StateNotifier<AsyncValue<void>> {
  final Ref _ref;

  ExpenseSyncController(this._ref) : super(const AsyncData(null));

  Future<void> sync() async {
    state = const AsyncLoading();

    try {
      final repository = _ref.read(expenseRepositoryProvider);

      await repository.syncOfflineMutations();
      final recurringEnabled = await hasFeatureWithCompatibility(
        _ref.read(entitlementEvaluatorProvider),
        'expenses.recurring',
      );
      if (recurringEnabled) {
        await repository.generateDueRecurringDrafts();
      }

      Future<void> safelyRefresh(Future<Object?> refresh) async {
        try {
          await refresh;
        } catch (_) {
          // Preserve the current local cache if one remote source is down.
        }
      }

      final range = _ref.read(expenseDateRangeProvider);
      await Future.wait([
        safelyRefresh(
          repository.refreshCurrentCategoriesCache(
            timeout: const Duration(seconds: 10),
          ),
        ),
        safelyRefresh(
          repository.refreshExpensesCache(
            dateFrom: range.from,
            dateTo: range.to,
            categoryId: _ref.read(selectedExpenseCategoryProvider),
            status: _ref.read(selectedExpenseStatusProvider),
            source: _ref.read(selectedExpenseSourceProvider),
            timeout: const Duration(seconds: 10),
          ),
        ),
        if (recurringEnabled)
          safelyRefresh(
            repository.refreshCurrentRecurringRulesCache(
              timeout: const Duration(seconds: 10),
            ),
          ),
      ]);

      _ref
        ..invalidate(expenseCategoriesProvider)
        ..invalidate(expensesProvider)
        ..invalidate(expenseReportProvider)
        ..invalidate(recurringExpenseRulesProvider)
        ..invalidate(activeRecurringExpenseRulesProvider);
      await Future.wait([
        safelyRefresh(_ref.read(expenseCategoriesProvider.future)),
        safelyRefresh(_ref.read(expensesProvider.future)),
        if (recurringEnabled)
          safelyRefresh(_ref.read(recurringExpenseRulesProvider.future)),
      ]);

      state = const AsyncData(null);
    } catch (e, st) {
      state = AsyncError(e, st);
    }
  }
}
