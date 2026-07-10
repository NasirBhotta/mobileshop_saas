import 'dart:convert';

import 'package:mobileshop_saas/core/local/local_database.dart';

import '../models/sales_report_models.dart';

class SalesReportLocalStore {
  // ════════════════════════════════════════
  // REPORT CACHE
  // ════════════════════════════════════════

  static Future<void> saveReportCache(SalesAnalyticsReportModel report) async {
    await LocalDatabase.execute(
      '''
      INSERT OR REPLACE INTO sales_report_cache(
        id,
        tenant_id,
        branch_id,
        date_from,
        date_to,
        report_json,
        created_at
      )
      VALUES (?, ?, ?, ?, ?, ?, ?)
      ''',
      [
        _cacheId(
          tenantId: report.tenantId,
          branchId: report.branchId,
          dateFrom: report.dateFrom,
          dateTo: report.dateTo,
        ),
        report.tenantId,
        report.branchId,
        _dateOnly(report.dateFrom),
        _dateOnly(report.dateTo),
        jsonEncode(report.toMap()),
        DateTime.now().toIso8601String(),
      ],
    );
  }

  static Future<SalesAnalyticsReportModel?> loadReportCache({
    required String tenantId,
    required String? branchId,
    required DateTime dateFrom,
    required DateTime dateTo,
  }) async {
    final rows = await LocalDatabase.select(
      '''
      SELECT *
      FROM sales_report_cache
      WHERE id = ?
      LIMIT 1
      ''',
      [
        _cacheId(
          tenantId: tenantId,
          branchId: branchId,
          dateFrom: dateFrom,
          dateTo: dateTo,
        ),
      ],
    );

    if (rows.isEmpty) return null;

    final json = jsonDecode(rows.first['report_json'] as String);

    return SalesAnalyticsReportModel.fromMap(
      Map<String, dynamic>.from(json as Map),
    );
  }

  // ════════════════════════════════════════
  // LOCAL REPORT CALCULATION
  // ════════════════════════════════════════

  static Future<SalesAnalyticsReportModel> buildLocalReport({
    required String tenantId,
    required String? branchId,
    required DateTime dateFrom,
    required DateTime dateTo,
    String plan = 'starter',
    bool exportAllowed = false,
    bool netReturns = false,
  }) async {
    final from = _dateOnly(dateFrom);
    final to = _dateOnly(dateTo);

    final branchFilter = branchId == null ? '' : 'AND s.branch_id = ?';

    final branchArg = branchId == null ? <Object?>[] : <Object?>[branchId];
    final tenantJoin = '''
      JOIN branches tenant_branch
        ON tenant_branch.id = s.branch_id
       AND tenant_branch.tenant_id = ?
      ''';
    final reportArgs = <Object?>[tenantId, ...branchArg, from, to];
    final reportArgsWithReturns =
        netReturns ? <Object?>[...reportArgs, ...reportArgs] : reportArgs;
    const saleItemCogs = '''
      COALESCE(
        si.cogs_total,
        si.unit_cost_at_sale * si.quantity,
        p.cost_price * si.quantity,
        0
      )
      ''';
    const returnItemCogs = '''
      COALESCE(
        CASE
          WHEN si.quantity IS NOT NULL AND si.quantity > 0 THEN
            (
              COALESCE(
                si.cogs_total,
                si.unit_cost_at_sale * si.quantity,
                p.cost_price * si.quantity,
                0
              ) / si.quantity
            ) * ri.quantity
          ELSE COALESCE(si.unit_cost_at_sale, p.cost_price, 0) * ri.quantity
        END,
        0
      )
      ''';

    final summaryRows = await LocalDatabase.select('''
      SELECT
        COUNT(DISTINCT s.id) AS total_orders,
        COALESCE(SUM(s.total), 0) AS revenue,
        COALESCE(SUM(s.discount_amount), 0) AS discount,
        COALESCE(SUM(s.tax_amount), 0) AS tax
      FROM sales s
      $tenantJoin
      WHERE s.status = 'completed'
        $branchFilter
        AND substr(s.created_at, 1, 10) BETWEEN ? AND ?
      ''', reportArgs);

    final itemSummaryRows = await LocalDatabase.select('''
      SELECT
        COALESCE(SUM(quantity), 0) AS total_units,
        COALESCE(SUM(cogs), 0) AS cogs,
        COALESCE(SUM(revenue - cogs), 0) AS gross_profit
      FROM (
        SELECT
          si.quantity AS quantity,
          COALESCE(si.line_total, si.unit_price * si.quantity, 0) AS revenue,
          $saleItemCogs AS cogs
        FROM sale_items si
        JOIN sales s ON s.id = si.sale_id
        $tenantJoin
        LEFT JOIN products p ON p.id = si.product_id
        WHERE s.status = 'completed'
          $branchFilter
          AND substr(s.created_at, 1, 10) BETWEEN ? AND ?
        ${netReturns ? '''
        UNION ALL
        SELECT
          -ri.quantity AS quantity,
          -ri.refund_amount AS revenue,
          -$returnItemCogs AS cogs
        FROM sale_return_items ri
        JOIN sale_returns r ON r.id = ri.return_id
        JOIN branches tenant_branch
          ON tenant_branch.id = r.branch_id
         AND tenant_branch.tenant_id = ?
        LEFT JOIN sale_items si
          ON si.sale_id = r.original_sale_id
         AND si.product_id = ri.product_id
        LEFT JOIN products p ON p.id = ri.product_id
        WHERE r.status = 'approved'
          ${branchId == null ? '' : 'AND r.branch_id = ?'}
          AND substr(r.created_at, 1, 10) BETWEEN ? AND ?
        ''' : ''}
      )
      ''', reportArgsWithReturns);

    final returnSummaryRows = await LocalDatabase.select('''
      SELECT
        COALESCE(SUM(ri.quantity), 0) AS returned_units,
        COALESCE(SUM(ri.refund_amount), 0) AS refund
      FROM sale_return_items ri
      JOIN sale_returns r ON r.id = ri.return_id
      JOIN branches tenant_branch
        ON tenant_branch.id = r.branch_id
       AND tenant_branch.tenant_id = ?
      WHERE r.status = 'approved'
        ${branchId == null ? '' : 'AND r.branch_id = ?'}
        AND substr(r.created_at, 1, 10) BETWEEN ? AND ?
      ''', reportArgs);

    final grossRevenue = _double(summaryRows.first['revenue']);
    final returnsAmount = _double(returnSummaryRows.first['refund']);
    final netRevenue = grossRevenue - returnsAmount;
    final revenue = netReturns ? netRevenue : grossRevenue;
    final cogs = _double(itemSummaryRows.first['cogs']);
    final grossProfit = _double(itemSummaryRows.first['gross_profit']);

    final summary = SalesReportSummaryModel(
      totalOrders: _int(summaryRows.first['total_orders']),
      totalUnits: _int(itemSummaryRows.first['total_units']),
      revenue: revenue,
      discount: _double(summaryRows.first['discount']),
      tax: _double(summaryRows.first['tax']),
      cogs: cogs,
      grossProfit: grossProfit,
      grossMarginPercent: revenue > 0 ? (grossProfit / revenue) * 100 : 0,
      returnedUnits: _int(returnSummaryRows.first['returned_units']),
      returnsAmount: returnsAmount,
      netRevenue: netRevenue,
    );

    final productRows = await LocalDatabase.select('''
      SELECT
        product_id,
        product_name,
        sku,
        COALESCE(SUM(quantity), 0) AS quantity,
        COALESCE(SUM(revenue), 0) AS revenue,
        COALESCE(SUM(cogs), 0) AS cogs,
        COALESCE(SUM(revenue - cogs), 0) AS gross_profit
      FROM (
        SELECT
          si.product_id AS product_id,
          COALESCE(si.product_name, p.name, 'Unknown Product') AS product_name,
          COALESCE(si.product_sku, p.sku) AS sku,
          si.quantity AS quantity,
          COALESCE(si.line_total, si.unit_price * si.quantity, 0) AS revenue,
          $saleItemCogs AS cogs
        FROM sale_items si
        JOIN sales s ON s.id = si.sale_id
        $tenantJoin
        LEFT JOIN products p ON p.id = si.product_id
        WHERE s.status = 'completed'
          $branchFilter
          AND substr(s.created_at, 1, 10) BETWEEN ? AND ?
        ${netReturns ? '''
        UNION ALL
        SELECT
          ri.product_id AS product_id,
          COALESCE(ri.product_name, p.name, 'Unknown Product') AS product_name,
          COALESCE(ri.product_sku, p.sku) AS sku,
          -ri.quantity AS quantity,
          -ri.refund_amount AS revenue,
          -$returnItemCogs AS cogs
        FROM sale_return_items ri
        JOIN sale_returns r ON r.id = ri.return_id
        JOIN branches tenant_branch
          ON tenant_branch.id = r.branch_id
         AND tenant_branch.tenant_id = ?
        LEFT JOIN sale_items si
          ON si.sale_id = r.original_sale_id
         AND si.product_id = ri.product_id
        LEFT JOIN products p ON p.id = ri.product_id
        WHERE r.status = 'approved'
          ${branchId == null ? '' : 'AND r.branch_id = ?'}
          AND substr(r.created_at, 1, 10) BETWEEN ? AND ?
        ''' : ''}
      )
      GROUP BY product_id, product_name, sku
      ORDER BY gross_profit DESC
      ''', reportArgsWithReturns);

    final customerRows = await LocalDatabase.select('''
      SELECT
        customer_id,
        customer_name,
        COUNT(DISTINCT sale_id) AS orders,
        COALESCE(SUM(revenue), 0) AS revenue,
        COALESCE(SUM(revenue - cogs), 0) AS gross_profit
      FROM (
        SELECT
          s.id AS sale_id,
          s.customer_id AS customer_id,
          COALESCE(c.full_name, 'Walk-in Customer') AS customer_name,
          COALESCE(si.line_total, si.unit_price * si.quantity, 0) AS revenue,
          $saleItemCogs AS cogs
        FROM sale_items si
        JOIN sales s ON s.id = si.sale_id
        $tenantJoin
        LEFT JOIN customers c ON c.id = s.customer_id
        LEFT JOIN products p ON p.id = si.product_id
        WHERE s.status = 'completed'
          $branchFilter
          AND substr(s.created_at, 1, 10) BETWEEN ? AND ?
        ${netReturns ? '''
        UNION ALL
        SELECT
          r.original_sale_id AS sale_id,
          s.customer_id AS customer_id,
          COALESCE(c.full_name, 'Walk-in Customer') AS customer_name,
          -ri.refund_amount AS revenue,
          -$returnItemCogs AS cogs
        FROM sale_return_items ri
        JOIN sale_returns r ON r.id = ri.return_id
        JOIN branches tenant_branch
          ON tenant_branch.id = r.branch_id
         AND tenant_branch.tenant_id = ?
        LEFT JOIN sales s ON s.id = r.original_sale_id
        LEFT JOIN sale_items si
          ON si.sale_id = r.original_sale_id
         AND si.product_id = ri.product_id
        LEFT JOIN products p ON p.id = ri.product_id
        LEFT JOIN customers c ON c.id = s.customer_id
        WHERE r.status = 'approved'
          ${branchId == null ? '' : 'AND r.branch_id = ?'}
          AND substr(r.created_at, 1, 10) BETWEEN ? AND ?
        ''' : ''}
      )
      GROUP BY customer_id, customer_name
      ORDER BY revenue DESC
      ''', reportArgsWithReturns);

    final branchRows = await LocalDatabase.select('''
      SELECT
        branch_id,
        branch_name,
        COUNT(DISTINCT sale_id) AS orders,
        COALESCE(SUM(revenue), 0) AS revenue,
        COALESCE(SUM(cogs), 0) AS cogs,
        COALESCE(SUM(revenue - cogs), 0) AS gross_profit
      FROM (
        SELECT
          s.id AS sale_id,
          s.branch_id AS branch_id,
          COALESCE(b.name, 'Branch') AS branch_name,
          COALESCE(si.line_total, si.unit_price * si.quantity, 0) AS revenue,
          $saleItemCogs AS cogs
        FROM sale_items si
        JOIN sales s ON s.id = si.sale_id
        $tenantJoin
        LEFT JOIN branches b ON b.id = s.branch_id
        LEFT JOIN products p ON p.id = si.product_id
        WHERE s.status = 'completed'
          $branchFilter
          AND substr(s.created_at, 1, 10) BETWEEN ? AND ?
        ${netReturns ? '''
        UNION ALL
        SELECT
          r.original_sale_id AS sale_id,
          r.branch_id AS branch_id,
          COALESCE(b.name, 'Branch') AS branch_name,
          -ri.refund_amount AS revenue,
          -$returnItemCogs AS cogs
        FROM sale_return_items ri
        JOIN sale_returns r ON r.id = ri.return_id
        JOIN branches tenant_branch
          ON tenant_branch.id = r.branch_id
         AND tenant_branch.tenant_id = ?
        LEFT JOIN sale_items si
          ON si.sale_id = r.original_sale_id
         AND si.product_id = ri.product_id
        LEFT JOIN products p ON p.id = ri.product_id
        LEFT JOIN branches b ON b.id = r.branch_id
        WHERE r.status = 'approved'
          ${branchId == null ? '' : 'AND r.branch_id = ?'}
          AND substr(r.created_at, 1, 10) BETWEEN ? AND ?
        ''' : ''}
      )
      GROUP BY branch_id, branch_name
      ORDER BY revenue DESC
      ''', reportArgsWithReturns);

    final categoryRows = await LocalDatabase.select('''
      SELECT
        category_id,
        category_name,
        COALESCE(SUM(quantity), 0) AS quantity,
        COALESCE(SUM(revenue), 0) AS revenue,
        COALESCE(SUM(cogs), 0) AS cogs,
        COALESCE(SUM(revenue - cogs), 0) AS gross_profit
      FROM (
        SELECT
          p.category_id AS category_id,
          COALESCE(c.name, 'Uncategorized') AS category_name,
          si.quantity AS quantity,
          COALESCE(si.line_total, si.unit_price * si.quantity, 0) AS revenue,
          $saleItemCogs AS cogs
        FROM sale_items si
        JOIN sales s ON s.id = si.sale_id
        $tenantJoin
        LEFT JOIN products p ON p.id = si.product_id
        LEFT JOIN categories c ON c.id = p.category_id
        WHERE s.status = 'completed'
          $branchFilter
          AND substr(s.created_at, 1, 10) BETWEEN ? AND ?
        ${netReturns ? '''
        UNION ALL
        SELECT
          p.category_id AS category_id,
          COALESCE(c.name, 'Uncategorized') AS category_name,
          -ri.quantity AS quantity,
          -ri.refund_amount AS revenue,
          -$returnItemCogs AS cogs
        FROM sale_return_items ri
        JOIN sale_returns r ON r.id = ri.return_id
        JOIN branches tenant_branch
          ON tenant_branch.id = r.branch_id
         AND tenant_branch.tenant_id = ?
        LEFT JOIN sale_items si
          ON si.sale_id = r.original_sale_id
         AND si.product_id = ri.product_id
        LEFT JOIN products p ON p.id = ri.product_id
        LEFT JOIN categories c ON c.id = p.category_id
        WHERE r.status = 'approved'
          ${branchId == null ? '' : 'AND r.branch_id = ?'}
          AND substr(r.created_at, 1, 10) BETWEEN ? AND ?
        ''' : ''}
      )
      GROUP BY category_id, category_name
      ORDER BY gross_profit DESC
      ''', reportArgsWithReturns);

    final dailyRows = await LocalDatabase.select('''
      SELECT
        date,
        COUNT(DISTINCT sale_id) AS orders,
        COALESCE(SUM(revenue), 0) AS revenue,
        COALESCE(SUM(cogs), 0) AS cogs,
        COALESCE(SUM(revenue - cogs), 0) AS gross_profit
      FROM (
        SELECT
          substr(s.created_at, 1, 10) AS date,
          s.id AS sale_id,
          COALESCE(si.line_total, si.unit_price * si.quantity, 0) AS revenue,
          $saleItemCogs AS cogs
        FROM sale_items si
        JOIN sales s ON s.id = si.sale_id
        $tenantJoin
        LEFT JOIN products p ON p.id = si.product_id
        WHERE s.status = 'completed'
          $branchFilter
          AND substr(s.created_at, 1, 10) BETWEEN ? AND ?
        ${netReturns ? '''
        UNION ALL
        SELECT
          substr(r.created_at, 1, 10) AS date,
          r.original_sale_id AS sale_id,
          -ri.refund_amount AS revenue,
          -$returnItemCogs AS cogs
        FROM sale_return_items ri
        JOIN sale_returns r ON r.id = ri.return_id
        JOIN branches tenant_branch
          ON tenant_branch.id = r.branch_id
         AND tenant_branch.tenant_id = ?
        LEFT JOIN sale_items si
          ON si.sale_id = r.original_sale_id
         AND si.product_id = ri.product_id
        LEFT JOIN products p ON p.id = ri.product_id
        WHERE r.status = 'approved'
          ${branchId == null ? '' : 'AND r.branch_id = ?'}
          AND substr(r.created_at, 1, 10) BETWEEN ? AND ?
        ''' : ''}
      )
      GROUP BY date
      ORDER BY date ASC
      ''', reportArgsWithReturns);

    final report = SalesAnalyticsReportModel(
      tenantId: tenantId,
      branchId: branchId,
      dateFrom: dateFrom,
      dateTo: dateTo,
      plan: plan,
      exportAllowed: exportAllowed,
      summary: summary,
      productBreakdown:
          productRows.map((row) {
            final revenue = _double(row['revenue']);
            final grossProfit = _double(row['gross_profit']);

            return SalesProductBreakdownItem(
              productId: row['product_id'] as String?,
              productName:
                  (row['product_name'] as String?) ?? 'Unknown Product',
              sku: row['sku'] as String?,
              quantity: _int(row['quantity']),
              revenue: revenue,
              cogs: _double(row['cogs']),
              grossProfit: grossProfit,
              marginPercent: revenue > 0 ? (grossProfit / revenue) * 100 : 0,
            );
          }).toList(),
      customerBreakdown:
          customerRows.map((row) {
            return SalesCustomerBreakdownItem(
              customerId: row['customer_id'] as String?,
              customerName:
                  (row['customer_name'] as String?) ?? 'Walk-in Customer',
              orders: _int(row['orders']),
              revenue: _double(row['revenue']),
              grossProfit: _double(row['gross_profit']),
            );
          }).toList(),
      branchBreakdown:
          branchRows.map((row) {
            final revenue = _double(row['revenue']);
            final grossProfit = _double(row['gross_profit']);
            return SalesBranchBreakdownItem(
              branchId: row['branch_id'] as String?,
              branchName: (row['branch_name'] as String?) ?? 'Branch',
              orders: _int(row['orders']),
              revenue: _double(row['revenue']),
              cogs: _double(row['cogs']),
              grossProfit: grossProfit,
              marginPercent: revenue > 0 ? (grossProfit / revenue) * 100 : 0,
            );
          }).toList(),
      categoryBreakdown:
          categoryRows.map((row) {
            final revenue = _double(row['revenue']);
            final grossProfit = _double(row['gross_profit']);

            return SalesCategoryBreakdownItem(
              categoryId: row['category_id'] as String?,
              categoryName:
                  (row['category_name'] as String?) ?? 'Uncategorized',
              quantity: _int(row['quantity']),
              revenue: revenue,
              cogs: _double(row['cogs']),
              grossProfit: grossProfit,
              marginPercent: revenue > 0 ? (grossProfit / revenue) * 100 : 0,
            );
          }).toList(),
      dailyBreakdown:
          dailyRows.map((row) {
            return SalesDailyBreakdownItem(
              date: DateTime.tryParse(row['date'].toString()) ?? DateTime.now(),
              orders: _int(row['orders']),
              revenue: _double(row['revenue']),
              cogs: _double(row['cogs']),
              grossProfit: _double(row['gross_profit']),
            );
          }).toList(),
    );

    await saveReportCache(report);

    return report;
  }

  // ════════════════════════════════════════
  // SCHEDULES
  // ════════════════════════════════════════

  static Future<void> saveSchedule(SalesReportScheduleModel schedule) async {
    await LocalDatabase.execute(
      '''
      INSERT OR REPLACE INTO sales_report_schedules(
        id,
        tenant_id,
        branch_id,
        name,
        cadence,
        report_scope,
        export_format,
        send_to_email,
        include_product_breakdown,
        include_customer_breakdown,
        include_branch_breakdown,
        include_category_breakdown,
        next_run_at,
        last_run_at,
        status,
        created_by,
        created_at,
        updated_at
      )
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''',
      [
        schedule.id,
        schedule.tenantId,
        schedule.branchId,
        schedule.name,
        schedule.cadence.code,
        schedule.reportScope.code,
        schedule.exportFormat.code,
        schedule.sendToEmail,
        schedule.includeProductBreakdown ? 1 : 0,
        schedule.includeCustomerBreakdown ? 1 : 0,
        schedule.includeBranchBreakdown ? 1 : 0,
        schedule.includeCategoryBreakdown ? 1 : 0,
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
    List<SalesReportScheduleModel> schedules,
  ) async {
    for (final schedule in schedules) {
      await saveSchedule(schedule);
    }
  }

  static Future<List<SalesReportScheduleModel>> loadSchedules({
    required String tenantId,
    String? branchId,
    bool includeAllBranches = true,
  }) async {
    final rows =
        branchId == null
            ? await LocalDatabase.select(
              '''
            SELECT *
            FROM sales_report_schedules
            WHERE tenant_id = ?
            ORDER BY next_run_at ASC
            ''',
              [tenantId],
            )
            : includeAllBranches
            ? await LocalDatabase.select(
              '''
            SELECT *
            FROM sales_report_schedules
            WHERE tenant_id = ?
              AND (branch_id = ? OR branch_id IS NULL)
            ORDER BY next_run_at ASC
            ''',
              [tenantId, branchId],
            )
            : await LocalDatabase.select(
              '''
            SELECT *
            FROM sales_report_schedules
            WHERE tenant_id = ?
              AND branch_id = ?
            ORDER BY next_run_at ASC
            ''',
              [tenantId, branchId],
            );

    return rows.map(SalesReportScheduleModel.fromMap).toList();
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
      UPDATE sales_report_schedules
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

  // ════════════════════════════════════════
  // DELIVERY JOBS
  // ════════════════════════════════════════

  static Future<void> saveDeliveryJob(SalesReportDeliveryJobModel job) async {
    await LocalDatabase.execute(
      '''
      INSERT OR REPLACE INTO sales_report_delivery_jobs(
        id,
        tenant_id,
        schedule_id,
        branch_id,
        date_from,
        date_to,
        export_format,
        send_to_email,
        status,
        error_message,
        created_at,
        processed_at
      )
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''',
      [
        job.id,
        job.tenantId,
        job.scheduleId,
        job.branchId,
        _dateOnly(job.dateFrom),
        _dateOnly(job.dateTo),
        job.exportFormat.code,
        job.sendToEmail,
        job.status,
        job.errorMessage,
        job.createdAt?.toIso8601String(),
        job.processedAt?.toIso8601String(),
      ],
    );
  }

  static Future<void> saveDeliveryJobs(
    List<SalesReportDeliveryJobModel> jobs,
  ) async {
    for (final job in jobs) {
      await saveDeliveryJob(job);
    }
  }

  static Future<List<SalesReportDeliveryJobModel>> loadDeliveryJobs({
    required String tenantId,
    String? branchId,
    bool includeAllBranches = true,
  }) async {
    final rows =
        branchId == null || includeAllBranches
            ? await LocalDatabase.select(
              '''
      SELECT *
      FROM sales_report_delivery_jobs
      WHERE tenant_id = ?
      ORDER BY created_at DESC
      LIMIT 100
      ''',
              [tenantId],
            )
            : await LocalDatabase.select(
              '''
      SELECT *
      FROM sales_report_delivery_jobs
      WHERE tenant_id = ?
        AND branch_id = ?
      ORDER BY created_at DESC
      LIMIT 100
      ''',
              [tenantId, branchId],
            );

    return rows.map(SalesReportDeliveryJobModel.fromMap).toList();
  }

  // ════════════════════════════════════════
  // HELPERS
  // ════════════════════════════════════════

  static String _cacheId({
    required String tenantId,
    required String? branchId,
    required DateTime dateFrom,
    required DateTime dateTo,
  }) {
    return [
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

  static double _double(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? 0;
  }
}
