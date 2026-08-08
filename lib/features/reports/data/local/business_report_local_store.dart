import 'dart:convert';

import 'package:mobileshop_saas/core/local/local_database.dart';
import 'package:mobileshop_saas/core/accounting/ledger_cash_summary.dart';

import '../models/business_report_models.dart';
import 'sales_report_local_store.dart';

class BusinessReportLocalStore {
  static Future<void> saveReportCache({
    required BusinessReportType reportType,
    required String tenantId,
    required String? branchId,
    required DateTime dateFrom,
    required DateTime dateTo,
    required Map<String, dynamic> report,
  }) async {
    await LocalDatabase.execute(
      '''
      INSERT OR REPLACE INTO business_report_cache(
        id,
        tenant_id,
        branch_id,
        report_type,
        date_from,
        date_to,
        report_json,
        created_at
      )
      VALUES (?, ?, ?, ?, ?, ?, ?, ?)
      ''',
      [
        _cacheId(
          reportType: reportType,
          tenantId: tenantId,
          branchId: branchId,
          dateFrom: dateFrom,
          dateTo: dateTo,
        ),
        tenantId,
        branchId,
        reportType.code,
        _dateOnly(dateFrom),
        _dateOnly(dateTo),
        jsonEncode(report),
        DateTime.now().toIso8601String(),
      ],
    );
  }

  static Future<Map<String, dynamic>?> loadReportCache({
    required BusinessReportType reportType,
    required String tenantId,
    required String? branchId,
    required DateTime dateFrom,
    required DateTime dateTo,
  }) async {
    final rows = await LocalDatabase.select(
      '''
      SELECT report_json
      FROM business_report_cache
      WHERE id = ?
      LIMIT 1
      ''',
      [
        _cacheId(
          reportType: reportType,
          tenantId: tenantId,
          branchId: branchId,
          dateFrom: dateFrom,
          dateTo: dateTo,
        ),
      ],
    );

    if (rows.isEmpty) return null;

    final decoded = jsonDecode(rows.first['report_json'] as String);
    return Map<String, dynamic>.from(decoded as Map);
  }

  static Future<Map<String, dynamic>> buildLocalReport({
    required BusinessReportType reportType,
    required String tenantId,
    required String? branchId,
    required DateTime dateFrom,
    required DateTime dateTo,
    String plan = 'starter',
    bool exportAllowed = false,
  }) async {
    final map = switch (reportType) {
      BusinessReportType.sales => await _buildSalesReport(
        tenantId: tenantId,
        branchId: branchId,
        dateFrom: dateFrom,
        dateTo: dateTo,
        plan: plan,
        exportAllowed: exportAllowed,
      ),
      BusinessReportType.profitLoss => await _buildProfitLossReport(
        tenantId: tenantId,
        branchId: branchId,
        dateFrom: dateFrom,
        dateTo: dateTo,
        plan: plan,
        exportAllowed: exportAllowed,
      ),
      BusinessReportType.inventory => await _buildInventoryReport(
        tenantId: tenantId,
        branchId: branchId,
        dateFrom: dateFrom,
        dateTo: dateTo,
      ),
      BusinessReportType.customerCredit => await _buildCustomerCreditReport(
        tenantId: tenantId,
        branchId: branchId,
        dateFrom: dateFrom,
        dateTo: dateTo,
      ),
      BusinessReportType.repairs => await _buildRepairReport(
        tenantId: tenantId,
        branchId: branchId,
        dateFrom: dateFrom,
        dateTo: dateTo,
      ),
      BusinessReportType.cashFlow => await _buildCashFlowReport(
        tenantId: tenantId,
        branchId: branchId,
        dateFrom: dateFrom,
        dateTo: dateTo,
      ),
      BusinessReportType.dashboard => await _buildDashboardReport(
        tenantId: tenantId,
        branchId: branchId,
        dateFrom: dateFrom,
        dateTo: dateTo,
        plan: plan,
        exportAllowed: exportAllowed,
      ),
    };

    await saveReportCache(
      reportType: reportType,
      tenantId: tenantId,
      branchId: branchId,
      dateFrom: dateFrom,
      dateTo: dateTo,
      report: map,
    );
    return map;
  }

  static Future<double> loadGrossProfit({
    required String tenantId,
    required String branchId,
    required DateTime dateFrom,
    required DateTime dateTo,
  }) async {
    final sales = await SalesReportLocalStore.buildLocalReport(
      tenantId: tenantId,
      branchId: branchId,
      dateFrom: dateFrom,
      dateTo: dateTo,
      netReturns: true,
    );
    final repairs = await _repairFinancialTotals(
      tenantId: tenantId,
      branchId: branchId,
      dateFrom: dateFrom,
      dateTo: dateTo,
    );
    return sales.summary.grossProfit + repairs.grossProfit;
  }

  static Future<void> saveSchedule(BusinessReportScheduleModel schedule) async {
    await LocalDatabase.execute(
      '''
      INSERT OR REPLACE INTO business_report_schedules(
        id,
        tenant_id,
        branch_id,
        name,
        report_type,
        cadence,
        report_scope,
        export_format,
        send_to_email,
        next_run_at,
        last_run_at,
        status,
        created_by,
        created_at,
        updated_at
      )
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''',
      [
        schedule.id,
        schedule.tenantId,
        schedule.branchId,
        schedule.name,
        schedule.reportType.code,
        schedule.cadence,
        schedule.reportScope,
        schedule.exportFormat,
        schedule.sendToEmail,
        schedule.nextRunAt.toIso8601String(),
        schedule.lastRunAt?.toIso8601String(),
        schedule.status,
        schedule.createdBy,
        schedule.createdAt?.toIso8601String(),
        schedule.updatedAt?.toIso8601String(),
      ],
    );
  }

  static Future<void> saveSchedules(
    List<BusinessReportScheduleModel> schedules,
  ) async {
    for (final schedule in schedules) {
      await saveSchedule(schedule);
    }
  }

  static Future<List<BusinessReportScheduleModel>> loadSchedules({
    required String tenantId,
    String? branchId,
    bool includeAllBranches = true,
  }) async {
    final rows =
        branchId == null
            ? await LocalDatabase.select(
              '''
              SELECT *
              FROM business_report_schedules
              WHERE tenant_id = ?
              ORDER BY next_run_at ASC
              ''',
              [tenantId],
            )
            : includeAllBranches
            ? await LocalDatabase.select(
              '''
              SELECT *
              FROM business_report_schedules
              WHERE tenant_id = ?
                AND (branch_id = ? OR branch_id IS NULL)
              ORDER BY next_run_at ASC
              ''',
              [tenantId, branchId],
            )
            : await LocalDatabase.select(
              '''
              SELECT *
              FROM business_report_schedules
              WHERE tenant_id = ?
                AND branch_id = ?
              ORDER BY next_run_at ASC
              ''',
              [tenantId, branchId],
            );

    return rows.map(BusinessReportScheduleModel.fromMap).toList();
  }

  static Future<void> updateScheduleStatus({
    required String scheduleId,
    required String tenantId,
    required String branchId,
    required bool includeAllBranches,
    required String status,
  }) async {
    final branchPredicate =
        includeAllBranches
            ? 'AND (branch_id = ? OR branch_id IS NULL)'
            : 'AND branch_id = ?';

    await LocalDatabase.execute(
      '''
      UPDATE business_report_schedules
      SET status = ?,
          updated_at = ?
      WHERE id = ?
        AND tenant_id = ?
        $branchPredicate
      ''',
      [
        status,
        DateTime.now().toIso8601String(),
        scheduleId,
        tenantId,
        branchId,
      ],
    );
  }

  static Future<void> saveDeliveryJob(
    BusinessReportDeliveryJobModel job,
  ) async {
    await LocalDatabase.execute(
      '''
      INSERT OR REPLACE INTO business_report_delivery_jobs(
        id,
        tenant_id,
        schedule_id,
        branch_id,
        report_type,
        date_from,
        date_to,
        export_format,
        send_to_email,
        status,
        error_message,
        created_at,
        processed_at
      )
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''',
      [
        job.id,
        job.tenantId,
        job.scheduleId,
        job.branchId,
        job.reportType.code,
        _dateOnly(job.dateFrom),
        _dateOnly(job.dateTo),
        job.exportFormat,
        job.sendToEmail,
        job.status,
        job.errorMessage,
        job.createdAt?.toIso8601String(),
        job.processedAt?.toIso8601String(),
      ],
    );
  }

  static Future<void> saveDeliveryJobs(
    List<BusinessReportDeliveryJobModel> jobs,
  ) async {
    for (final job in jobs) {
      await saveDeliveryJob(job);
    }
  }

  static Future<List<BusinessReportDeliveryJobModel>> loadDeliveryJobs({
    required String tenantId,
    String? branchId,
    bool includeAllBranches = true,
  }) async {
    final rows =
        branchId == null || includeAllBranches
            ? await LocalDatabase.select(
              '''
              SELECT *
              FROM business_report_delivery_jobs
              WHERE tenant_id = ?
              ORDER BY created_at DESC
              LIMIT 100
              ''',
              [tenantId],
            )
            : await LocalDatabase.select(
              '''
              SELECT *
              FROM business_report_delivery_jobs
              WHERE tenant_id = ?
                AND branch_id = ?
              ORDER BY created_at DESC
              LIMIT 100
              ''',
              [tenantId, branchId],
            );

    return rows.map(BusinessReportDeliveryJobModel.fromMap).toList();
  }

  static Future<Map<String, dynamic>> _buildSalesReport({
    required String tenantId,
    required String? branchId,
    required DateTime dateFrom,
    required DateTime dateTo,
    required String plan,
    required bool exportAllowed,
  }) async {
    final report = await SalesReportLocalStore.buildLocalReport(
      tenantId: tenantId,
      branchId: branchId,
      dateFrom: dateFrom,
      dateTo: dateTo,
      plan: plan,
      exportAllowed: exportAllowed,
      netReturns: true,
    );
    return report.toMap();
  }

  static Future<Map<String, dynamic>> _buildProfitLossReport({
    required String tenantId,
    required String? branchId,
    required DateTime dateFrom,
    required DateTime dateTo,
    required String plan,
    required bool exportAllowed,
  }) async {
    final sales = await SalesReportLocalStore.buildLocalReport(
      tenantId: tenantId,
      branchId: branchId,
      dateFrom: dateFrom,
      dateTo: dateTo,
      plan: plan,
      exportAllowed: exportAllowed,
      netReturns: true,
    );
    final repairs = await _repairFinancialTotals(
      tenantId: tenantId,
      branchId: branchId,
      dateFrom: dateFrom,
      dateTo: dateTo,
    );
    final expenses = await _expenseTotals(
      tenantId: tenantId,
      branchId: branchId,
      dateFrom: dateFrom,
      dateTo: dateTo,
    );
    final expenseBreakdown = await _expenseBreakdown(
      tenantId: tenantId,
      branchId: branchId,
      dateFrom: dateFrom,
      dateTo: dateTo,
    );

    final revenue = sales.summary.revenue + repairs.revenue;
    final cogs = sales.summary.cogs + repairs.directCost;
    final grossProfit = revenue - cogs;
    final netProfit = grossProfit - expenses.confirmed;

    return {
      'tenant_id': tenantId,
      'branch_id': branchId,
      'date_from': _dateOnly(dateFrom),
      'date_to': _dateOnly(dateTo),
      'plan': plan,
      'export_allowed': exportAllowed,
      'summary': {
        'revenue': revenue,
        'cogs': cogs,
        'gross_profit': grossProfit,
        'gross_margin_percent': revenue > 0 ? (grossProfit / revenue) * 100 : 0,
        'expenses': expenses.confirmed,
        'draft_expenses': expenses.draft,
        'net_profit': netProfit,
        'net_margin_percent': revenue > 0 ? (netProfit / revenue) * 100 : 0,
      },
      'expense_breakdown': expenseBreakdown,
      'daily_breakdown':
          sales.dailyBreakdown.map((item) {
            final date = _dateOnly(item.date);
            final dayExpenses = expenses.byDate[date] ?? 0;
            final dayRepairRevenue = expenses.repairRevenueByDate[date] ?? 0;
            final dayRepairCost = expenses.repairCostByDate[date] ?? 0;
            final revenue = item.revenue + dayRepairRevenue;
            final cogs = item.cogs + dayRepairCost;
            final grossProfit = revenue - cogs;
            return {
              'date': date,
              'revenue': revenue,
              'cogs': cogs,
              'gross_profit': grossProfit,
              'expenses': dayExpenses,
              'net_profit': grossProfit - dayExpenses,
            };
          }).toList(),
    };
  }

  static Future<Map<String, dynamic>> _buildInventoryReport({
    required String tenantId,
    required String? branchId,
    required DateTime dateFrom,
    required DateTime dateTo,
  }) async {
    final branchSql = branchId == null ? '' : 'AND p.branch_id = ?';
    final args = <Object?>[tenantId, if (branchId != null) branchId];
    final rows = await LocalDatabase.select('''
      SELECT
        p.id AS product_id,
        p.name AS product_name,
        p.sku AS sku,
        p.category_id AS category_id,
        COALESCE(c.name, 'Uncategorized') AS category_name,
        COALESCE(i.quantity, 0) AS quantity,
        COALESCE(i.reorder_threshold, p.reorder_threshold, c.default_reorder_threshold, 1) AS reorder_threshold,
        COALESCE(p.cost_price, 0) AS cost_price,
        COALESCE(i.quantity, 0) * COALESCE(p.cost_price, 0) AS stock_value
      FROM products p
      LEFT JOIN inventory i ON i.product_id = p.id AND i.branch_id = p.branch_id
      LEFT JOIN categories c ON c.id = p.category_id
      WHERE p.tenant_id = ?
        AND COALESCE(p.is_active, 1) = 1
        $branchSql
      ORDER BY p.name ASC
      ''', args);

    final totalProducts = rows.length;
    final totalStock = rows.fold<double>(
      0,
      (sum, row) => sum + _num(row['quantity']),
    );
    final stockValue = rows.fold<double>(
      0,
      (sum, row) => sum + _num(row['stock_value']),
    );
    final lowStock =
        rows.where((row) {
          final qty = _num(row['quantity']);
          final threshold = _num(row['reorder_threshold']);
          return qty > 0 && qty <= (threshold > 0 ? threshold : 5);
        }).toList();
    final outOfStock = rows.where((row) => _num(row['quantity']) <= 0).toList();

    final movingRows = await _movingInventoryRows(
      tenantId: tenantId,
      branchId: branchId,
      dateFrom: dateFrom,
      dateTo: dateTo,
    );

    final categoryTotals = <String, Map<String, dynamic>>{};
    for (final row in rows) {
      final key = (row['category_id'] as String?) ?? 'uncategorized';
      final target = categoryTotals.putIfAbsent(key, () {
        return {
          'category_id': row['category_id'],
          'category_name': row['category_name'],
          'stock_qty': 0.0,
          'stock_value': 0.0,
        };
      });
      target['stock_qty'] = _num(target['stock_qty']) + _num(row['quantity']);
      target['stock_value'] =
          _num(target['stock_value']) + _num(row['stock_value']);
    }

    return {
      'tenant_id': tenantId,
      'branch_id': branchId,
      'date_from': _dateOnly(dateFrom),
      'date_to': _dateOnly(dateTo),
      'summary': {
        'total_products': totalProducts,
        'total_stock': totalStock,
        'stock_value': stockValue,
        'low_stock_count': lowStock.length,
        'out_of_stock_count': outOfStock.length,
      },
      'low_stock': lowStock.map(_inventoryStockItem).toList(),
      'fast_moving': movingRows.take(10).toList(),
      'dead_stock':
          rows
              .where((row) => _num(row['quantity']) > 0)
              .where(
                (row) =>
                    !movingRows.any(
                      (moving) => moving['product_id'] == row['product_id'],
                    ),
              )
              .take(10)
              .map(_inventoryDeadStockItem)
              .toList(),
      'category_stock': categoryTotals.values.toList(),
    };
  }

  static Future<Map<String, dynamic>> _buildCustomerCreditReport({
    required String tenantId,
    required String? branchId,
    required DateTime dateFrom,
    required DateTime dateTo,
  }) async {
    final branchSql = branchId == null ? '' : 'AND c.branch_id = ?';
    final args = <Object?>[tenantId, if (branchId != null) branchId];
    final rows = await LocalDatabase.select('''
      SELECT
        c.id AS customer_id,
        c.full_name AS customer_name,
        c.phone AS phone,
        COALESCE(c.credit_limit, 0) AS credit_limit,
        COALESCE(c.outstanding_balance, 0) AS outstanding_balance
      FROM customers c
      WHERE c.tenant_id = ?
        $branchSql
      ORDER BY outstanding_balance DESC
      ''', args);
    final topCustomers = await _topCustomerRows(
      tenantId: tenantId,
      branchId: branchId,
      dateFrom: dateFrom,
      dateTo: dateTo,
    );
    final creditRows =
        rows.where((row) => _num(row['outstanding_balance']) > 0.01).toList();

    return {
      'tenant_id': tenantId,
      'branch_id': branchId,
      'date_from': _dateOnly(dateFrom),
      'date_to': _dateOnly(dateTo),
      'summary': {
        'total_customers': rows.length,
        'credit_customers': creditRows.length,
        'outstanding_balance': creditRows.fold<double>(
          0,
          (sum, row) => sum + _num(row['outstanding_balance']),
        ),
      },
      'top_customers': topCustomers,
      'credit_customers': creditRows,
    };
  }

  static Future<Map<String, dynamic>> _buildRepairReport({
    required String tenantId,
    required String? branchId,
    required DateTime dateFrom,
    required DateTime dateTo,
  }) async {
    final from = _dateOnly(dateFrom);
    final to = _dateOnly(dateTo);
    final branchSql = branchId == null ? '' : 'AND branch_id = ?';
    final args = <Object?>[tenantId, if (branchId != null) branchId, from, to];
    final rows = await LocalDatabase.select('''
      SELECT *
      FROM repair_tickets
      WHERE tenant_id = ?
        $branchSql
        AND substr(created_at, 1, 10) BETWEEN ? AND ?
      ''', args);
    final revenueRows = await LocalDatabase.select('''
      SELECT
        status,
        technician_id,
        COUNT(*) AS repairs,
        COALESCE(SUM(total_cost), 0) AS revenue
      FROM repair_tickets
      WHERE tenant_id = ?
        $branchSql
        AND status IN ('completed', 'delivered')
        AND substr(COALESCE(delivered_at, completed_at), 1, 10) BETWEEN ? AND ?
      GROUP BY status, technician_id
      ''', args);
    final repairFinancials = await _repairFinancialTotals(
      tenantId: tenantId,
      branchId: branchId,
      dateFrom: dateFrom,
      dateTo: dateTo,
    );
    final repairRevenue = repairFinancials.revenue;
    final completedRepairs = revenueRows.fold<int>(
      0,
      (sum, row) => sum + _int(row['repairs']),
    );
    final openRepairs =
        rows
            .where(
              (row) =>
                  row['status'] != 'completed' &&
                  row['status'] != 'delivered' &&
                  row['status'] != 'cancelled',
            )
            .length;

    return {
      'tenant_id': tenantId,
      'branch_id': branchId,
      'date_from': _dateOnly(dateFrom),
      'date_to': _dateOnly(dateTo),
      'summary': {
        'total_repairs': rows.length,
        'open_repairs': openRepairs,
        'completed_repairs': completedRepairs,
        'repair_revenue': repairRevenue,
      },
      'status_breakdown':
          revenueRows
              .map(
                (row) => {
                  'status': row['status'],
                  'count': _int(row['repairs']),
                  'revenue': _num(row['revenue']),
                },
              )
              .toList(),
      'technician_breakdown':
          revenueRows
              .map(
                (row) => {
                  'technician_id': row['technician_id'],
                  'repairs': _int(row['repairs']),
                  'completed': _int(row['repairs']),
                  'revenue': _num(row['revenue']),
                },
              )
              .toList(),
    };
  }

  static Future<Map<String, dynamic>> _buildCashFlowReport({
    required String tenantId,
    required String? branchId,
    required DateTime dateFrom,
    required DateTime dateTo,
  }) async {
    final cash = await _cashFlowTotals(
      tenantId: tenantId,
      branchId: branchId,
      dateFrom: dateFrom,
      dateTo: dateTo,
    );
    return {
      'tenant_id': tenantId,
      'branch_id': branchId,
      'date_from': _dateOnly(dateFrom),
      'date_to': _dateOnly(dateTo),
      'summary': {
        'cash_in': cash.cashIn,
        'cash_out': cash.cashOut,
        'net_cash': cash.cashIn - cash.cashOut,
      },
      'sales_payment_breakdown': cash.salesBreakdown,
      'expense_payment_breakdown': cash.expenseBreakdown,
    };
  }

  static Future<Map<String, dynamic>> _buildDashboardReport({
    required String tenantId,
    required String? branchId,
    required DateTime dateFrom,
    required DateTime dateTo,
    required String plan,
    required bool exportAllowed,
  }) async {
    final sales = await _buildSalesReport(
      tenantId: tenantId,
      branchId: branchId,
      dateFrom: dateFrom,
      dateTo: dateTo,
      plan: plan,
      exportAllowed: exportAllowed,
    );
    final profitLoss = await _buildProfitLossReport(
      tenantId: tenantId,
      branchId: branchId,
      dateFrom: dateFrom,
      dateTo: dateTo,
      plan: plan,
      exportAllowed: exportAllowed,
    );
    final inventory = await _buildInventoryReport(
      tenantId: tenantId,
      branchId: branchId,
      dateFrom: dateFrom,
      dateTo: dateTo,
    );
    final customers = await _buildCustomerCreditReport(
      tenantId: tenantId,
      branchId: branchId,
      dateFrom: dateFrom,
      dateTo: dateTo,
    );
    final repairs = await _buildRepairReport(
      tenantId: tenantId,
      branchId: branchId,
      dateFrom: dateFrom,
      dateTo: dateTo,
    );
    final cashFlow = await _buildCashFlowReport(
      tenantId: tenantId,
      branchId: branchId,
      dateFrom: dateFrom,
      dateTo: dateTo,
    );
    return {
      'tenant_id': tenantId,
      'branch_id': branchId,
      'date_from': _dateOnly(dateFrom),
      'date_to': _dateOnly(dateTo),
      'sales': sales,
      'profit_loss': profitLoss,
      'inventory': inventory,
      'customers': customers,
      'repairs': repairs,
      'cash_flow': cashFlow,
    };
  }

  static Future<_RepairFinancialTotals> _repairFinancialTotals({
    required String tenantId,
    required String? branchId,
    required DateTime dateFrom,
    required DateTime dateTo,
  }) async {
    final branchSql = branchId == null ? '' : 'AND branch_id = ?';
    final rows = await LocalDatabase.select(
      '''
      SELECT
        COALESCE(SUM(revenue_amount), 0) AS revenue,
        COALESCE(SUM(
          inventory_cost + direct_parts_cost +
          commission_cost + other_direct_cost
        ), 0) AS direct_cost,
        COALESCE(SUM(gross_profit), 0) AS gross_profit
      FROM repair_financial_events
      WHERE tenant_id = ?
        $branchSql
        AND substr(effective_at, 1, 10) BETWEEN ? AND ?
      ''',
      [
        tenantId,
        if (branchId != null) branchId,
        _dateOnly(dateFrom),
        _dateOnly(dateTo),
      ],
    );
    return _RepairFinancialTotals(
      revenue: _num(rows.first['revenue']),
      directCost: _num(rows.first['direct_cost']),
      grossProfit: _num(rows.first['gross_profit']),
    );
  }

  static Future<_ExpenseTotals> _expenseTotals({
    required String tenantId,
    required String? branchId,
    required DateTime dateFrom,
    required DateTime dateTo,
  }) async {
    final branchSql = branchId == null ? '' : 'AND branch_id = ?';
    final args = <Object?>[
      tenantId,
      if (branchId != null) branchId,
      _dateOnly(dateFrom),
      _dateOnly(dateTo),
    ];
    final rows = await LocalDatabase.select('''
      SELECT status, COALESCE(SUM(amount), 0) AS total
      FROM expenses
      WHERE tenant_id = ?
        $branchSql
        AND expense_date BETWEEN ? AND ?
        AND status IN ('confirmed', 'draft')
      GROUP BY status
      ''', args);
    final byDateRows = await LocalDatabase.select('''
      SELECT expense_date AS date, COALESCE(SUM(amount), 0) AS total
      FROM expenses
      WHERE tenant_id = ?
        $branchSql
        AND expense_date BETWEEN ? AND ?
        AND status = 'confirmed'
      GROUP BY expense_date
      ''', args);
    final repairRows = await LocalDatabase.select('''
      SELECT substr(effective_at, 1, 10) AS date,
        COALESCE(SUM(revenue_amount), 0) AS total,
        COALESCE(SUM(
          inventory_cost + direct_parts_cost +
          commission_cost + other_direct_cost
        ), 0) AS direct_cost
      FROM repair_financial_events
      WHERE tenant_id = ?
        $branchSql
        AND substr(effective_at, 1, 10) BETWEEN ? AND ?
      GROUP BY substr(effective_at, 1, 10)
      ''', args);

    var confirmed = 0.0;
    var draft = 0.0;
    for (final row in rows) {
      if (row['status'] == 'draft') {
        draft += _num(row['total']);
      } else {
        confirmed += _num(row['total']);
      }
    }

    return _ExpenseTotals(
      confirmed: confirmed,
      draft: draft,
      byDate: {
        for (final row in byDateRows)
          row['date'].toString(): _num(row['total']),
      },
      repairRevenueByDate: {
        for (final row in repairRows)
          row['date'].toString(): _num(row['total']),
      },
      repairCostByDate: {
        for (final row in repairRows)
          row['date'].toString(): _num(row['direct_cost']),
      },
    );
  }

  static Future<List<Map<String, dynamic>>> _expenseBreakdown({
    required String tenantId,
    required String? branchId,
    required DateTime dateFrom,
    required DateTime dateTo,
  }) async {
    final branchSql = branchId == null ? '' : 'AND branch_id = ?';
    final rows = await LocalDatabase.select(
      '''
      SELECT
        COALESCE(category_name, 'Uncategorized') AS category_name,
        COALESCE(SUM(amount), 0) AS amount
      FROM expenses
      WHERE tenant_id = ?
        $branchSql
        AND expense_date BETWEEN ? AND ?
        AND status = 'confirmed'
      GROUP BY COALESCE(category_name, 'Uncategorized')
      ORDER BY amount DESC
      ''',
      [
        tenantId,
        if (branchId != null) branchId,
        _dateOnly(dateFrom),
        _dateOnly(dateTo),
      ],
    );
    return rows;
  }

  static Future<_CashFlowTotals> _cashFlowTotals({
    required String tenantId,
    required String? branchId,
    required DateTime dateFrom,
    required DateTime dateTo,
  }) async {
    final cash = await LedgerCashSummary.load(
      tenantId: tenantId,
      branchId: branchId,
      dateFrom: dateFrom,
      dateTo: dateTo,
    );

    return _CashFlowTotals(
      cashIn: cash.cashIn,
      cashOut: cash.cashOut,
      salesBreakdown:
          cash.inflowBreakdown.entries
              .map(
                (entry) => {'payment_mode': entry.key, 'amount': entry.value},
              )
              .toList(),
      expenseBreakdown:
          cash.outflowBreakdown.entries
              .map(
                (entry) => {'payment_mode': entry.key, 'amount': entry.value},
              )
              .toList(),
    );
  }

  static Future<List<Map<String, dynamic>>> _movingInventoryRows({
    required String tenantId,
    required String? branchId,
    required DateTime dateFrom,
    required DateTime dateTo,
  }) async {
    final report = await SalesReportLocalStore.buildLocalReport(
      tenantId: tenantId,
      branchId: branchId,
      dateFrom: dateFrom,
      dateTo: dateTo,
      netReturns: true,
    );
    return report.productBreakdown
        .where((item) => item.quantity > 0)
        .map(
          (item) => {
            'product_id': item.productId,
            'product_name': item.productName,
            'sku': item.sku,
            'quantity_sold': item.quantity,
            'revenue': item.revenue,
            'gross_profit': item.grossProfit,
          },
        )
        .toList();
  }

  static Future<List<Map<String, dynamic>>> _topCustomerRows({
    required String tenantId,
    required String? branchId,
    required DateTime dateFrom,
    required DateTime dateTo,
  }) async {
    final report = await SalesReportLocalStore.buildLocalReport(
      tenantId: tenantId,
      branchId: branchId,
      dateFrom: dateFrom,
      dateTo: dateTo,
      netReturns: true,
    );
    return report.customerBreakdown
        .take(10)
        .map(
          (item) => {
            'customer_id': item.customerId,
            'customer_name': item.customerName,
            'orders': item.orders,
            'revenue': item.revenue,
          },
        )
        .toList();
  }

  static Map<String, dynamic> _inventoryStockItem(Map<String, dynamic> row) {
    return {
      'product_id': row['product_id'],
      'product_name': row['product_name'],
      'sku': row['sku'],
      'quantity': _num(row['quantity']),
      'reorder_threshold': _num(row['reorder_threshold']),
      'stock_value': _num(row['stock_value']),
    };
  }

  static Map<String, dynamic> _inventoryDeadStockItem(
    Map<String, dynamic> row,
  ) {
    return {
      'product_id': row['product_id'],
      'product_name': row['product_name'],
      'sku': row['sku'],
      'quantity': _num(row['quantity']),
      'stock_value': _num(row['stock_value']),
    };
  }

  static String _cacheId({
    required BusinessReportType reportType,
    required String tenantId,
    required String? branchId,
    required DateTime dateFrom,
    required DateTime dateTo,
  }) {
    return [
      reportType.code,
      tenantId,
      branchId ?? 'all',
      _dateOnly(dateFrom),
      _dateOnly(dateTo),
    ].join('|');
  }

  static String _dateOnly(DateTime date) {
    final year = date.year.toString().padLeft(4, '0');
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  static int _int(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString()) ?? 0;
  }

  static double _num(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? 0;
  }
}

class _ExpenseTotals {
  final double confirmed;
  final double draft;
  final Map<String, double> byDate;
  final Map<String, double> repairRevenueByDate;
  final Map<String, double> repairCostByDate;

  const _ExpenseTotals({
    required this.confirmed,
    required this.draft,
    required this.byDate,
    required this.repairRevenueByDate,
    required this.repairCostByDate,
  });
}

class _CashFlowTotals {
  final double cashIn;
  final double cashOut;
  final List<Map<String, dynamic>> salesBreakdown;
  final List<Map<String, dynamic>> expenseBreakdown;

  const _CashFlowTotals({
    required this.cashIn,
    required this.cashOut,
    required this.salesBreakdown,
    required this.expenseBreakdown,
  });
}

class _RepairFinancialTotals {
  final double revenue;
  final double directCost;
  final double grossProfit;

  const _RepairFinancialTotals({
    required this.revenue,
    required this.directCost,
    required this.grossProfit,
  });
}
