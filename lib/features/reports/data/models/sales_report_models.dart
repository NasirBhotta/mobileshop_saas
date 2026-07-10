enum SalesReportCadence { daily, weekly, monthly }

extension SalesReportCadenceX on SalesReportCadence {
  String get code {
    switch (this) {
      case SalesReportCadence.daily:
        return 'daily';
      case SalesReportCadence.weekly:
        return 'weekly';
      case SalesReportCadence.monthly:
        return 'monthly';
    }
  }

  String get label {
    switch (this) {
      case SalesReportCadence.daily:
        return 'Daily';
      case SalesReportCadence.weekly:
        return 'Weekly';
      case SalesReportCadence.monthly:
        return 'Monthly';
    }
  }

  static SalesReportCadence fromCode(String? code) {
    switch (code) {
      case 'weekly':
        return SalesReportCadence.weekly;
      case 'monthly':
        return SalesReportCadence.monthly;
      case 'daily':
      default:
        return SalesReportCadence.daily;
    }
  }
}

enum SalesReportScope { branch, allBranches }

extension SalesReportScopeX on SalesReportScope {
  String get code {
    switch (this) {
      case SalesReportScope.branch:
        return 'branch';
      case SalesReportScope.allBranches:
        return 'all_branches';
    }
  }

  String get label {
    switch (this) {
      case SalesReportScope.branch:
        return 'Current Branch';
      case SalesReportScope.allBranches:
        return 'All Branches';
    }
  }

  static SalesReportScope fromCode(String? code) {
    switch (code) {
      case 'all_branches':
        return SalesReportScope.allBranches;
      case 'branch':
      default:
        return SalesReportScope.branch;
    }
  }
}

enum SalesReportExportFormat { csv, pdf }

extension SalesReportExportFormatX on SalesReportExportFormat {
  String get code {
    switch (this) {
      case SalesReportExportFormat.csv:
        return 'csv';
      case SalesReportExportFormat.pdf:
        return 'pdf';
    }
  }

  String get label {
    switch (this) {
      case SalesReportExportFormat.csv:
        return 'CSV';
      case SalesReportExportFormat.pdf:
        return 'PDF';
    }
  }

  static SalesReportExportFormat fromCode(String? code) {
    switch (code) {
      case 'pdf':
        return SalesReportExportFormat.pdf;
      case 'csv':
      default:
        return SalesReportExportFormat.csv;
    }
  }
}

class SalesReportSummaryModel {
  final int totalOrders;
  final int totalUnits;
  final double revenue;
  final double discount;
  final double tax;
  final double cogs;
  final double grossProfit;
  final double grossMarginPercent;

  const SalesReportSummaryModel({
    required this.totalOrders,
    required this.totalUnits,
    required this.revenue,
    required this.discount,
    required this.tax,
    required this.cogs,
    required this.grossProfit,
    required this.grossMarginPercent,
  });

  factory SalesReportSummaryModel.empty() {
    return const SalesReportSummaryModel(
      totalOrders: 0,
      totalUnits: 0,
      revenue: 0,
      discount: 0,
      tax: 0,
      cogs: 0,
      grossProfit: 0,
      grossMarginPercent: 0,
    );
  }

  factory SalesReportSummaryModel.fromMap(Map<String, dynamic> map) {
    return SalesReportSummaryModel(
      totalOrders: _int(map['total_orders']),
      totalUnits: _int(map['total_units']),
      revenue: _double(map['revenue']),
      discount: _double(map['discount']),
      tax: _double(map['tax']),
      cogs: _double(map['cogs']),
      grossProfit: _double(map['gross_profit']),
      grossMarginPercent: _double(map['gross_margin_percent']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'total_orders': totalOrders,
      'total_units': totalUnits,
      'revenue': revenue,
      'discount': discount,
      'tax': tax,
      'cogs': cogs,
      'gross_profit': grossProfit,
      'gross_margin_percent': grossMarginPercent,
    };
  }
}

class SalesProductBreakdownItem {
  final String? productId;
  final String productName;
  final String? sku;
  final int quantity;
  final double revenue;
  final double cogs;
  final double grossProfit;
  final double marginPercent;

  const SalesProductBreakdownItem({
    this.productId,
    required this.productName,
    this.sku,
    required this.quantity,
    required this.revenue,
    required this.cogs,
    required this.grossProfit,
    required this.marginPercent,
  });

  factory SalesProductBreakdownItem.fromMap(Map<String, dynamic> map) {
    return SalesProductBreakdownItem(
      productId: map['product_id'] as String?,
      productName: (map['product_name'] as String?) ?? 'Unknown Product',
      sku: map['sku'] as String?,
      quantity: _int(map['quantity']),
      revenue: _double(map['revenue']),
      cogs: _double(map['cogs']),
      grossProfit: _double(map['gross_profit']),
      marginPercent: _double(map['margin_percent']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'product_id': productId,
      'product_name': productName,
      'sku': sku,
      'quantity': quantity,
      'revenue': revenue,
      'cogs': cogs,
      'gross_profit': grossProfit,
      'margin_percent': marginPercent,
    };
  }
}

class SalesCustomerBreakdownItem {
  final String? customerId;
  final String customerName;
  final int orders;
  final double revenue;
  final double grossProfit;

  const SalesCustomerBreakdownItem({
    this.customerId,
    required this.customerName,
    required this.orders,
    required this.revenue,
    required this.grossProfit,
  });

  factory SalesCustomerBreakdownItem.fromMap(Map<String, dynamic> map) {
    return SalesCustomerBreakdownItem(
      customerId: map['customer_id'] as String?,
      customerName: (map['customer_name'] as String?) ?? 'Walk-in Customer',
      orders: _int(map['orders']),
      revenue: _double(map['revenue']),
      grossProfit: _double(map['gross_profit']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'customer_id': customerId,
      'customer_name': customerName,
      'orders': orders,
      'revenue': revenue,
      'gross_profit': grossProfit,
    };
  }
}

class SalesBranchBreakdownItem {
  final String? branchId;
  final String branchName;
  final int orders;
  final double revenue;
  final double cogs;
  final double grossProfit;
  final double marginPercent;

  const SalesBranchBreakdownItem({
    this.branchId,
    required this.branchName,
    required this.orders,
    required this.revenue,
    required this.cogs,
    required this.grossProfit,
    required this.marginPercent,
  });

  factory SalesBranchBreakdownItem.fromMap(Map<String, dynamic> map) {
    return SalesBranchBreakdownItem(
      branchId: map['branch_id'] as String?,
      branchName: (map['branch_name'] as String?) ?? 'Branch',
      orders: _int(map['orders']),
      revenue: _double(map['revenue']),
      cogs: _double(map['cogs']),
      grossProfit: _double(map['gross_profit']),
      marginPercent: _double(map['margin_percent']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'branch_id': branchId,
      'branch_name': branchName,
      'orders': orders,
      'revenue': revenue,
      'cogs': cogs,
      'gross_profit': grossProfit,
      'margin_percent': marginPercent,
    };
  }
}

class SalesCategoryBreakdownItem {
  final String? categoryId;
  final String categoryName;
  final int quantity;
  final double revenue;
  final double cogs;
  final double grossProfit;
  final double marginPercent;

  const SalesCategoryBreakdownItem({
    this.categoryId,
    required this.categoryName,
    required this.quantity,
    required this.revenue,
    required this.cogs,
    required this.grossProfit,
    required this.marginPercent,
  });

  factory SalesCategoryBreakdownItem.fromMap(Map<String, dynamic> map) {
    return SalesCategoryBreakdownItem(
      categoryId: map['category_id'] as String?,
      categoryName: (map['category_name'] as String?) ?? 'Uncategorized',
      quantity: _int(map['quantity']),
      revenue: _double(map['revenue']),
      cogs: _double(map['cogs']),
      grossProfit: _double(map['gross_profit']),
      marginPercent: _double(map['margin_percent']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'category_id': categoryId,
      'category_name': categoryName,
      'quantity': quantity,
      'revenue': revenue,
      'cogs': cogs,
      'gross_profit': grossProfit,
      'margin_percent': marginPercent,
    };
  }
}

class SalesDailyBreakdownItem {
  final DateTime date;
  final int orders;
  final double revenue;
  final double cogs;
  final double grossProfit;

  const SalesDailyBreakdownItem({
    required this.date,
    required this.orders,
    required this.revenue,
    required this.cogs,
    required this.grossProfit,
  });

  factory SalesDailyBreakdownItem.fromMap(Map<String, dynamic> map) {
    return SalesDailyBreakdownItem(
      date: _date(map['date']) ?? DateTime.now(),
      orders: _int(map['orders']),
      revenue: _double(map['revenue']),
      cogs: _double(map['cogs']),
      grossProfit: _double(map['gross_profit']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'date': _dateOnly(date),
      'orders': orders,
      'revenue': revenue,
      'cogs': cogs,
      'gross_profit': grossProfit,
    };
  }
}

class SalesAnalyticsReportModel {
  final String tenantId;
  final String? branchId;
  final DateTime dateFrom;
  final DateTime dateTo;
  final String plan;
  final bool exportAllowed;

  final SalesReportSummaryModel summary;
  final List<SalesProductBreakdownItem> productBreakdown;
  final List<SalesCustomerBreakdownItem> customerBreakdown;
  final List<SalesBranchBreakdownItem> branchBreakdown;
  final List<SalesCategoryBreakdownItem> categoryBreakdown;
  final List<SalesDailyBreakdownItem> dailyBreakdown;

  const SalesAnalyticsReportModel({
    required this.tenantId,
    required this.branchId,
    required this.dateFrom,
    required this.dateTo,
    required this.plan,
    required this.exportAllowed,
    required this.summary,
    required this.productBreakdown,
    required this.customerBreakdown,
    required this.branchBreakdown,
    required this.categoryBreakdown,
    required this.dailyBreakdown,
  });

  factory SalesAnalyticsReportModel.empty({
    required String tenantId,
    required String? branchId,
    required DateTime dateFrom,
    required DateTime dateTo,
    String plan = 'starter',
  }) {
    return SalesAnalyticsReportModel(
      tenantId: tenantId,
      branchId: branchId,
      dateFrom: dateFrom,
      dateTo: dateTo,
      plan: plan,
      exportAllowed: false,
      summary: SalesReportSummaryModel.empty(),
      productBreakdown: const [],
      customerBreakdown: const [],
      branchBreakdown: const [],
      categoryBreakdown: const [],
      dailyBreakdown: const [],
    );
  }

  factory SalesAnalyticsReportModel.fromMap(Map<String, dynamic> map) {
    return SalesAnalyticsReportModel(
      tenantId: map['tenant_id'] as String,
      branchId: map['branch_id'] as String?,
      dateFrom: _date(map['date_from']) ?? DateTime.now(),
      dateTo: _date(map['date_to']) ?? DateTime.now(),
      plan: (map['plan'] as String?) ?? 'starter',
      exportAllowed: _bool(map['export_allowed']),
      summary: SalesReportSummaryModel.fromMap(
        Map<String, dynamic>.from((map['summary'] as Map?) ?? {}),
      ),
      productBreakdown:
          ((map['product_breakdown'] as List?) ?? [])
              .map(
                (item) => SalesProductBreakdownItem.fromMap(
                  Map<String, dynamic>.from(item as Map),
                ),
              )
              .toList(),
      customerBreakdown:
          ((map['customer_breakdown'] as List?) ?? [])
              .map(
                (item) => SalesCustomerBreakdownItem.fromMap(
                  Map<String, dynamic>.from(item as Map),
                ),
              )
              .toList(),
      branchBreakdown:
          ((map['branch_breakdown'] as List?) ?? [])
              .map(
                (item) => SalesBranchBreakdownItem.fromMap(
                  Map<String, dynamic>.from(item as Map),
                ),
              )
              .toList(),
      categoryBreakdown:
          ((map['category_breakdown'] as List?) ?? [])
              .map(
                (item) => SalesCategoryBreakdownItem.fromMap(
                  Map<String, dynamic>.from(item as Map),
                ),
              )
              .toList(),
      dailyBreakdown:
          ((map['daily_breakdown'] as List?) ?? [])
              .map(
                (item) => SalesDailyBreakdownItem.fromMap(
                  Map<String, dynamic>.from(item as Map),
                ),
              )
              .toList(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'tenant_id': tenantId,
      'branch_id': branchId,
      'date_from': _dateOnly(dateFrom),
      'date_to': _dateOnly(dateTo),
      'plan': plan,
      'export_allowed': exportAllowed,
      'summary': summary.toMap(),
      'product_breakdown': productBreakdown.map((e) => e.toMap()).toList(),
      'customer_breakdown': customerBreakdown.map((e) => e.toMap()).toList(),
      'branch_breakdown': branchBreakdown.map((e) => e.toMap()).toList(),
      'category_breakdown': categoryBreakdown.map((e) => e.toMap()).toList(),
      'daily_breakdown': dailyBreakdown.map((e) => e.toMap()).toList(),
    };
  }
}

class SalesReportScheduleModel {
  final String id;
  final String tenantId;
  final String? branchId;

  final String name;
  final SalesReportCadence cadence;
  final SalesReportScope reportScope;
  final SalesReportExportFormat exportFormat;
  final String sendToEmail;

  final bool includeProductBreakdown;
  final bool includeCustomerBreakdown;
  final bool includeBranchBreakdown;
  final bool includeCategoryBreakdown;

  final DateTime nextRunAt;
  final DateTime? lastRunAt;
  final String status;

  final String? createdBy;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const SalesReportScheduleModel({
    required this.id,
    required this.tenantId,
    this.branchId,
    required this.name,
    required this.cadence,
    required this.reportScope,
    required this.exportFormat,
    required this.sendToEmail,
    this.includeProductBreakdown = true,
    this.includeCustomerBreakdown = true,
    this.includeBranchBreakdown = true,
    this.includeCategoryBreakdown = true,
    required this.nextRunAt,
    this.lastRunAt,
    this.status = 'active',
    this.createdBy,
    this.createdAt,
    this.updatedAt,
  });

  factory SalesReportScheduleModel.fromMap(Map<String, dynamic> map) {
    return SalesReportScheduleModel(
      id: map['id'] as String,
      tenantId: map['tenant_id'] as String,
      branchId: map['branch_id'] as String?,
      name: map['name'] as String,
      cadence: SalesReportCadenceX.fromCode(map['cadence'] as String?),
      reportScope: SalesReportScopeX.fromCode(map['report_scope'] as String?),
      exportFormat: SalesReportExportFormatX.fromCode(
        map['export_format'] as String?,
      ),
      sendToEmail: map['send_to_email'] as String,
      includeProductBreakdown: _bool(
        map['include_product_breakdown'],
        defaultValue: true,
      ),
      includeCustomerBreakdown: _bool(
        map['include_customer_breakdown'],
        defaultValue: true,
      ),
      includeBranchBreakdown: _bool(
        map['include_branch_breakdown'],
        defaultValue: true,
      ),
      includeCategoryBreakdown: _bool(
        map['include_category_breakdown'],
        defaultValue: true,
      ),
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
      'cadence': cadence.code,
      'report_scope': reportScope.code,
      'export_format': exportFormat.code,
      'send_to_email': sendToEmail,
      'include_product_breakdown': includeProductBreakdown,
      'include_customer_breakdown': includeCustomerBreakdown,
      'include_branch_breakdown': includeBranchBreakdown,
      'include_category_breakdown': includeCategoryBreakdown,
      'next_run_at': nextRunAt.toIso8601String(),
      'last_run_at': lastRunAt?.toIso8601String(),
      'status': status,
      'created_by': createdBy,
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }
}

class SalesReportDeliveryJobModel {
  final String id;
  final String tenantId;
  final String? scheduleId;
  final String? branchId;
  final DateTime dateFrom;
  final DateTime dateTo;
  final SalesReportExportFormat exportFormat;
  final String sendToEmail;
  final String status;
  final String? errorMessage;
  final DateTime? createdAt;
  final DateTime? processedAt;

  const SalesReportDeliveryJobModel({
    required this.id,
    required this.tenantId,
    this.scheduleId,
    this.branchId,
    required this.dateFrom,
    required this.dateTo,
    required this.exportFormat,
    required this.sendToEmail,
    required this.status,
    this.errorMessage,
    this.createdAt,
    this.processedAt,
  });

  factory SalesReportDeliveryJobModel.fromMap(Map<String, dynamic> map) {
    return SalesReportDeliveryJobModel(
      id: map['id'] as String,
      tenantId: map['tenant_id'] as String,
      scheduleId: map['schedule_id'] as String?,
      branchId: map['branch_id'] as String?,
      dateFrom: _date(map['date_from']) ?? DateTime.now(),
      dateTo: _date(map['date_to']) ?? DateTime.now(),
      exportFormat: SalesReportExportFormatX.fromCode(
        map['export_format'] as String?,
      ),
      sendToEmail: map['send_to_email'] as String,
      status: (map['status'] as String?) ?? 'pending',
      errorMessage: map['error_message'] as String?,
      createdAt: _date(map['created_at']),
      processedAt: _date(map['processed_at']),
    );
  }
}

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

String _dateOnly(DateTime date) {
  final year = date.year.toString().padLeft(4, '0');
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '$year-$month-$day';
}
