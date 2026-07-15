import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:mobileshop_saas/core/entitlements/entitlement_evaluator.dart';
import 'package:mobileshop_saas/core/offline/offline_store.dart';
import 'package:mobileshop_saas/core/utils/offline_error_classifier.dart';
import 'package:mobileshop_saas/features/expenses/data/local/expense_local_store.dart';
import 'package:mobileshop_saas/features/expenses/data/models/expense_models.dart';
import 'package:mobileshop_saas/features/expenses/domain/expense_entitlement_gate.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

class ExpenseRepository {
  static const _networkTimeout = Duration(seconds: 8);
  static const _receiptBucket = 'expense-receipts';

  final SupabaseClient _client;
  final EntitlementEvaluator _entitlements;
  late final ExpenseEntitlementGate _gate = ExpenseEntitlementGate(
    _entitlements,
  );

  ExpenseRepository({
    SupabaseClient? client,
    required EntitlementEvaluator entitlements,
  }) : _client = client ?? Supabase.instance.client,
       _entitlements = entitlements;

  User get _currentUser {
    final user = _client.auth.currentUser;
    if (user == null) throw Exception('User not logged in');
    return user;
  }

  // ════════════════════════════════════════
  // CURRENT PROFILE / TENANT / BRANCH
  // ════════════════════════════════════════

  Future<Map<String, dynamic>> _currentProfile() async {
    final cached = await OfflineStore.loadProfile(_currentUser.id);

    if (cached != null) {
      return cached;
    }

    final profile = await _client
        .from('users')
        .select('id, tenant_id, branch_id, full_name, email, phone, role')
        .eq('id', _currentUser.id)
        .maybeSingle()
        .timeout(_networkTimeout);

    if (profile == null) {
      throw Exception('User profile not found');
    }

    final selectedBranchId = await OfflineStore.loadSelectedBranchId(
      _currentUser.id,
    );

    if (selectedBranchId != null) {
      profile['branch_id'] = selectedBranchId;
    }

    await OfflineStore.saveProfile(_currentUser.id, profile);

    return profile;
  }

  Future<String> _tenantId() async {
    final profile = await _currentProfile();
    final tenantId = profile['tenant_id'] as String?;

    if (tenantId == null) {
      throw Exception('Tenant not found');
    }

    return tenantId;
  }

  Future<String> _branchId(String tenantId) async {
    final profile = await _currentProfile();

    final selectedBranchId = profile['branch_id'] as String?;
    if (selectedBranchId != null) return selectedBranchId;

    final cachedBranches = await OfflineStore.loadBranches(tenantId);
    if (cachedBranches.isNotEmpty && cachedBranches.first.id != null) {
      return cachedBranches.first.id!;
    }

    final branch = await _client
        .from('branches')
        .select('id')
        .eq('tenant_id', tenantId)
        .limit(1)
        .maybeSingle()
        .timeout(_networkTimeout);

    final branchId = branch?['id'] as String?;

    if (branchId == null) {
      throw Exception('Branch not found');
    }

    return branchId;
  }

  Future<String> _tenantPlan(String tenantId) async {
    try {
      final tenant = await _client
          .from('tenants')
          .select('plan')
          .eq('id', tenantId)
          .maybeSingle()
          .timeout(_networkTimeout);

      return (tenant?['plan'] as String?)?.toLowerCase() ?? 'starter';
    } catch (_) {
      final cachedTenant = await OfflineStore.loadTenant(_currentUser.id);
      return (cachedTenant?['plan'] as String?)?.toLowerCase() ?? 'starter';
    }
  }

  // ════════════════════════════════════════
  // CATEGORIES
  // ════════════════════════════════════════

  Future<List<ExpenseCategoryModel>> fetchCategories() async {
    await _gate.require('expenses.core');
    final tenantId = await _tenantId();
    final branchId = await _branchId(tenantId);

    final cached = await ExpenseLocalStore.loadCategories(
      tenantId: tenantId,
      branchId: branchId,
    );

    if (cached.isNotEmpty) {
      unawaited(_refreshCategories(tenantId: tenantId, branchId: branchId));
      unawaited(syncOfflineMutations());
      return cached;
    }

    try {
      await _ensureDefaultCategories(tenantId: tenantId, branchId: branchId);

      return await _fetchRemoteCategories(
        tenantId: tenantId,
        branchId: branchId,
      ).timeout(_networkTimeout);
    } catch (_) {
      return ExpenseLocalStore.loadCategories(
        tenantId: tenantId,
        branchId: branchId,
      );
    }
  }

  Future<ExpenseCategoryModel> createCategory({
    required String name,
    String? description,
  }) async {
    await _gate.require('expenses.core');
    final tenantId = await _tenantId();
    final branchId = await _branchId(tenantId);
    final now = DateTime.now();

    final category = ExpenseCategoryModel(
      id: const Uuid().v4(),
      tenantId: tenantId,
      branchId: branchId,
      name: name.trim(),
      description: _clean(description),
      isSystem: false,
      isActive: true,
      createdBy: _currentUser.id,
      createdAt: now,
      updatedAt: now,
    );

    await ExpenseLocalStore.saveCategory(category);

    try {
      final data = await _client
          .from('expense_categories')
          .upsert(category.toMap(), onConflict: 'id')
          .select()
          .single()
          .timeout(_networkTimeout);

      final saved = ExpenseCategoryModel.fromMap(data);
      await ExpenseLocalStore.saveCategory(saved);
      return saved;
    } catch (e) {
      OfflineErrorClassifier.rethrowIfTerminal(e);
      await OfflineStore.enqueueMutation(
        userId: _currentUser.id,
        type: 'upsert_expense_category',
        payload: category.toMap(),
      );

      debugPrint('Expense category saved offline: $e');
      return category;
    }
  }

  Future<void> _ensureDefaultCategories({
    required String tenantId,
    required String branchId,
  }) async {
    try {
      await _client
          .rpc(
            'ensure_default_expense_categories',
            params: {'p_tenant_id': tenantId, 'p_branch_id': branchId},
          )
          .timeout(_networkTimeout);
    } catch (_) {
      // If remote is unavailable, app can still work with manually created
      // or cached categories.
    }
  }

  Future<void> _refreshCategories({
    required String tenantId,
    required String branchId,
  }) async {
    try {
      await _ensureDefaultCategories(tenantId: tenantId, branchId: branchId);

      await _fetchRemoteCategories(
        tenantId: tenantId,
        branchId: branchId,
      ).timeout(_networkTimeout);
    } catch (_) {}
  }

  Future<List<ExpenseCategoryModel>> _fetchRemoteCategories({
    required String tenantId,
    required String branchId,
  }) async {
    final data = await _client
        .from('expense_categories')
        .select()
        .eq('tenant_id', tenantId)
        .or('branch_id.eq.$branchId,branch_id.is.null')
        .eq('is_active', true)
        .order('is_system', ascending: false)
        .order('name');

    final categories =
        (data as List).map((row) => ExpenseCategoryModel.fromMap(row)).toList();

    await ExpenseLocalStore.saveCategories(categories);

    return categories;
  }

  // ════════════════════════════════════════
  // EXPENSES
  // ════════════════════════════════════════

  Future<ExpenseModel> createExpense({
    required String title,
    required DateTime expenseDate,
    required double amount,
    String? categoryId,
    String? categoryName,
    ExpensePaymentMode paymentMode = ExpensePaymentMode.cash,
    String? payee,
    String? notes,
    String? localReceiptPath,
    ExpenseStatus status = ExpenseStatus.confirmed,
  }) async {
    await _gate.require('expenses.core');
    if (localReceiptPath?.trim().isNotEmpty == true) {
      await _gate.require('expenses.receipts');
    }
    if (amount < 0) {
      throw Exception('Expense amount cannot be negative.');
    }

    final tenantId = await _tenantId();
    final branchId = await _branchId(tenantId);
    final now = DateTime.now();

    final expense = ExpenseModel(
      id: const Uuid().v4(),
      tenantId: tenantId,
      branchId: branchId,
      categoryId: categoryId,
      categoryName: _clean(categoryName),
      title: title.trim(),
      expenseDate: expenseDate,
      amount: amount,
      paymentMode: paymentMode,
      payee: _clean(payee),
      notes: _clean(notes),
      receiptPhotoPath: null,
      localReceiptPath: _clean(localReceiptPath),
      status: status,
      source: ExpenseSource.manual,
      createdBy: _currentUser.id,
      confirmedBy: status == ExpenseStatus.confirmed ? _currentUser.id : null,
      confirmedAt: status == ExpenseStatus.confirmed ? now : null,
      createdAt: now,
      updatedAt: now,
    );

    await ExpenseLocalStore.saveExpense(expense);

    try {
      final uploadedReceiptPath = await _uploadReceiptIfNeeded(
        expense: expense,
      );

      final remoteExpense = expense.copyWith(
        receiptPhotoPath: uploadedReceiptPath,
        updatedAt: DateTime.now(),
      );

      final data = await _client
          .from('expenses')
          .upsert(remoteExpense.toRemoteInsertMap(), onConflict: 'id')
          .select()
          .single()
          .timeout(_networkTimeout);

      final saved = ExpenseModel.fromMap(data);
      await ExpenseLocalStore.saveExpense(saved);
      return saved;
    } catch (e) {
      OfflineErrorClassifier.rethrowIfTerminal(e);
      await OfflineStore.enqueueMutation(
        userId: _currentUser.id,
        type: 'upsert_expense',
        payload: expense.toMap(),
      );

      debugPrint('Expense saved offline: $e');
      return expense;
    }
  }

  Future<List<ExpenseModel>> fetchExpenses({
    DateTime? dateFrom,
    DateTime? dateTo,
    String? categoryId,
    ExpenseStatus? status,
    ExpenseSource? source,
  }) async {
    await _gate.require('expenses.core');
    final tenantId = await _tenantId();
    final branchId = await _branchId(tenantId);

    final cached = await ExpenseLocalStore.loadExpenses(
      branchId: branchId,
      dateFrom: dateFrom,
      dateTo: dateTo,
      categoryId: categoryId,
      status: status,
      source: source,
    );

    if (cached.isNotEmpty) {
      unawaited(
        _refreshExpenses(
          tenantId: tenantId,
          branchId: branchId,
          dateFrom: dateFrom,
          dateTo: dateTo,
          categoryId: categoryId,
          status: status,
          source: source,
        ),
      );

      unawaited(syncOfflineMutations());
      return cached;
    }

    try {
      return await _fetchRemoteExpenses(
        tenantId: tenantId,
        branchId: branchId,
        dateFrom: dateFrom,
        dateTo: dateTo,
        categoryId: categoryId,
        status: status,
        source: source,
      ).timeout(_networkTimeout);
    } catch (_) {
      return ExpenseLocalStore.loadExpenses(
        branchId: branchId,
        dateFrom: dateFrom,
        dateTo: dateTo,
        categoryId: categoryId,
        status: status,
        source: source,
      );
    }
  }

  Future<ExpenseModel?> fetchExpenseById(String expenseId) async {
    await _gate.require('expenses.core');
    try {
      final data = await _client
          .from('expenses')
          .select()
          .eq('id', expenseId)
          .maybeSingle()
          .timeout(_networkTimeout);

      if (data == null) {
        return ExpenseLocalStore.loadExpenseById(expenseId);
      }

      final expense = ExpenseModel.fromMap(data);
      await ExpenseLocalStore.saveExpense(expense);
      return expense;
    } catch (_) {
      return ExpenseLocalStore.loadExpenseById(expenseId);
    }
  }

  Future<void> _refreshExpenses({
    required String tenantId,
    required String branchId,
    DateTime? dateFrom,
    DateTime? dateTo,
    String? categoryId,
    ExpenseStatus? status,
    ExpenseSource? source,
  }) async {
    try {
      await _fetchRemoteExpenses(
        tenantId: tenantId,
        branchId: branchId,
        dateFrom: dateFrom,
        dateTo: dateTo,
        categoryId: categoryId,
        status: status,
        source: source,
      ).timeout(_networkTimeout);
    } catch (_) {}
  }

  Future<List<ExpenseModel>> _fetchRemoteExpenses({
    required String tenantId,
    required String branchId,
    DateTime? dateFrom,
    DateTime? dateTo,
    String? categoryId,
    ExpenseStatus? status,
    ExpenseSource? source,
  }) async {
    var query = _client
        .from('expenses')
        .select()
        .eq('tenant_id', tenantId)
        .eq('branch_id', branchId);

    if (dateFrom != null) {
      query = query.gte('expense_date', _dateOnly(dateFrom));
    }

    if (dateTo != null) {
      query = query.lte('expense_date', _dateOnly(dateTo));
    }

    if (categoryId != null) {
      query = query.eq('category_id', categoryId);
    }

    if (status != null) {
      query = query.eq('status', status.code);
    }

    if (source != null) {
      query = query.eq('source', source.code);
    }

    final data = await query
        .order('expense_date', ascending: false)
        .order('created_at', ascending: false)
        .limit(200);

    final expenses =
        (data as List).map((row) => ExpenseModel.fromMap(row)).toList();

    for (var index = 0; index < expenses.length; index++) {
      var expense = expenses[index];
      final ruleId = expense.recurringRuleId;
      final dueDate = expense.recurringDueDate;
      if (ruleId == null || dueDate == null) continue;

      final localOccurrences = await ExpenseLocalStore.loadRecurringOccurrence(
        ruleId: ruleId,
        dueDate: dueDate,
      );
      final locallyVoided = localOccurrences.any(
        (local) => local.status == ExpenseStatus.voided,
      );
      if (locallyVoided && expense.status != ExpenseStatus.voided) {
        await _client.rpc('void_expense', params: {'p_expense_id': expense.id});
        expense = expense.copyWith(
          status: ExpenseStatus.voided,
          updatedAt: DateTime.now(),
        );
        expenses[index] = expense;
      }

      await ExpenseLocalStore.deleteRecurringOccurrenceDuplicates(
        ruleId: ruleId,
        dueDate: dueDate,
        keepExpenseId: expense.id,
      );
    }

    await ExpenseLocalStore.saveExpenses(expenses);

    return expenses;
  }

  Future<void> confirmExpense({
    required ExpenseModel expense,
    double? actualAmount,
    String? localReceiptPath,
  }) async {
    await _gate.require('expenses.core');
    if (localReceiptPath?.trim().isNotEmpty == true) {
      await _gate.require('expenses.receipts');
    }
    if (actualAmount != null && actualAmount < 0) {
      throw Exception('Expense amount cannot be negative.');
    }

    await ExpenseLocalStore.confirmExpenseLocally(
      expenseId: expense.id,
      confirmedBy: _currentUser.id,
      actualAmount: actualAmount,
      localReceiptPath: localReceiptPath,
    );

    final updatedLocal = await ExpenseLocalStore.loadExpenseById(expense.id);
    if (updatedLocal == null) {
      throw Exception('Expense not found');
    }

    try {
      final uploadedReceiptPath = await _uploadReceiptIfNeeded(
        expense: updatedLocal,
      );

      await _client
          .rpc(
            'confirm_expense',
            params: {
              'p_expense_id': expense.id,
              'p_actual_amount': actualAmount,
              'p_receipt_photo_path': uploadedReceiptPath,
            },
          )
          .timeout(_networkTimeout);

      final refreshed = await fetchExpenseById(expense.id);
      if (refreshed != null) {
        await ExpenseLocalStore.saveExpense(refreshed);
      }
    } catch (e) {
      OfflineErrorClassifier.rethrowIfTerminal(e);
      await OfflineStore.enqueueMutation(
        userId: _currentUser.id,
        type: 'confirm_expense',
        payload: {
          'expense_id': expense.id,
          'actual_amount': actualAmount,
          'local_receipt_path': localReceiptPath,
        },
      );

      debugPrint('Expense confirmation saved offline: $e');
    }
  }

  Future<void> voidExpense(ExpenseModel expense) async {
    await _gate.require('expenses.core');
    await ExpenseLocalStore.voidExpenseLocally(
      expenseId: expense.id,
      voidedBy: _currentUser.id,
    );

    try {
      await _client
          .rpc('void_expense', params: {'p_expense_id': expense.id})
          .timeout(_networkTimeout);
    } catch (e) {
      OfflineErrorClassifier.rethrowIfTerminal(e);
      try {
        await OfflineStore.enqueueMutation(
          userId: _currentUser.id,
          type: 'void_expense',
          payload: {
            'expense_id': expense.id,
            'recurring_rule_id': expense.recurringRuleId,
            'recurring_due_date':
                expense.recurringDueDate == null
                    ? null
                    : _dateOnly(expense.recurringDueDate!),
          },
        );
      } catch (queueError) {
        // The local void has already succeeded. Do not report it as failed
        // merely because another concurrent sync is writing the queue.
        debugPrint('Expense void queue save failed: $queueError');
      }

      debugPrint('Expense void saved offline: $e');
    }
  }

  // ════════════════════════════════════════
  // RECURRING EXPENSE RULES
  // ════════════════════════════════════════

  Future<RecurringExpenseRuleModel> createRecurringRule({
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
    await _gate.require('expenses.recurring');
    if (estimatedAmount < 0) {
      throw Exception('Estimated amount cannot be negative.');
    }

    if (intervalCount <= 0) {
      throw Exception('Interval must be greater than zero.');
    }

    if (reminderDaysBefore < 0) {
      throw Exception('Reminder days cannot be negative.');
    }

    final tenantId = await _tenantId();
    final branchId = await _branchId(tenantId);
    final now = DateTime.now();

    final rule = RecurringExpenseRuleModel(
      id: const Uuid().v4(),
      tenantId: tenantId,
      branchId: branchId,
      categoryId: categoryId,
      categoryName: categoryName.trim(),
      title: title.trim(),
      estimatedAmount: estimatedAmount,
      paymentMode: paymentMode,
      payee: _clean(payee),
      note: _clean(note),
      frequency: frequency,
      intervalCount: intervalCount,
      startDate: startDate,
      nextDueDate: startDate,
      endDate: endDate,
      reminderDaysBefore: reminderDaysBefore,
      status: 'active',
      createdBy: _currentUser.id,
      createdAt: now,
      updatedAt: now,
    );

    await ExpenseLocalStore.saveRecurringRule(rule);

    try {
      final data = await _client
          .from('recurring_expense_rules')
          .upsert(rule.toMap(), onConflict: 'id')
          .select()
          .single()
          .timeout(_networkTimeout);

      final saved = RecurringExpenseRuleModel.fromMap(data);
      await ExpenseLocalStore.saveRecurringRule(saved);
      return saved;
    } catch (e) {
      OfflineErrorClassifier.rethrowIfTerminal(e);
      await OfflineStore.enqueueMutation(
        userId: _currentUser.id,
        type: 'upsert_recurring_expense_rule',
        payload: rule.toMap(),
      );

      debugPrint('Recurring expense rule saved offline: $e');
      return rule;
    }
  }

  Future<List<RecurringExpenseRuleModel>> fetchRecurringRules({
    bool activeOnly = false,
  }) async {
    await _gate.require('expenses.recurring');
    final tenantId = await _tenantId();
    final branchId = await _branchId(tenantId);

    final cached = await ExpenseLocalStore.loadRecurringRules(
      branchId: branchId,
      activeOnly: activeOnly,
    );

    if (cached.isNotEmpty) {
      unawaited(_refreshRecurringRules(tenantId: tenantId, branchId: branchId));
      unawaited(syncOfflineMutations());
      return cached;
    }

    try {
      return await _fetchRemoteRecurringRules(
        tenantId: tenantId,
        branchId: branchId,
        activeOnly: activeOnly,
      ).timeout(_networkTimeout);
    } catch (_) {
      return ExpenseLocalStore.loadRecurringRules(
        branchId: branchId,
        activeOnly: activeOnly,
      );
    }
  }

  Future<void> _refreshRecurringRules({
    required String tenantId,
    required String branchId,
  }) async {
    try {
      await _fetchRemoteRecurringRules(
        tenantId: tenantId,
        branchId: branchId,
      ).timeout(_networkTimeout);
    } catch (_) {}
  }

  Future<List<RecurringExpenseRuleModel>> _fetchRemoteRecurringRules({
    required String tenantId,
    required String branchId,
    bool activeOnly = false,
  }) async {
    var query = _client
        .from('recurring_expense_rules')
        .select()
        .eq('tenant_id', tenantId)
        .eq('branch_id', branchId);

    if (activeOnly) {
      query = query.eq('status', 'active');
    }

    final data = await query.order('next_due_date', ascending: true);

    final rules =
        (data as List)
            .map((row) => RecurringExpenseRuleModel.fromMap(row))
            .toList();

    await ExpenseLocalStore.saveRecurringRules(rules);

    return rules;
  }

  Future<int> generateDueRecurringDrafts() async {
    await _gate.require('expenses.recurring');
    final tenantId = await _tenantId();
    final branchId = await _branchId(tenantId);

    final localCount =
        await ExpenseLocalStore.generateDueRecurringDraftsLocally(
          tenantId: tenantId,
          branchId: branchId,
          userId: _currentUser.id,
        );

    try {
      final remoteCount = await _client
          .rpc(
            'generate_due_recurring_expenses',
            params: {'p_tenant_id': tenantId, 'p_branch_id': branchId},
          )
          .timeout(_networkTimeout);

      await _fetchRemoteExpenses(
        tenantId: tenantId,
        branchId: branchId,
        source: ExpenseSource.recurring,
      );

      await _fetchRemoteRecurringRules(tenantId: tenantId, branchId: branchId);

      return (remoteCount as num?)?.toInt() ?? localCount;
    } catch (e) {
      debugPrint('Recurring drafts generated locally: $e');
      return localCount;
    }
  }

  Future<void> updateRecurringRuleStatus({
    required RecurringExpenseRuleModel rule,
    required String status,
  }) async {
    await _gate.require('expenses.recurring');
    if (!['active', 'paused', 'cancelled'].contains(status)) {
      throw Exception('Invalid recurring rule status.');
    }

    switch (status) {
      case 'active':
        await ExpenseLocalStore.activateRecurringRule(rule.id);
        break;
      case 'paused':
        await ExpenseLocalStore.pauseRecurringRule(rule.id);
        break;
      case 'cancelled':
        await ExpenseLocalStore.cancelRecurringRule(rule.id);
        break;
    }

    try {
      await _client
          .from('recurring_expense_rules')
          .update({
            'status': status,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', rule.id)
          .timeout(_networkTimeout);
    } catch (e) {
      OfflineErrorClassifier.rethrowIfTerminal(e);
      await OfflineStore.enqueueMutation(
        userId: _currentUser.id,
        type: 'update_recurring_expense_rule_status',
        payload: {'rule_id': rule.id, 'status': status},
      );

      debugPrint('Recurring rule status saved offline: $e');
    }
  }

  // ════════════════════════════════════════
  // REPORT
  // ════════════════════════════════════════

  Future<ExpenseProfitReportModel> fetchReport({
    required DateTime dateFrom,
    required DateTime dateTo,
    String? categoryId,
  }) async {
    await _gate.require('expenses.reporting');
    final tenantId = await _tenantId();
    final branchId = await _branchId(tenantId);
    final plan = await _tenantPlan(tenantId);

    final historyLimit = await _entitlements.getLimit('expenses.history_days');
    _validateReportRange(
      historyLimit: historyLimit,
      dateFrom: dateFrom,
      dateTo: dateTo,
    );

    try {
      final data = await _client
          .rpc(
            'get_expense_profit_report',
            params: {
              'p_tenant_id': tenantId,
              'p_branch_id': branchId,
              'p_date_from': _dateOnly(dateFrom),
              'p_date_to': _dateOnly(dateTo),
              'p_category_id': categoryId,
            },
          )
          .timeout(_networkTimeout);

      return ExpenseProfitReportModel.fromMap(
        Map<String, dynamic>.from(data as Map),
      );
    } catch (_) {
      return ExpenseLocalStore.loadReportLocally(
        tenantId: tenantId,
        branchId: branchId,
        dateFrom: dateFrom,
        dateTo: dateTo,
        plan: plan,
        categoryId: categoryId,
      );
    }
  }

  void _validateReportRange({
    required num? historyLimit,
    required DateTime dateFrom,
    required DateTime dateTo,
  }) {
    if (dateTo.isBefore(dateFrom)) {
      throw Exception('Invalid date range.');
    }

    final days = dateTo.difference(dateFrom).inDays + 1;

    if (historyLimit != null && days > historyLimit) {
      if (historyLimit == 30) {
        throw Exception('Starter plan can view only last 30 days.');
      }
      if (historyLimit == 365) {
        throw Exception('Business plan can view up to 1 year.');
      }
      throw Exception(
        'Expense history is limited to ${historyLimit.toInt()} days.',
      );
    }
  }

  // ════════════════════════════════════════
  // OFFLINE MUTATION SYNC
  // ════════════════════════════════════════

  Future<void> syncOfflineMutations() async {
    final userId = _currentUser.id;
    final mutations = await OfflineStore.loadMutations(userId);

    if (mutations.isEmpty) return;

    final remaining = <OfflineMutation>[];

    for (final mutation in mutations) {
      try {
        switch (mutation.type) {
          case 'upsert_expense_category':
            await _syncCategory(mutation.payload);
            break;

          case 'upsert_expense':
            await _syncExpense(mutation.payload);
            break;

          case 'confirm_expense':
            await _syncConfirmExpense(mutation.payload);
            break;

          case 'void_expense':
            await _syncVoidExpense(mutation.payload);
            break;

          case 'upsert_recurring_expense_rule':
            await _syncRecurringRule(mutation.payload);
            break;

          case 'update_recurring_expense_rule_status':
            await _syncRecurringRuleStatus(mutation.payload);
            break;

          default:
            remaining.add(mutation);
        }
      } catch (e) {
        debugPrint('Expense mutation sync failed: $e');
        remaining.add(mutation);
      }
    }

    await OfflineStore.saveMutations(userId, remaining);
  }

  Future<void> _syncCategory(Map<String, dynamic> payload) async {
    final data =
        await _client
            .from('expense_categories')
            .upsert(payload, onConflict: 'id')
            .select()
            .single();

    await ExpenseLocalStore.saveCategory(ExpenseCategoryModel.fromMap(data));
  }

  Future<void> _syncExpense(Map<String, dynamic> payload) async {
    final queuedExpense = ExpenseModel.fromMap(payload);
    final remote = await _loadRemoteExpense(queuedExpense.id);
    if (remote?.status == ExpenseStatus.voided) {
      await ExpenseLocalStore.saveExpense(remote!);
      return;
    }
    // A later local action (for example void) may have changed the expense
    // after this upsert was queued. Never replay the stale queued status over
    // the current local state.
    final expense =
        await ExpenseLocalStore.loadExpenseById(queuedExpense.id) ??
        queuedExpense;

    final uploadedReceiptPath = await _uploadReceiptIfNeeded(expense: expense);

    final remoteExpense = expense.copyWith(
      receiptPhotoPath: uploadedReceiptPath ?? expense.receiptPhotoPath,
      updatedAt: DateTime.now(),
    );

    final data =
        await _client
            .from('expenses')
            .upsert(remoteExpense.toRemoteInsertMap(), onConflict: 'id')
            .select()
            .single();

    await ExpenseLocalStore.saveExpenses([ExpenseModel.fromMap(data)]);
  }

  Future<void> _syncConfirmExpense(Map<String, dynamic> payload) async {
    final expenseId = payload['expense_id'] as String;
    final actualAmount = (payload['actual_amount'] as num?)?.toDouble();
    final localReceiptPath = payload['local_receipt_path'] as String?;

    final local = await ExpenseLocalStore.loadExpenseById(expenseId);

    // A queued confirmation is obsolete once the expense has subsequently
    // been voided locally.
    if (local?.status == ExpenseStatus.voided) return;

    final remote = await _loadRemoteExpense(expenseId);
    if (remote?.status == ExpenseStatus.voided) {
      await ExpenseLocalStore.saveExpense(remote!);
      return;
    }

    String? uploadedReceiptPath;

    if (local != null) {
      uploadedReceiptPath = await _uploadReceiptIfNeeded(
        expense: local.copyWith(
          localReceiptPath: localReceiptPath ?? local.localReceiptPath,
        ),
      );
    }

    await _client.rpc(
      'confirm_expense',
      params: {
        'p_expense_id': expenseId,
        'p_actual_amount': actualAmount,
        'p_receipt_photo_path': uploadedReceiptPath,
      },
    );

    final refreshed = await fetchExpenseById(expenseId);
    if (refreshed != null) {
      await ExpenseLocalStore.saveExpense(refreshed);
    }
  }

  Future<void> _syncVoidExpense(Map<String, dynamic> payload) async {
    var expenseId = payload['expense_id'] as String;
    if (!_isUuid(expenseId)) {
      final local = await ExpenseLocalStore.loadExpenseById(expenseId);
      final ruleId =
          payload['recurring_rule_id'] as String? ?? local?.recurringRuleId;
      final dueDate =
          payload['recurring_due_date'] as String? ??
          (local?.recurringDueDate == null
              ? null
              : _dateOnly(local!.recurringDueDate!));
      if (ruleId == null || dueDate == null) {
        throw Exception('Offline recurring expense identity is incomplete.');
      }

      final remote = await _client
          .from('expenses')
          .select('id')
          .eq('recurring_rule_id', ruleId)
          .eq('recurring_due_date', dueDate)
          .maybeSingle();
      if (remote == null) {
        throw Exception('Recurring expense is not generated remotely yet.');
      }
      expenseId = remote['id'] as String;
    }

    await _client.rpc(
      'void_expense',
      params: {'p_expense_id': expenseId},
    );
  }

  Future<ExpenseModel?> _loadRemoteExpense(String expenseId) async {
    final data =
        await _client
            .from('expenses')
            .select()
            .eq('id', expenseId)
            .maybeSingle();
    return data == null ? null : ExpenseModel.fromMap(data);
  }

  bool _isUuid(String value) => RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
  ).hasMatch(value);

  Future<void> _syncRecurringRule(Map<String, dynamic> payload) async {
    final data =
        await _client
            .from('recurring_expense_rules')
            .upsert(payload, onConflict: 'id')
            .select()
            .single();

    await ExpenseLocalStore.saveRecurringRule(
      RecurringExpenseRuleModel.fromMap(data),
    );
  }

  Future<void> _syncRecurringRuleStatus(Map<String, dynamic> payload) async {
    await _client
        .from('recurring_expense_rules')
        .update({
          'status': payload['status'],
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', payload['rule_id']);
  }

  // ════════════════════════════════════════
  // RECEIPT PHOTO UPLOAD
  // ════════════════════════════════════════

  Future<String?> _uploadReceiptIfNeeded({
    required ExpenseModel expense,
  }) async {
    if (expense.localReceiptPath == null ||
        expense.localReceiptPath!.trim().isEmpty) {
      return expense.receiptPhotoPath;
    }

    final file = File(expense.localReceiptPath!);

    if (!await file.exists()) {
      return expense.receiptPhotoPath;
    }

    final extension = _extensionFromPath(expense.localReceiptPath!);

    final storagePath =
        '${expense.tenantId}/${expense.branchId}/${expense.id}/receipt$extension';

    await _client.storage
        .from(_receiptBucket)
        .upload(
          storagePath,
          file,
          fileOptions: const FileOptions(upsert: true),
        );

    return storagePath;
  }

  String _extensionFromPath(String path) {
    final dot = path.lastIndexOf('.');
    if (dot == -1) return '.jpg';
    return path.substring(dot);
  }

  // ════════════════════════════════════════
  // HELPERS
  // ════════════════════════════════════════

  String? _clean(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    return trimmed;
  }

  String _dateOnly(DateTime date) {
    final year = date.year.toString().padLeft(4, '0');
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }
}
