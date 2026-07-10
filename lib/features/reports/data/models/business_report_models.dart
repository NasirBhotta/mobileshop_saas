enum BusinessReportType {
  sales,
  profitLoss,
  inventory,
  customerCredit,
  repairs,
  cashFlow,
  dashboard,
}

extension BusinessReportTypeX on BusinessReportType {
  String get code {
    switch (this) {
      case BusinessReportType.sales:
        return 'sales';
      case BusinessReportType.profitLoss:
        return 'profit_loss';
      case BusinessReportType.inventory:
        return 'inventory';
      case BusinessReportType.customerCredit:
        return 'customer_credit';
      case BusinessReportType.repairs:
        return 'repairs';
      case BusinessReportType.cashFlow:
        return 'cash_flow';
      case BusinessReportType.dashboard:
        return 'dashboard';
    }
  }

  String get label {
    switch (this) {
      case BusinessReportType.sales:
        return 'Sales';
      case BusinessReportType.profitLoss:
        return 'Profit & Loss';
      case BusinessReportType.inventory:
        return 'Inventory';
      case BusinessReportType.customerCredit:
        return 'Customer Credit';
      case BusinessReportType.repairs:
        return 'Repairs';
      case BusinessReportType.cashFlow:
        return 'Cash Flow';
      case BusinessReportType.dashboard:
        return 'Business Dashboard';
    }
  }

  static BusinessReportType fromCode(String? code) {
    switch (code) {
      case 'sales':
        return BusinessReportType.sales;
      case 'profit_loss':
        return BusinessReportType.profitLoss;
      case 'inventory':
        return BusinessReportType.inventory;
      case 'customer_credit':
        return BusinessReportType.customerCredit;
      case 'repairs':
        return BusinessReportType.repairs;
      case 'cash_flow':
        return BusinessReportType.cashFlow;
      case 'dashboard':
      default:
        return BusinessReportType.dashboard;
    }
  }
}

class ReportMoneyBreakdownItem {
  final String label;
  final double amount;

  const ReportMoneyBreakdownItem({required this.label, required this.amount});

  factory ReportMoneyBreakdownItem.fromMap(
    Map<String, dynamic> map, {
    String labelKey = 'label',
    String amountKey = 'amount',
  }) {
    return ReportMoneyBreakdownItem(
      label:
          (map[labelKey] as String?) ??
          (map['category_name'] as String?) ??
          (map['payment_mode'] as String?) ??
          (map['status'] as String?) ??
          'Unknown',
      amount: _double(map[amountKey]),
    );
  }
}

class ReportDailyProfitItem {
  final DateTime date;
  final double revenue;
  final double cogs;
  final double grossProfit;
  final double expenses;
  final double netProfit;

  const ReportDailyProfitItem({
    required this.date,
    required this.revenue,
    required this.cogs,
    required this.grossProfit,
    required this.expenses,
    required this.netProfit,
  });

  factory ReportDailyProfitItem.fromMap(Map<String, dynamic> map) {
    return ReportDailyProfitItem(
      date: _date(map['date']) ?? DateTime.now(),
      revenue: _double(map['revenue']),
      cogs: _double(map['cogs']),
      grossProfit: _double(map['gross_profit']),
      expenses: _double(map['expenses']),
      netProfit: _double(map['net_profit']),
    );
  }
}

// ════════════════════════════════════════
// PROFIT & LOSS
// ════════════════════════════════════════

class ProfitLossSummaryModel {
  final double revenue;
  final double cogs;
  final double grossProfit;
  final double grossMarginPercent;
  final double expenses;
  final double draftExpenses;
  final double netProfit;
  final double netMarginPercent;

  const ProfitLossSummaryModel({
    required this.revenue,
    required this.cogs,
    required this.grossProfit,
    required this.grossMarginPercent,
    required this.expenses,
    required this.draftExpenses,
    required this.netProfit,
    required this.netMarginPercent,
  });

  factory ProfitLossSummaryModel.empty() {
    return const ProfitLossSummaryModel(
      revenue: 0,
      cogs: 0,
      grossProfit: 0,
      grossMarginPercent: 0,
      expenses: 0,
      draftExpenses: 0,
      netProfit: 0,
      netMarginPercent: 0,
    );
  }

  factory ProfitLossSummaryModel.fromMap(Map<String, dynamic> map) {
    return ProfitLossSummaryModel(
      revenue: _double(map['revenue']),
      cogs: _double(map['cogs']),
      grossProfit: _double(map['gross_profit']),
      grossMarginPercent: _double(map['gross_margin_percent']),
      expenses: _double(map['expenses']),
      draftExpenses: _double(map['draft_expenses']),
      netProfit: _double(map['net_profit']),
      netMarginPercent: _double(map['net_margin_percent']),
    );
  }
}

class ProfitLossReportModel {
  final String tenantId;
  final String? branchId;
  final DateTime dateFrom;
  final DateTime dateTo;
  final String plan;
  final bool exportAllowed;
  final ProfitLossSummaryModel summary;
  final List<ReportMoneyBreakdownItem> expenseBreakdown;
  final List<ReportDailyProfitItem> dailyBreakdown;

  const ProfitLossReportModel({
    required this.tenantId,
    required this.branchId,
    required this.dateFrom,
    required this.dateTo,
    required this.plan,
    required this.exportAllowed,
    required this.summary,
    required this.expenseBreakdown,
    required this.dailyBreakdown,
  });

  factory ProfitLossReportModel.fromMap(Map<String, dynamic> map) {
    return ProfitLossReportModel(
      tenantId: map['tenant_id'] as String,
      branchId: map['branch_id'] as String?,
      dateFrom: _date(map['date_from']) ?? DateTime.now(),
      dateTo: _date(map['date_to']) ?? DateTime.now(),
      plan: (map['plan'] as String?) ?? 'starter',
      exportAllowed: _bool(map['export_allowed']),
      summary: ProfitLossSummaryModel.fromMap(
        Map<String, dynamic>.from((map['summary'] as Map?) ?? {}),
      ),
      expenseBreakdown:
          ((map['expense_breakdown'] as List?) ?? [])
              .map(
                (item) => ReportMoneyBreakdownItem.fromMap(
                  Map<String, dynamic>.from(item as Map),
                  labelKey: 'category_name',
                  amountKey: 'amount',
                ),
              )
              .toList(),
      dailyBreakdown:
          ((map['daily_breakdown'] as List?) ?? [])
              .map(
                (item) => ReportDailyProfitItem.fromMap(
                  Map<String, dynamic>.from(item as Map),
                ),
              )
              .toList(),
    );
  }
}

// ════════════════════════════════════════
// INVENTORY ANALYTICS
// ════════════════════════════════════════

class InventoryReportSummaryModel {
  final int totalProducts;
  final double totalStock;
  final double stockValue;
  final int lowStockCount;
  final int outOfStockCount;

  const InventoryReportSummaryModel({
    required this.totalProducts,
    required this.totalStock,
    required this.stockValue,
    required this.lowStockCount,
    required this.outOfStockCount,
  });

  factory InventoryReportSummaryModel.empty() {
    return const InventoryReportSummaryModel(
      totalProducts: 0,
      totalStock: 0,
      stockValue: 0,
      lowStockCount: 0,
      outOfStockCount: 0,
    );
  }

  factory InventoryReportSummaryModel.fromMap(Map<String, dynamic> map) {
    return InventoryReportSummaryModel(
      totalProducts: _int(map['total_products']),
      totalStock: _double(map['total_stock']),
      stockValue: _double(map['stock_value']),
      lowStockCount: _int(map['low_stock_count']),
      outOfStockCount: _int(map['out_of_stock_count']),
    );
  }
}

class InventoryLowStockItem {
  final String? productId;
  final String productName;
  final String? sku;
  final double quantity;
  final double reorderThreshold;
  final double stockValue;

  const InventoryLowStockItem({
    this.productId,
    required this.productName,
    this.sku,
    required this.quantity,
    required this.reorderThreshold,
    required this.stockValue,
  });

  factory InventoryLowStockItem.fromMap(Map<String, dynamic> map) {
    return InventoryLowStockItem(
      productId: map['product_id'] as String?,
      productName: (map['product_name'] as String?) ?? 'Product',
      sku: map['sku'] as String?,
      quantity: _double(map['quantity']),
      reorderThreshold: _double(map['reorder_threshold']),
      stockValue: _double(map['stock_value']),
    );
  }
}

class InventoryMovingItem {
  final String? productId;
  final String productName;
  final String? sku;
  final double quantitySold;
  final double revenue;
  final double grossProfit;

  const InventoryMovingItem({
    this.productId,
    required this.productName,
    this.sku,
    required this.quantitySold,
    required this.revenue,
    required this.grossProfit,
  });

  factory InventoryMovingItem.fromMap(Map<String, dynamic> map) {
    return InventoryMovingItem(
      productId: map['product_id'] as String?,
      productName: (map['product_name'] as String?) ?? 'Product',
      sku: map['sku'] as String?,
      quantitySold: _double(map['quantity_sold']),
      revenue: _double(map['revenue']),
      grossProfit: _double(map['gross_profit']),
    );
  }
}

class InventoryDeadStockItem {
  final String? productId;
  final String productName;
  final String? sku;
  final double quantity;
  final double stockValue;

  const InventoryDeadStockItem({
    this.productId,
    required this.productName,
    this.sku,
    required this.quantity,
    required this.stockValue,
  });

  factory InventoryDeadStockItem.fromMap(Map<String, dynamic> map) {
    return InventoryDeadStockItem(
      productId: map['product_id'] as String?,
      productName: (map['product_name'] as String?) ?? 'Product',
      sku: map['sku'] as String?,
      quantity: _double(map['quantity']),
      stockValue: _double(map['stock_value']),
    );
  }
}

class InventoryCategoryStockItem {
  final String? categoryId;
  final String categoryName;
  final double stockQty;
  final double stockValue;

  const InventoryCategoryStockItem({
    this.categoryId,
    required this.categoryName,
    required this.stockQty,
    required this.stockValue,
  });

  factory InventoryCategoryStockItem.fromMap(Map<String, dynamic> map) {
    return InventoryCategoryStockItem(
      categoryId: map['category_id'] as String?,
      categoryName: (map['category_name'] as String?) ?? 'Uncategorized',
      stockQty: _double(map['stock_qty']),
      stockValue: _double(map['stock_value']),
    );
  }
}

class InventoryAnalyticsReportModel {
  final String tenantId;
  final String? branchId;
  final DateTime dateFrom;
  final DateTime dateTo;
  final InventoryReportSummaryModel summary;
  final List<InventoryLowStockItem> lowStock;
  final List<InventoryMovingItem> fastMoving;
  final List<InventoryDeadStockItem> deadStock;
  final List<InventoryCategoryStockItem> categoryStock;

  const InventoryAnalyticsReportModel({
    required this.tenantId,
    required this.branchId,
    required this.dateFrom,
    required this.dateTo,
    required this.summary,
    required this.lowStock,
    required this.fastMoving,
    required this.deadStock,
    required this.categoryStock,
  });

  factory InventoryAnalyticsReportModel.fromMap(Map<String, dynamic> map) {
    return InventoryAnalyticsReportModel(
      tenantId: map['tenant_id'] as String,
      branchId: map['branch_id'] as String?,
      dateFrom: _date(map['date_from']) ?? DateTime.now(),
      dateTo: _date(map['date_to']) ?? DateTime.now(),
      summary: InventoryReportSummaryModel.fromMap(
        Map<String, dynamic>.from((map['summary'] as Map?) ?? {}),
      ),
      lowStock:
          ((map['low_stock'] as List?) ?? [])
              .map(
                (item) => InventoryLowStockItem.fromMap(
                  Map<String, dynamic>.from(item as Map),
                ),
              )
              .toList(),
      fastMoving:
          ((map['fast_moving'] as List?) ?? [])
              .map(
                (item) => InventoryMovingItem.fromMap(
                  Map<String, dynamic>.from(item as Map),
                ),
              )
              .toList(),
      deadStock:
          ((map['dead_stock'] as List?) ?? [])
              .map(
                (item) => InventoryDeadStockItem.fromMap(
                  Map<String, dynamic>.from(item as Map),
                ),
              )
              .toList(),
      categoryStock:
          ((map['category_stock'] as List?) ?? [])
              .map(
                (item) => InventoryCategoryStockItem.fromMap(
                  Map<String, dynamic>.from(item as Map),
                ),
              )
              .toList(),
    );
  }
}

// ════════════════════════════════════════
// CUSTOMER CREDIT
// ════════════════════════════════════════

class CustomerCreditSummaryModel {
  final int totalCustomers;
  final int creditCustomers;
  final double outstandingBalance;

  const CustomerCreditSummaryModel({
    required this.totalCustomers,
    required this.creditCustomers,
    required this.outstandingBalance,
  });

  factory CustomerCreditSummaryModel.fromMap(Map<String, dynamic> map) {
    return CustomerCreditSummaryModel(
      totalCustomers: _int(map['total_customers']),
      creditCustomers: _int(map['credit_customers']),
      outstandingBalance: _double(map['outstanding_balance']),
    );
  }
}

class TopCustomerReportItem {
  final String? customerId;
  final String customerName;
  final String? phone;
  final int orders;
  final double revenue;

  const TopCustomerReportItem({
    this.customerId,
    required this.customerName,
    this.phone,
    required this.orders,
    required this.revenue,
  });

  factory TopCustomerReportItem.fromMap(Map<String, dynamic> map) {
    return TopCustomerReportItem(
      customerId: map['customer_id'] as String?,
      customerName: (map['customer_name'] as String?) ?? 'Customer',
      phone: map['phone'] as String?,
      orders: _int(map['orders']),
      revenue: _double(map['revenue']),
    );
  }
}

class CreditCustomerReportItem {
  final String? customerId;
  final String customerName;
  final String? phone;
  final double creditLimit;
  final double outstandingBalance;

  const CreditCustomerReportItem({
    this.customerId,
    required this.customerName,
    this.phone,
    required this.creditLimit,
    required this.outstandingBalance,
  });

  factory CreditCustomerReportItem.fromMap(Map<String, dynamic> map) {
    return CreditCustomerReportItem(
      customerId: map['customer_id'] as String?,
      customerName: (map['customer_name'] as String?) ?? 'Customer',
      phone: map['phone'] as String?,
      creditLimit: _double(map['credit_limit']),
      outstandingBalance: _double(map['outstanding_balance']),
    );
  }
}

class CustomerCreditReportModel {
  final String tenantId;
  final String? branchId;
  final DateTime dateFrom;
  final DateTime dateTo;
  final CustomerCreditSummaryModel summary;
  final List<TopCustomerReportItem> topCustomers;
  final List<CreditCustomerReportItem> creditCustomers;

  const CustomerCreditReportModel({
    required this.tenantId,
    required this.branchId,
    required this.dateFrom,
    required this.dateTo,
    required this.summary,
    required this.topCustomers,
    required this.creditCustomers,
  });

  factory CustomerCreditReportModel.fromMap(Map<String, dynamic> map) {
    return CustomerCreditReportModel(
      tenantId: map['tenant_id'] as String,
      branchId: map['branch_id'] as String?,
      dateFrom: _date(map['date_from']) ?? DateTime.now(),
      dateTo: _date(map['date_to']) ?? DateTime.now(),
      summary: CustomerCreditSummaryModel.fromMap(
        Map<String, dynamic>.from((map['summary'] as Map?) ?? {}),
      ),
      topCustomers:
          ((map['top_customers'] as List?) ?? [])
              .map(
                (item) => TopCustomerReportItem.fromMap(
                  Map<String, dynamic>.from(item as Map),
                ),
              )
              .toList(),
      creditCustomers:
          ((map['credit_customers'] as List?) ?? [])
              .map(
                (item) => CreditCustomerReportItem.fromMap(
                  Map<String, dynamic>.from(item as Map),
                ),
              )
              .toList(),
    );
  }
}

// ════════════════════════════════════════
// REPAIRS
// ════════════════════════════════════════

class RepairReportSummaryModel {
  final int totalRepairs;
  final int openRepairs;
  final int completedRepairs;
  final double repairRevenue;

  const RepairReportSummaryModel({
    required this.totalRepairs,
    required this.openRepairs,
    required this.completedRepairs,
    required this.repairRevenue,
  });

  factory RepairReportSummaryModel.fromMap(Map<String, dynamic> map) {
    return RepairReportSummaryModel(
      totalRepairs: _int(map['total_repairs']),
      openRepairs: _int(map['open_repairs']),
      completedRepairs: _int(map['completed_repairs']),
      repairRevenue: _double(map['repair_revenue']),
    );
  }
}

class RepairStatusBreakdownItem {
  final String status;
  final int count;
  final double revenue;

  const RepairStatusBreakdownItem({
    required this.status,
    required this.count,
    required this.revenue,
  });

  factory RepairStatusBreakdownItem.fromMap(Map<String, dynamic> map) {
    return RepairStatusBreakdownItem(
      status: (map['status'] as String?) ?? 'unknown',
      count: _int(map['count']),
      revenue: _double(map['revenue']),
    );
  }
}

class RepairTechnicianBreakdownItem {
  final String? technicianId;
  final int repairs;
  final int completed;
  final double revenue;

  const RepairTechnicianBreakdownItem({
    this.technicianId,
    required this.repairs,
    required this.completed,
    required this.revenue,
  });

  factory RepairTechnicianBreakdownItem.fromMap(Map<String, dynamic> map) {
    return RepairTechnicianBreakdownItem(
      technicianId: map['technician_id'] as String?,
      repairs: _int(map['repairs']),
      completed: _int(map['completed']),
      revenue: _double(map['revenue']),
    );
  }
}

class RepairAnalyticsReportModel {
  final String tenantId;
  final String? branchId;
  final DateTime dateFrom;
  final DateTime dateTo;
  final RepairReportSummaryModel summary;
  final List<RepairStatusBreakdownItem> statusBreakdown;
  final List<RepairTechnicianBreakdownItem> technicianBreakdown;

  const RepairAnalyticsReportModel({
    required this.tenantId,
    required this.branchId,
    required this.dateFrom,
    required this.dateTo,
    required this.summary,
    required this.statusBreakdown,
    required this.technicianBreakdown,
  });

  factory RepairAnalyticsReportModel.fromMap(Map<String, dynamic> map) {
    return RepairAnalyticsReportModel(
      tenantId: map['tenant_id'] as String,
      branchId: map['branch_id'] as String?,
      dateFrom: _date(map['date_from']) ?? DateTime.now(),
      dateTo: _date(map['date_to']) ?? DateTime.now(),
      summary: RepairReportSummaryModel.fromMap(
        Map<String, dynamic>.from((map['summary'] as Map?) ?? {}),
      ),
      statusBreakdown:
          ((map['status_breakdown'] as List?) ?? [])
              .map(
                (item) => RepairStatusBreakdownItem.fromMap(
                  Map<String, dynamic>.from(item as Map),
                ),
              )
              .toList(),
      technicianBreakdown:
          ((map['technician_breakdown'] as List?) ?? [])
              .map(
                (item) => RepairTechnicianBreakdownItem.fromMap(
                  Map<String, dynamic>.from(item as Map),
                ),
              )
              .toList(),
    );
  }
}

// ════════════════════════════════════════
// CASH FLOW
// ════════════════════════════════════════

class CashFlowSummaryModel {
  final double cashIn;
  final double cashOut;
  final double netCash;

  const CashFlowSummaryModel({
    required this.cashIn,
    required this.cashOut,
    required this.netCash,
  });

  factory CashFlowSummaryModel.fromMap(Map<String, dynamic> map) {
    return CashFlowSummaryModel(
      cashIn: _double(map['cash_in']),
      cashOut: _double(map['cash_out']),
      netCash: _double(map['net_cash']),
    );
  }
}

class CashFlowReportModel {
  final String tenantId;
  final String? branchId;
  final DateTime dateFrom;
  final DateTime dateTo;
  final CashFlowSummaryModel summary;
  final List<ReportMoneyBreakdownItem> salesPaymentBreakdown;
  final List<ReportMoneyBreakdownItem> expensePaymentBreakdown;

  const CashFlowReportModel({
    required this.tenantId,
    required this.branchId,
    required this.dateFrom,
    required this.dateTo,
    required this.summary,
    required this.salesPaymentBreakdown,
    required this.expensePaymentBreakdown,
  });

  factory CashFlowReportModel.fromMap(Map<String, dynamic> map) {
    return CashFlowReportModel(
      tenantId: map['tenant_id'] as String,
      branchId: map['branch_id'] as String?,
      dateFrom: _date(map['date_from']) ?? DateTime.now(),
      dateTo: _date(map['date_to']) ?? DateTime.now(),
      summary: CashFlowSummaryModel.fromMap(
        Map<String, dynamic>.from((map['summary'] as Map?) ?? {}),
      ),
      salesPaymentBreakdown:
          ((map['sales_payment_breakdown'] as List?) ?? [])
              .map(
                (item) => ReportMoneyBreakdownItem.fromMap(
                  Map<String, dynamic>.from(item as Map),
                  labelKey: 'payment_mode',
                  amountKey: 'amount',
                ),
              )
              .toList(),
      expensePaymentBreakdown:
          ((map['expense_payment_breakdown'] as List?) ?? [])
              .map(
                (item) => ReportMoneyBreakdownItem.fromMap(
                  Map<String, dynamic>.from(item as Map),
                  labelKey: 'payment_mode',
                  amountKey: 'amount',
                ),
              )
              .toList(),
    );
  }
}

// ════════════════════════════════════════
// BUSINESS DASHBOARD
// ════════════════════════════════════════

class BusinessDashboardReportModel {
  final String tenantId;
  final String? branchId;
  final DateTime dateFrom;
  final DateTime dateTo;

  final Map<String, dynamic> sales;
  final ProfitLossReportModel profitLoss;
  final InventoryAnalyticsReportModel inventory;
  final CustomerCreditReportModel customers;
  final RepairAnalyticsReportModel repairs;
  final CashFlowReportModel cashFlow;

  const BusinessDashboardReportModel({
    required this.tenantId,
    required this.branchId,
    required this.dateFrom,
    required this.dateTo,
    required this.sales,
    required this.profitLoss,
    required this.inventory,
    required this.customers,
    required this.repairs,
    required this.cashFlow,
  });

  factory BusinessDashboardReportModel.fromMap(Map<String, dynamic> map) {
    final tenantId = map['tenant_id'] as String;
    final branchId = map['branch_id'] as String?;
    final dateFrom = map['date_from'];
    final dateTo = map['date_to'];

    return BusinessDashboardReportModel(
      tenantId: tenantId,
      branchId: branchId,
      dateFrom: _date(dateFrom) ?? DateTime.now(),
      dateTo: _date(dateTo) ?? DateTime.now(),
      sales: Map<String, dynamic>.from((map['sales'] as Map?) ?? {}),
      profitLoss: ProfitLossReportModel.fromMap(
        _nestedReportMap(
          map['profit_loss'],
          tenantId: tenantId,
          branchId: branchId,
          dateFrom: dateFrom,
          dateTo: dateTo,
        ),
      ),
      inventory: InventoryAnalyticsReportModel.fromMap(
        _nestedReportMap(
          map['inventory'],
          tenantId: tenantId,
          branchId: branchId,
          dateFrom: dateFrom,
          dateTo: dateTo,
        ),
      ),
      customers: CustomerCreditReportModel.fromMap(
        _nestedReportMap(
          map['customers'],
          tenantId: tenantId,
          branchId: branchId,
          dateFrom: dateFrom,
          dateTo: dateTo,
        ),
      ),
      repairs: RepairAnalyticsReportModel.fromMap(
        _nestedReportMap(
          map['repairs'],
          tenantId: tenantId,
          branchId: branchId,
          dateFrom: dateFrom,
          dateTo: dateTo,
        ),
      ),
      cashFlow: CashFlowReportModel.fromMap(
        _nestedReportMap(
          map['cash_flow'],
          tenantId: tenantId,
          branchId: branchId,
          dateFrom: dateFrom,
          dateTo: dateTo,
        ),
      ),
    );
  }
}

class BusinessReportScheduleModel {
  final String id;
  final String tenantId;
  final String? branchId;

  final String name;
  final BusinessReportType reportType;
  final String cadence;
  final String reportScope;
  final String exportFormat;
  final String sendToEmail;

  final DateTime nextRunAt;
  final DateTime? lastRunAt;
  final String status;

  final String? createdBy;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const BusinessReportScheduleModel({
    required this.id,
    required this.tenantId,
    this.branchId,
    required this.name,
    required this.reportType,
    required this.cadence,
    required this.reportScope,
    required this.exportFormat,
    required this.sendToEmail,
    required this.nextRunAt,
    this.lastRunAt,
    this.status = 'active',
    this.createdBy,
    this.createdAt,
    this.updatedAt,
  });

  factory BusinessReportScheduleModel.fromMap(Map<String, dynamic> map) {
    return BusinessReportScheduleModel(
      id: map['id'] as String,
      tenantId: map['tenant_id'] as String,
      branchId: map['branch_id'] as String?,
      name: map['name'] as String,
      reportType: BusinessReportTypeX.fromCode(map['report_type'] as String?),
      cadence: (map['cadence'] as String?) ?? 'daily',
      reportScope: (map['report_scope'] as String?) ?? 'branch',
      exportFormat: (map['export_format'] as String?) ?? 'csv',
      sendToEmail: map['send_to_email'] as String,
      nextRunAt: _date(map['next_run_at']) ?? DateTime.now(),
      lastRunAt: _date(map['last_run_at']),
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
      'name': name,
      'report_type': reportType.code,
      'cadence': cadence,
      'report_scope': reportScope,
      'export_format': exportFormat,
      'send_to_email': sendToEmail,
      'next_run_at': nextRunAt.toIso8601String(),
      'last_run_at': lastRunAt?.toIso8601String(),
      'status': status,
      'created_by': createdBy,
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }
}

class BusinessReportDeliveryJobModel {
  final String id;
  final String tenantId;
  final String? scheduleId;
  final String? branchId;

  final BusinessReportType reportType;
  final DateTime dateFrom;
  final DateTime dateTo;
  final String exportFormat;
  final String sendToEmail;
  final String status;
  final String? errorMessage;
  final DateTime? createdAt;
  final DateTime? processedAt;

  const BusinessReportDeliveryJobModel({
    required this.id,
    required this.tenantId,
    this.scheduleId,
    this.branchId,
    required this.reportType,
    required this.dateFrom,
    required this.dateTo,
    required this.exportFormat,
    required this.sendToEmail,
    required this.status,
    this.errorMessage,
    this.createdAt,
    this.processedAt,
  });

  factory BusinessReportDeliveryJobModel.fromMap(Map<String, dynamic> map) {
    return BusinessReportDeliveryJobModel(
      id: map['id'] as String,
      tenantId: map['tenant_id'] as String,
      scheduleId: map['schedule_id'] as String?,
      branchId: map['branch_id'] as String?,
      reportType: BusinessReportTypeX.fromCode(map['report_type'] as String?),
      dateFrom: _date(map['date_from']) ?? DateTime.now(),
      dateTo: _date(map['date_to']) ?? DateTime.now(),
      exportFormat: (map['export_format'] as String?) ?? 'csv',
      sendToEmail: map['send_to_email'] as String,
      status: (map['status'] as String?) ?? 'pending',
      errorMessage: map['error_message'] as String?,
      createdAt: _date(map['created_at']),
      processedAt: _date(map['processed_at']),
    );
  }
}

// ════════════════════════════════════════
// HELPERS
// ════════════════════════════════════════

int _int(dynamic value) {
  if (value == null) return 0;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString()) ?? 0;
}

double _double(dynamic value) {
  if (value == null) return 0;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString()) ?? 0;
}

bool _bool(dynamic value, {bool defaultValue = false}) {
  if (value == null) return defaultValue;
  if (value is bool) return value;
  if (value is num) return value.toInt() == 1;
  if (value is String) return value == 'true' || value == '1';
  return defaultValue;
}

DateTime? _date(dynamic value) {
  if (value == null) return null;
  return DateTime.tryParse(value.toString());
}

Map<String, dynamic> _nestedReportMap(
  dynamic value, {
  required String tenantId,
  required String? branchId,
  required dynamic dateFrom,
  required dynamic dateTo,
}) {
  final map = Map<String, dynamic>.from((value as Map?) ?? {});

  map['tenant_id'] ??= tenantId;
  map['branch_id'] ??= branchId;
  map['date_from'] ??= dateFrom;
  map['date_to'] ??= dateTo;

  return map;
}
