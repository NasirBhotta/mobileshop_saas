import 'package:mobileshop_saas/core/local/local_database.dart';

import '../models/expense_models.dart';

class ExpenseLocalStore {
  // ════════════════════════════════════════
  // EXPENSE CATEGORIES
  // ════════════════════════════════════════

  static Future<void> saveCategory(ExpenseCategoryModel category) async {
    await LocalDatabase.execute(
      '''
      INSERT OR REPLACE INTO expense_categories(
        id,
        tenant_id,
        branch_id,
        name,
        description,
        is_system,
        is_active,
        created_by,
        created_at,
        updated_at
      )
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''',
      [
        category.id,
        category.tenantId,
        category.branchId,
        category.name,
        category.description,
        category.isSystem ? 1 : 0,
        category.isActive ? 1 : 0,
        category.createdBy,
        category.createdAt?.toIso8601String(),
        category.updatedAt?.toIso8601String(),
      ],
    );
  }

  static Future<void> saveCategories(
    List<ExpenseCategoryModel> categories,
  ) async {
    for (final category in categories) {
      await saveCategory(category);
    }
  }

  static Future<List<ExpenseCategoryModel>> loadCategories({
    required String tenantId,
    String? branchId,
    bool activeOnly = true,
  }) async {
    final where = <String>['tenant_id = ?'];

    final args = <Object?>[tenantId];

    if (branchId != null) {
      where.add('(branch_id = ? OR branch_id IS NULL)');
      args.add(branchId);
    }

    if (activeOnly) {
      where.add('is_active = 1');
    }

    final rows = await LocalDatabase.select('''
      SELECT *
      FROM expense_categories
      WHERE ${where.join(' AND ')}
      ORDER BY is_system DESC, name ASC
      ''', args);

    return rows.map(ExpenseCategoryModel.fromMap).toList();
  }

  static Future<ExpenseCategoryModel?> loadCategoryById(
    String categoryId,
  ) async {
    final rows = await LocalDatabase.select(
      '''
      SELECT *
      FROM expense_categories
      WHERE id = ?
      LIMIT 1
      ''',
      [categoryId],
    );

    if (rows.isEmpty) return null;
    return ExpenseCategoryModel.fromMap(rows.first);
  }

  static Future<void> replaceCategoryId({
    required String oldId,
    required ExpenseCategoryModel replacement,
  }) async {
    if (oldId == replacement.id) {
      await saveCategory(replacement);
      return;
    }

    await saveCategory(replacement);
    await LocalDatabase.execute(
      'UPDATE expenses SET category_id = ? WHERE category_id = ?',
      [replacement.id, oldId],
    );
    await LocalDatabase.execute(
      'UPDATE recurring_expense_rules SET category_id = ? WHERE category_id = ?',
      [replacement.id, oldId],
    );
    await LocalDatabase.execute('DELETE FROM expense_categories WHERE id = ?', [
      oldId,
    ]);
  }

  // ════════════════════════════════════════
  // EXPENSES
  // ════════════════════════════════════════

  static Future<void> saveExpense(ExpenseModel expense) async {
    await LocalDatabase.execute(
      '''
      INSERT OR REPLACE INTO expenses(
        id,
        tenant_id,
        branch_id,
        category_id,
        category_name,
        title,
        expense_date,
        amount,
        payment_mode,
        payee,
        notes,
        receipt_photo_path,
        local_receipt_path,
        status,
        source,
        recurring_rule_id,
        recurring_due_date,
        created_by,
        confirmed_by,
        voided_by,
        confirmed_at,
        voided_at,
        created_at,
        updated_at
      )
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''',
      [
        expense.id,
        expense.tenantId,
        expense.branchId,
        expense.categoryId,
        expense.categoryName,
        expense.title,
        _dateOnly(expense.expenseDate),
        expense.amount,
        expense.paymentMode.code,
        expense.payee,
        expense.notes,
        expense.receiptPhotoPath,
        expense.localReceiptPath,
        expense.status.code,
        expense.source.code,
        expense.recurringRuleId,
        expense.recurringDueDate == null
            ? null
            : _dateOnly(expense.recurringDueDate!),
        expense.createdBy,
        expense.confirmedBy,
        expense.voidedBy,
        expense.confirmedAt?.toIso8601String(),
        expense.voidedAt?.toIso8601String(),
        expense.createdAt?.toIso8601String(),
        expense.updatedAt?.toIso8601String(),
      ],
    );
  }

  static Future<void> saveExpenses(List<ExpenseModel> expenses) async {
    for (final expense in expenses) {
      final existing = await loadExpenseById(expense.id);
      final localUpdatedAt = existing?.updatedAt;
      final remoteUpdatedAt = expense.updatedAt;
      if (localUpdatedAt != null &&
          remoteUpdatedAt != null &&
          localUpdatedAt.isAfter(remoteUpdatedAt)) {
        continue;
      }
      await saveExpense(expense);
    }
  }

  static Future<List<ExpenseModel>> loadExpenses({
    required String branchId,
    DateTime? dateFrom,
    DateTime? dateTo,
    String? categoryId,
    ExpenseStatus? status,
    ExpenseSource? source,
    int limit = 200,
  }) async {
    final where = <String>['branch_id = ?'];

    final args = <Object?>[branchId];

    if (dateFrom != null) {
      where.add('expense_date >= ?');
      args.add(_dateOnly(dateFrom));
    }

    if (dateTo != null) {
      where.add('expense_date <= ?');
      args.add(_dateOnly(dateTo));
    }

    if (categoryId != null) {
      where.add('category_id = ?');
      args.add(categoryId);
    }

    if (status != null) {
      where.add('status = ?');
      args.add(status.code);
    }

    if (source != null) {
      where.add('source = ?');
      args.add(source.code);
    }

    args.add(limit);

    final rows = await LocalDatabase.select('''
      SELECT *
      FROM expenses
      WHERE ${where.join(' AND ')}
      ORDER BY expense_date DESC, created_at DESC
      LIMIT ?
      ''', args);

    return rows.map(ExpenseModel.fromMap).toList();
  }

  static Future<ExpenseModel?> loadExpenseById(String expenseId) async {
    final rows = await LocalDatabase.select(
      '''
      SELECT *
      FROM expenses
      WHERE id = ?
      LIMIT 1
      ''',
      [expenseId],
    );

    if (rows.isEmpty) return null;
    return ExpenseModel.fromMap(rows.first);
  }

  static Future<List<ExpenseModel>> loadRecurringOccurrence({
    required String ruleId,
    required DateTime dueDate,
  }) async {
    final rows = await LocalDatabase.select(
      '''
      SELECT *
      FROM expenses
      WHERE recurring_rule_id = ?
        AND recurring_due_date = ?
      ''',
      [ruleId, _dateOnly(dueDate)],
    );
    return rows.map(ExpenseModel.fromMap).toList();
  }

  static Future<void> deleteRecurringOccurrenceDuplicates({
    required String ruleId,
    required DateTime dueDate,
    required String keepExpenseId,
  }) async {
    await LocalDatabase.execute(
      '''
      DELETE FROM expenses
      WHERE recurring_rule_id = ?
        AND recurring_due_date = ?
        AND id <> ?
      ''',
      [ruleId, _dateOnly(dueDate), keepExpenseId],
    );
  }

  static Future<void> confirmExpenseLocally({
    required String expenseId,
    required String confirmedBy,
    double? actualAmount,
    String? receiptPhotoPath,
    String? localReceiptPath,
  }) async {
    final existing = await loadExpenseById(expenseId);
    if (existing == null) {
      throw Exception('Expense not found');
    }

    if (actualAmount != null && actualAmount < 0) {
      throw Exception('Expense amount cannot be negative');
    }

    final now = DateTime.now();

    final updated = existing.copyWith(
      amount: actualAmount ?? existing.amount,
      receiptPhotoPath: receiptPhotoPath ?? existing.receiptPhotoPath,
      localReceiptPath: localReceiptPath ?? existing.localReceiptPath,
      status: ExpenseStatus.confirmed,
      confirmedBy: confirmedBy,
      confirmedAt: now,
      updatedAt: now,
    );

    await saveExpense(updated);
  }

  static Future<void> voidExpenseLocally({
    required String expenseId,
    required String voidedBy,
  }) async {
    final existing = await loadExpenseById(expenseId);
    if (existing == null) {
      throw Exception('Expense not found');
    }

    final now = DateTime.now();

    await LocalDatabase.execute(
      '''
      UPDATE expenses
      SET status = ?,
          voided_by = ?,
          voided_at = ?,
          updated_at = ?
      WHERE id = ?
      ''',
      [
        ExpenseStatus.voided.code,
        voidedBy,
        now.toIso8601String(),
        now.toIso8601String(),
        expenseId,
      ],
    );
  }

  // ════════════════════════════════════════
  // RECURRING EXPENSE RULES
  // ════════════════════════════════════════

  static Future<void> saveRecurringRule(RecurringExpenseRuleModel rule) async {
    await LocalDatabase.execute(
      '''
      INSERT OR REPLACE INTO recurring_expense_rules(
        id,
        tenant_id,
        branch_id,
        category_id,
        category_name,
        title,
        estimated_amount,
        payment_mode,
        payee,
        note,
        frequency,
        interval_count,
        start_date,
        end_date,
        next_due_date,
        reminder_days_before,
        status,
        created_by,
        created_at,
        updated_at
      )
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''',
      [
        rule.id,
        rule.tenantId,
        rule.branchId,
        rule.categoryId,
        rule.categoryName,
        rule.title,
        rule.estimatedAmount,
        rule.paymentMode.code,
        rule.payee,
        rule.note,
        rule.frequency.code,
        rule.intervalCount,
        _dateOnly(rule.startDate),
        rule.endDate == null ? null : _dateOnly(rule.endDate!),
        _dateOnly(rule.nextDueDate),
        rule.reminderDaysBefore,
        rule.status,
        rule.createdBy,
        rule.createdAt?.toIso8601String(),
        rule.updatedAt?.toIso8601String(),
      ],
    );
  }

  static Future<void> saveRecurringRules(
    List<RecurringExpenseRuleModel> rules,
  ) async {
    for (final rule in rules) {
      await saveRecurringRule(rule);
    }
  }

  static Future<List<RecurringExpenseRuleModel>> loadRecurringRules({
    required String branchId,
    bool activeOnly = false,
  }) async {
    final rows =
        activeOnly
            ? await LocalDatabase.select(
              '''
            SELECT *
            FROM recurring_expense_rules
            WHERE branch_id = ?
              AND status = 'active'
            ORDER BY next_due_date ASC
            ''',
              [branchId],
            )
            : await LocalDatabase.select(
              '''
            SELECT *
            FROM recurring_expense_rules
            WHERE branch_id = ?
            ORDER BY next_due_date ASC
            ''',
              [branchId],
            );

    return rows.map(RecurringExpenseRuleModel.fromMap).toList();
  }

  static Future<RecurringExpenseRuleModel?> loadRecurringRuleById(
    String ruleId,
  ) async {
    final rows = await LocalDatabase.select(
      '''
      SELECT *
      FROM recurring_expense_rules
      WHERE id = ?
      LIMIT 1
      ''',
      [ruleId],
    );

    if (rows.isEmpty) return null;
    return RecurringExpenseRuleModel.fromMap(rows.first);
  }

  static Future<void> updateRecurringRuleNextDueDate({
    required String ruleId,
    required DateTime nextDueDate,
  }) async {
    await LocalDatabase.execute(
      '''
      UPDATE recurring_expense_rules
      SET next_due_date = ?,
          updated_at = ?
      WHERE id = ?
      ''',
      [_dateOnly(nextDueDate), DateTime.now().toIso8601String(), ruleId],
    );
  }

  static Future<void> pauseRecurringRule(String ruleId) async {
    await _updateRecurringRuleStatus(ruleId, 'paused');
  }

  static Future<void> cancelRecurringRule(String ruleId) async {
    await _updateRecurringRuleStatus(ruleId, 'cancelled');
  }

  static Future<void> activateRecurringRule(String ruleId) async {
    await _updateRecurringRuleStatus(ruleId, 'active');
  }

  static Future<void> _updateRecurringRuleStatus(
    String ruleId,
    String status,
  ) async {
    await LocalDatabase.execute(
      '''
      UPDATE recurring_expense_rules
      SET status = ?,
          updated_at = ?
      WHERE id = ?
      ''',
      [status, DateTime.now().toIso8601String(), ruleId],
    );
  }

  // ════════════════════════════════════════
  // LOCAL RECURRING DRAFT GENERATION
  // ════════════════════════════════════════

  static Future<int> generateDueRecurringDraftsLocally({
    required String tenantId,
    required String branchId,
    required String userId,
  }) async {
    final today = DateTime.now();

    final rules = await loadRecurringRules(
      branchId: branchId,
      activeOnly: true,
    );

    var createdCount = 0;

    await LocalDatabase.execute(
      '''
      UPDATE expenses
      SET status = ?,
          confirmed_by = COALESCE(confirmed_by, ?),
          confirmed_at = COALESCE(confirmed_at, ?),
          updated_at = ?
      WHERE branch_id = ?
        AND source = ?
        AND status = ?
        AND expense_date <= ?
      ''',
      [
        ExpenseStatus.confirmed.code,
        userId,
        today.toIso8601String(),
        today.toIso8601String(),
        branchId,
        ExpenseSource.recurring.code,
        ExpenseStatus.draft.code,
        _dateOnly(today),
      ],
    );

    for (final rule in rules) {
      final reminderDate = today.add(Duration(days: rule.reminderDaysBefore));

      var dueDate = rule.nextDueDate;
      while (!dueDate.isAfter(reminderDate) &&
          (rule.endDate == null || !dueDate.isAfter(rule.endDate!))) {
        final alreadyExists = await _recurringDraftExists(
          ruleId: rule.id,
          dueDate: dueDate,
        );

        if (!alreadyExists) {
          final now = DateTime.now();
          final isDue = !dueDate.isAfter(today);

          await saveExpense(
            ExpenseModel(
              id: _localId(),
              tenantId: tenantId,
              branchId: branchId,
              categoryId: rule.categoryId,
              categoryName: rule.categoryName,
              title: rule.title,
              expenseDate: dueDate,
              amount: rule.estimatedAmount,
              paymentMode: rule.paymentMode,
              payee: rule.payee,
              notes: rule.note,
              status: isDue ? ExpenseStatus.confirmed : ExpenseStatus.draft,
              source: ExpenseSource.recurring,
              recurringRuleId: rule.id,
              recurringDueDate: dueDate,
              createdBy: userId,
              confirmedBy: isDue ? userId : null,
              confirmedAt: isDue ? now : null,
              createdAt: now,
              updatedAt: now,
            ),
          );
          createdCount++;
        }

        dueDate = _nextRecurringDate(
          dueDate,
          rule.frequency,
          rule.intervalCount,
        );
      }

      await updateRecurringRuleNextDueDate(
        ruleId: rule.id,
        nextDueDate: dueDate,
      );
    }

    return createdCount;
  }

  static Future<bool> _recurringDraftExists({
    required String ruleId,
    required DateTime dueDate,
  }) async {
    final rows = await LocalDatabase.select(
      '''
      SELECT id
      FROM expenses
      WHERE recurring_rule_id = ?
        AND recurring_due_date = ?
      LIMIT 1
      ''',
      [ruleId, _dateOnly(dueDate)],
    );

    return rows.isNotEmpty;
  }

  static DateTime _nextRecurringDate(
    DateTime current,
    RecurringExpenseFrequency frequency,
    int intervalCount,
  ) {
    switch (frequency) {
      case RecurringExpenseFrequency.daily:
        return current.add(Duration(days: intervalCount));

      case RecurringExpenseFrequency.weekly:
        return current.add(Duration(days: intervalCount * 7));

      case RecurringExpenseFrequency.monthly:
        return DateTime(
          current.year,
          current.month + intervalCount,
          current.day,
        );

      case RecurringExpenseFrequency.yearly:
        return DateTime(
          current.year + intervalCount,
          current.month,
          current.day,
        );
    }
  }

  // ════════════════════════════════════════
  // LOCAL EXPENSE + PROFIT REPORT
  // ════════════════════════════════════════

  static Future<ExpenseProfitReportModel> loadReportLocally({
    required String tenantId,
    required String branchId,
    required DateTime dateFrom,
    required DateTime dateTo,
    String plan = 'starter',
    String? categoryId,
  }) async {
    final from = _dateOnly(dateFrom);
    final to = _dateOnly(dateTo);

    final expenseArgs = <Object?>[branchId, from, to];

    var categoryFilter = '';

    if (categoryId != null) {
      categoryFilter = 'AND category_id = ?';
      expenseArgs.add(categoryId);
    }

    final totalExpensesRows = await LocalDatabase.select('''
      SELECT COALESCE(SUM(amount), 0) AS total
      FROM expenses
      WHERE branch_id = ?
        AND status = 'confirmed'
        AND expense_date BETWEEN ? AND ?
        $categoryFilter
      ''', expenseArgs);

    final draftExpensesRows = await LocalDatabase.select('''
      SELECT COALESCE(SUM(amount), 0) AS total
      FROM expenses
      WHERE branch_id = ?
        AND status = 'draft'
        AND expense_date BETWEEN ? AND ?
        $categoryFilter
      ''', expenseArgs);

    final byCategoryRows = await LocalDatabase.select('''
      SELECT
        COALESCE(category_name, 'Uncategorized') AS label,
        COALESCE(SUM(amount), 0) AS total
      FROM expenses
      WHERE branch_id = ?
        AND status = 'confirmed'
        AND expense_date BETWEEN ? AND ?
        $categoryFilter
      GROUP BY COALESCE(category_name, 'Uncategorized')
      ORDER BY total DESC
      ''', expenseArgs);

    final byPaymentRows = await LocalDatabase.select('''
      SELECT
        payment_mode AS label,
        COALESCE(SUM(amount), 0) AS total
      FROM expenses
      WHERE branch_id = ?
        AND status = 'confirmed'
        AND expense_date BETWEEN ? AND ?
        $categoryFilter
      GROUP BY payment_mode
      ORDER BY total DESC
      ''', expenseArgs);

    final salesRows = await LocalDatabase.select(
      '''
      SELECT COALESCE(SUM(total), 0) AS total
      FROM sales
      WHERE branch_id = ?
        AND status = 'completed'
        AND substr(created_at, 1, 10) BETWEEN ? AND ?
      ''',
      [branchId, from, to],
    );

    final cogsRows = await LocalDatabase.select(
      '''
      SELECT COALESCE(
        SUM(
          COALESCE(
            si.cogs_total,
            si.unit_cost_at_sale * si.quantity,
            p.cost_price * si.quantity,
            0
          )
        ),
        0
      ) AS total
      FROM sale_items si
      JOIN sales s ON s.id = si.sale_id
      LEFT JOIN products p ON p.id = si.product_id
      WHERE s.branch_id = ?
        AND s.status = 'completed'
        AND substr(s.created_at, 1, 10) BETWEEN ? AND ?
      ''',
      [branchId, from, to],
    );

    final totalExpenses = _num(totalExpensesRows.first['total']);
    final draftExpenses = _num(draftExpensesRows.first['total']);
    final salesRevenue = _num(salesRows.first['total']);
    final cogs = _num(cogsRows.first['total']);
    final grossProfit = salesRevenue - cogs;
    final netProfit = grossProfit - totalExpenses;

    return ExpenseProfitReportModel(
      tenantId: tenantId,
      branchId: branchId,
      dateFrom: dateFrom,
      dateTo: dateTo,
      plan: plan,
      totalExpenses: totalExpenses,
      draftExpenses: draftExpenses,
      salesRevenue: salesRevenue,
      cogs: cogs,
      grossProfit: grossProfit,
      netProfit: netProfit,
      byCategory:
          byCategoryRows.map((row) {
            return ExpenseReportBreakdownItem(
              label: (row['label'] as String?) ?? 'Uncategorized',
              total: _num(row['total']),
            );
          }).toList(),
      byPaymentMode:
          byPaymentRows.map((row) {
            final mode = ExpensePaymentModeX.fromCode(row['label'] as String?);

            return ExpenseReportBreakdownItem(
              label: mode.label,
              total: _num(row['total']),
            );
          }).toList(),
    );
  }

  // ════════════════════════════════════════
  // HELPERS
  // ════════════════════════════════════════

  static String _dateOnly(DateTime date) {
    final year = date.year.toString().padLeft(4, '0');
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  static double _num(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? 0;
  }

  static String _localId() {
    return DateTime.now().microsecondsSinceEpoch.toString();
  }
}
