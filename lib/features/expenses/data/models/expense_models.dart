enum ExpensePaymentMode {
  cash,
  card,
  bankTransfer,
  easypaisa,
  jazzcash,
  cheque,
  other,
}

extension ExpensePaymentModeX on ExpensePaymentMode {
  String get code {
    switch (this) {
      case ExpensePaymentMode.cash:
        return 'cash';
      case ExpensePaymentMode.card:
        return 'card';
      case ExpensePaymentMode.bankTransfer:
        return 'bank_transfer';
      case ExpensePaymentMode.easypaisa:
        return 'easypaisa';
      case ExpensePaymentMode.jazzcash:
        return 'jazzcash';
      case ExpensePaymentMode.cheque:
        return 'cheque';
      case ExpensePaymentMode.other:
        return 'other';
    }
  }

  String get label {
    switch (this) {
      case ExpensePaymentMode.cash:
        return 'Cash';
      case ExpensePaymentMode.card:
        return 'Card';
      case ExpensePaymentMode.bankTransfer:
        return 'Bank Transfer';
      case ExpensePaymentMode.easypaisa:
        return 'Easypaisa';
      case ExpensePaymentMode.jazzcash:
        return 'JazzCash';
      case ExpensePaymentMode.cheque:
        return 'Cheque';
      case ExpensePaymentMode.other:
        return 'Other';
    }
  }

  static ExpensePaymentMode fromCode(String? code) {
    switch (code) {
      case 'card':
        return ExpensePaymentMode.card;
      case 'bank_transfer':
        return ExpensePaymentMode.bankTransfer;
      case 'easypaisa':
        return ExpensePaymentMode.easypaisa;
      case 'jazzcash':
        return ExpensePaymentMode.jazzcash;
      case 'cheque':
        return ExpensePaymentMode.cheque;
      case 'other':
        return ExpensePaymentMode.other;
      case 'cash':
      default:
        return ExpensePaymentMode.cash;
    }
  }
}

enum ExpenseStatus { draft, confirmed, voided }

extension ExpenseStatusX on ExpenseStatus {
  String get code {
    switch (this) {
      case ExpenseStatus.draft:
        return 'draft';
      case ExpenseStatus.confirmed:
        return 'confirmed';
      case ExpenseStatus.voided:
        return 'void';
    }
  }

  String get label {
    switch (this) {
      case ExpenseStatus.draft:
        return 'Draft';
      case ExpenseStatus.confirmed:
        return 'Confirmed';
      case ExpenseStatus.voided:
        return 'Void';
    }
  }

  static ExpenseStatus fromCode(String? code) {
    switch (code) {
      case 'draft':
        return ExpenseStatus.draft;
      case 'void':
        return ExpenseStatus.voided;
      case 'confirmed':
      default:
        return ExpenseStatus.confirmed;
    }
  }
}

enum ExpenseSource { manual, recurring }

extension ExpenseSourceX on ExpenseSource {
  String get code {
    switch (this) {
      case ExpenseSource.manual:
        return 'manual';
      case ExpenseSource.recurring:
        return 'recurring';
    }
  }

  String get label {
    switch (this) {
      case ExpenseSource.manual:
        return 'Manual';
      case ExpenseSource.recurring:
        return 'Recurring';
    }
  }

  static ExpenseSource fromCode(String? code) {
    switch (code) {
      case 'recurring':
        return ExpenseSource.recurring;
      case 'manual':
      default:
        return ExpenseSource.manual;
    }
  }
}

enum RecurringExpenseFrequency { daily, weekly, monthly, yearly }

extension RecurringExpenseFrequencyX on RecurringExpenseFrequency {
  String get code {
    switch (this) {
      case RecurringExpenseFrequency.daily:
        return 'daily';
      case RecurringExpenseFrequency.weekly:
        return 'weekly';
      case RecurringExpenseFrequency.monthly:
        return 'monthly';
      case RecurringExpenseFrequency.yearly:
        return 'yearly';
    }
  }

  String get label {
    switch (this) {
      case RecurringExpenseFrequency.daily:
        return 'Daily';
      case RecurringExpenseFrequency.weekly:
        return 'Weekly';
      case RecurringExpenseFrequency.monthly:
        return 'Monthly';
      case RecurringExpenseFrequency.yearly:
        return 'Yearly';
    }
  }

  static RecurringExpenseFrequency fromCode(String? code) {
    switch (code) {
      case 'daily':
        return RecurringExpenseFrequency.daily;
      case 'weekly':
        return RecurringExpenseFrequency.weekly;
      case 'yearly':
        return RecurringExpenseFrequency.yearly;
      case 'monthly':
      default:
        return RecurringExpenseFrequency.monthly;
    }
  }
}

class ExpenseCategoryModel {
  final String id;
  final String tenantId;
  final String? branchId;
  final String name;
  final String? description;
  final bool isSystem;
  final bool isActive;
  final String? createdBy;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const ExpenseCategoryModel({
    required this.id,
    required this.tenantId,
    this.branchId,
    required this.name,
    this.description,
    this.isSystem = false,
    this.isActive = true,
    this.createdBy,
    this.createdAt,
    this.updatedAt,
  });

  factory ExpenseCategoryModel.fromMap(Map<String, dynamic> map) {
    return ExpenseCategoryModel(
      id: map['id'] as String,
      tenantId: map['tenant_id'] as String,
      branchId: map['branch_id'] as String?,
      name: map['name'] as String,
      description: map['description'] as String?,
      isSystem: _bool(map['is_system']),
      isActive: _bool(map['is_active'], defaultValue: true),
      createdBy: map['created_by'] as String?,
      createdAt: _date(map['created_at']),
      updatedAt: _date(map['updated_at']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'tenant_id': tenantId,
      'branch_id': branchId,
      'name': name,
      'description': description,
      'is_system': isSystem,
      'is_active': isActive,
      'created_by': createdBy,
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }
}

class ExpenseModel {
  final String id;
  final String tenantId;
  final String branchId;

  final String? categoryId;
  final String? categoryName;

  final String title;
  final DateTime expenseDate;
  final double amount;

  final ExpensePaymentMode paymentMode;

  final String? payee;
  final String? notes;

  /// Remote Supabase Storage path.
  final String? receiptPhotoPath;

  /// Local device file path used before upload/sync.
  final String? localReceiptPath;

  final ExpenseStatus status;
  final ExpenseSource source;

  /// Existing DB table is recurring_expense_rules.
  final String? recurringRuleId;
  final DateTime? recurringDueDate;

  final String? createdBy;
  final String? confirmedBy;
  final String? voidedBy;

  final DateTime? confirmedAt;
  final DateTime? voidedAt;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  const ExpenseModel({
    required this.id,
    required this.tenantId,
    required this.branchId,
    this.categoryId,
    this.categoryName,
    required this.title,
    required this.expenseDate,
    required this.amount,
    this.paymentMode = ExpensePaymentMode.cash,
    this.payee,
    this.notes,
    this.receiptPhotoPath,
    this.localReceiptPath,
    this.status = ExpenseStatus.confirmed,
    this.source = ExpenseSource.manual,
    this.recurringRuleId,
    this.recurringDueDate,
    this.createdBy,
    this.confirmedBy,
    this.voidedBy,
    this.confirmedAt,
    this.voidedAt,
    this.createdAt,
    this.updatedAt,
  });

  factory ExpenseModel.fromMap(Map<String, dynamic> map) {
    return ExpenseModel(
      id: map['id'] as String,
      tenantId: map['tenant_id'] as String,
      branchId: map['branch_id'] as String,
      categoryId: map['category_id'] as String?,
      categoryName: map['category_name'] as String?,
      title: map['title'] as String,
      expenseDate: _date(map['expense_date']) ?? DateTime.now(),
      amount: (map['amount'] as num?)?.toDouble() ?? 0,
      paymentMode: ExpensePaymentModeX.fromCode(map['payment_mode'] as String?),
      payee: map['payee'] as String?,
      notes: map['notes'] as String?,
      receiptPhotoPath: map['receipt_photo_path'] as String?,
      localReceiptPath: map['local_receipt_path'] as String?,
      status: ExpenseStatusX.fromCode(map['status'] as String?),
      source: ExpenseSourceX.fromCode(map['source'] as String?),
      recurringRuleId: map['recurring_rule_id'] as String?,
      recurringDueDate: _date(map['recurring_due_date']),
      createdBy: map['created_by'] as String?,
      confirmedBy: map['confirmed_by'] as String?,
      voidedBy: map['voided_by'] as String?,
      confirmedAt: _date(map['confirmed_at']),
      voidedAt: _date(map['voided_at']),
      createdAt: _date(map['created_at']),
      updatedAt: _date(map['updated_at']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'tenant_id': tenantId,
      'branch_id': branchId,
      'category_id': categoryId,
      'category_name': categoryName,
      'title': title,
      'expense_date': _dateOnly(expenseDate),
      'amount': amount,
      'payment_mode': paymentMode.code,
      'payee': payee,
      'notes': notes,
      'receipt_photo_path': receiptPhotoPath,
      'local_receipt_path': localReceiptPath,
      'status': status.code,
      'source': source.code,
      'recurring_rule_id': recurringRuleId,
      'recurring_due_date':
          recurringDueDate == null ? null : _dateOnly(recurringDueDate!),
      'created_by': createdBy,
      'confirmed_by': confirmedBy,
      'voided_by': voidedBy,
      'confirmed_at': confirmedAt?.toIso8601String(),
      'voided_at': voidedAt?.toIso8601String(),
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  Map<String, dynamic> toRemoteInsertMap() {
    final map = toMap();

    /// `local_receipt_path` app-only field hai.
    /// Supabase table mein column add kiya hai for convenience, but remote
    /// receipt sharing ke liye real value `receipt_photo_path` hai.
    return map;
  }

  ExpenseModel copyWith({
    String? categoryId,
    String? categoryName,
    String? title,
    DateTime? expenseDate,
    double? amount,
    ExpensePaymentMode? paymentMode,
    String? payee,
    String? notes,
    String? receiptPhotoPath,
    String? localReceiptPath,
    ExpenseStatus? status,
    String? confirmedBy,
    DateTime? confirmedAt,
    DateTime? updatedAt,
  }) {
    return ExpenseModel(
      id: id,
      tenantId: tenantId,
      branchId: branchId,
      categoryId: categoryId ?? this.categoryId,
      categoryName: categoryName ?? this.categoryName,
      title: title ?? this.title,
      expenseDate: expenseDate ?? this.expenseDate,
      amount: amount ?? this.amount,
      paymentMode: paymentMode ?? this.paymentMode,
      payee: payee ?? this.payee,
      notes: notes ?? this.notes,
      receiptPhotoPath: receiptPhotoPath ?? this.receiptPhotoPath,
      localReceiptPath: localReceiptPath ?? this.localReceiptPath,
      status: status ?? this.status,
      source: source,
      recurringRuleId: recurringRuleId,
      recurringDueDate: recurringDueDate,
      createdBy: createdBy,
      confirmedBy: confirmedBy ?? this.confirmedBy,
      voidedBy: voidedBy,
      confirmedAt: confirmedAt ?? this.confirmedAt,
      voidedAt: voidedAt,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

class RecurringExpenseRuleModel {
  final String id;
  final String tenantId;
  final String branchId;

  final String? categoryId;
  final String categoryName;

  final String title;
  final double estimatedAmount;

  final ExpensePaymentMode paymentMode;

  final String? payee;
  final String? note;

  final RecurringExpenseFrequency frequency;
  final int intervalCount;

  final DateTime startDate;
  final DateTime? endDate;
  final DateTime nextDueDate;

  final int reminderDaysBefore;

  /// Existing DB uses status: active / paused / cancelled.
  final String status;

  final String? createdBy;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const RecurringExpenseRuleModel({
    required this.id,
    required this.tenantId,
    required this.branchId,
    this.categoryId,
    required this.categoryName,
    required this.title,
    required this.estimatedAmount,
    this.paymentMode = ExpensePaymentMode.cash,
    this.payee,
    this.note,
    this.frequency = RecurringExpenseFrequency.monthly,
    this.intervalCount = 1,
    required this.startDate,
    this.endDate,
    required this.nextDueDate,
    this.reminderDaysBefore = 3,
    this.status = 'active',
    this.createdBy,
    this.createdAt,
    this.updatedAt,
  });

  factory RecurringExpenseRuleModel.fromMap(Map<String, dynamic> map) {
    return RecurringExpenseRuleModel(
      id: map['id'] as String,
      tenantId: map['tenant_id'] as String,
      branchId: map['branch_id'] as String,
      categoryId: map['category_id'] as String?,
      categoryName: map['category_name'] as String,
      title:
          (map['title'] as String?) ??
          (map['category_name'] as String?) ??
          'Recurring Expense',
      estimatedAmount: (map['estimated_amount'] as num?)?.toDouble() ?? 0,
      paymentMode: ExpensePaymentModeX.fromCode(map['payment_mode'] as String?),
      payee: map['payee'] as String?,
      note: map['note'] as String?,
      frequency: RecurringExpenseFrequencyX.fromCode(
        map['frequency'] as String?,
      ),
      intervalCount: (map['interval_count'] as num?)?.toInt() ?? 1,
      startDate: _date(map['start_date']) ?? DateTime.now(),
      endDate: _date(map['end_date']),
      nextDueDate: _date(map['next_due_date']) ?? DateTime.now(),
      reminderDaysBefore: (map['reminder_days_before'] as num?)?.toInt() ?? 3,
      status: (map['status'] as String?) ?? 'active',
      createdBy: map['created_by'] as String?,
      createdAt: _date(map['created_at']),
      updatedAt: _date(map['updated_at']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'tenant_id': tenantId,
      'branch_id': branchId,
      'category_id': categoryId,
      'category_name': categoryName,
      'title': title,
      'estimated_amount': estimatedAmount,
      'payment_mode': paymentMode.code,
      'payee': payee,
      'note': note,
      'frequency': frequency.code,
      'interval_count': intervalCount,
      'start_date': _dateOnly(startDate),
      'end_date': endDate == null ? null : _dateOnly(endDate!),
      'next_due_date': _dateOnly(nextDueDate),
      'reminder_days_before': reminderDaysBefore,
      'status': status,
      'created_by': createdBy,
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }
}

class ExpenseReportBreakdownItem {
  final String label;
  final double total;

  const ExpenseReportBreakdownItem({required this.label, required this.total});

  factory ExpenseReportBreakdownItem.fromCategoryMap(Map<String, dynamic> map) {
    return ExpenseReportBreakdownItem(
      label: (map['category_name'] as String?) ?? 'Uncategorized',
      total: (map['total'] as num?)?.toDouble() ?? 0,
    );
  }

  factory ExpenseReportBreakdownItem.fromPaymentModeMap(
    Map<String, dynamic> map,
  ) {
    final mode = ExpensePaymentModeX.fromCode(map['payment_mode'] as String?);

    return ExpenseReportBreakdownItem(
      label: mode.label,
      total: (map['total'] as num?)?.toDouble() ?? 0,
    );
  }
}

class ExpenseProfitReportModel {
  final String tenantId;
  final String branchId;
  final DateTime dateFrom;
  final DateTime dateTo;
  final String plan;

  final double totalExpenses;
  final double draftExpenses;
  final double salesRevenue;
  final double cogs;
  final double grossProfit;
  final double netProfit;

  final List<ExpenseReportBreakdownItem> byCategory;
  final List<ExpenseReportBreakdownItem> byPaymentMode;

  const ExpenseProfitReportModel({
    required this.tenantId,
    required this.branchId,
    required this.dateFrom,
    required this.dateTo,
    required this.plan,
    required this.totalExpenses,
    required this.draftExpenses,
    required this.salesRevenue,
    required this.cogs,
    required this.grossProfit,
    required this.netProfit,
    required this.byCategory,
    required this.byPaymentMode,
  });

  factory ExpenseProfitReportModel.fromMap(Map<String, dynamic> map) {
    return ExpenseProfitReportModel(
      tenantId: map['tenant_id'] as String,
      branchId: map['branch_id'] as String,
      dateFrom: _date(map['date_from']) ?? DateTime.now(),
      dateTo: _date(map['date_to']) ?? DateTime.now(),
      plan: (map['plan'] as String?) ?? 'starter',
      totalExpenses: (map['total_expenses'] as num?)?.toDouble() ?? 0,
      draftExpenses: (map['draft_expenses'] as num?)?.toDouble() ?? 0,
      salesRevenue: (map['sales_revenue'] as num?)?.toDouble() ?? 0,
      cogs: (map['cogs'] as num?)?.toDouble() ?? 0,
      grossProfit: (map['gross_profit'] as num?)?.toDouble() ?? 0,
      netProfit: (map['net_profit'] as num?)?.toDouble() ?? 0,
      byCategory:
          ((map['by_category'] as List?) ?? [])
              .map(
                (item) => ExpenseReportBreakdownItem.fromCategoryMap(
                  Map<String, dynamic>.from(item as Map),
                ),
              )
              .toList(),
      byPaymentMode:
          ((map['by_payment_mode'] as List?) ?? [])
              .map(
                (item) => ExpenseReportBreakdownItem.fromPaymentModeMap(
                  Map<String, dynamic>.from(item as Map),
                ),
              )
              .toList(),
    );
  }
}

DateTime? _date(dynamic value) {
  if (value == null) return null;
  return DateTime.tryParse(value.toString());
}

String _dateOnly(DateTime date) {
  final year = date.year.toString().padLeft(4, '0');
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '$year-$month-$day';
}

bool _bool(dynamic value, {bool defaultValue = false}) {
  if (value == null) return defaultValue;
  if (value is bool) return value;
  if (value is num) return value.toInt() == 1;
  if (value is String) return value == 'true' || value == '1';
  return defaultValue;
}
