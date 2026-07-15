import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:mobileshop_saas/core/authorization/permission_evaluator.dart';
import 'package:mobileshop_saas/core/entitlements/entitlement_evaluator.dart';
import 'package:mobileshop_saas/core/offline/offline_store.dart';
import 'package:mobileshop_saas/core/utils/offline_error_classifier.dart';
import 'package:mobileshop_saas/features/reports/data/local/sales_report_local_store.dart';
import 'package:mobileshop_saas/features/reports/data/models/sales_report_models.dart';
import 'package:mobileshop_saas/features/reports/domain/report_entitlement_gate.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

class SalesReportRepository {
  static const _networkTimeout = Duration(milliseconds: 1200);

  final SupabaseClient _client;
  final PermissionEvaluator _permissions;
  final EntitlementEvaluator _entitlements;
  late final ReportEntitlementGate _gate = ReportEntitlementGate(_entitlements);

  SalesReportRepository({
    SupabaseClient? client,
    required PermissionEvaluator permissions,
    required EntitlementEvaluator entitlements,
  }) : _client = client ?? Supabase.instance.client,
       _permissions = permissions,
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
      final selectedBranchId = await OfflineStore.loadSelectedBranchId(
        _currentUser.id,
      );

      if (selectedBranchId != null) {
        cached['branch_id'] = selectedBranchId;
      }

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
      final data = await _client
          .from('tenants')
          .select('plan')
          .eq('id', tenantId)
          .maybeSingle()
          .timeout(_networkTimeout);

      return (data?['plan'] as String?)?.toLowerCase() ?? 'starter';
    } catch (_) {
      final cachedTenant = await OfflineStore.loadTenant(tenantId);
      return (cachedTenant?['plan'] as String?)?.toLowerCase() ?? 'starter';
    }
  }

  Future<bool> _canAccessAllBranches() async {
    return (await _permissions.can('report.all_branches.view')).isAllowed;
  }

  Future<void> _ensureAllBranchesAccess() async {
    if (await _canAccessAllBranches()) return;

    throw Exception('All-branch sales reports are available only to owners.');
  }

  // ════════════════════════════════════════
  // SALES ANALYTICS REPORT
  // ════════════════════════════════════════

  Future<SalesAnalyticsReportModel> fetchSalesReport({
    required DateTime dateFrom,
    required DateTime dateTo,
    bool allBranches = false,
  }) async {
    await _gate.require('reports.sales');
    if (dateTo.isBefore(dateFrom)) {
      throw Exception('Invalid date range');
    }

    final tenantId = await _tenantId();
    if (allBranches) {
      await _ensureAllBranchesAccess();
    }

    final branchId = allBranches ? null : await _branchId(tenantId);
    final plan = await _tenantPlan(tenantId);
    final exportAllowed = await _entitlements.hasFeature('reports.export');

    try {
      final report = await SalesReportLocalStore.buildLocalReport(
        tenantId: tenantId,
        branchId: branchId,
        dateFrom: dateFrom,
        dateTo: dateTo,
        plan: plan,
        exportAllowed: exportAllowed,
      );

      unawaited(syncOfflineMutations());

      return report;
    } catch (e) {
      debugPrint('Local sales report failed, using cache/remote fallback: $e');

      final cached = await SalesReportLocalStore.loadReportCache(
        tenantId: tenantId,
        branchId: branchId,
        dateFrom: dateFrom,
        dateTo: dateTo,
      );

      if (cached != null) return cached;

      return _fetchRemoteSalesReport(
        tenantId: tenantId,
        branchId: branchId,
        dateFrom: dateFrom,
        dateTo: dateTo,
      ).timeout(_networkTimeout);
    }
  }

  Future<SalesAnalyticsReportModel> _fetchRemoteSalesReport({
    required String tenantId,
    required String? branchId,
    required DateTime dateFrom,
    required DateTime dateTo,
  }) async {
    final data = await _client.rpc(
      'get_sales_analytics_report',
      params: {
        'p_tenant_id': tenantId,
        'p_branch_id': branchId,
        'p_date_from': _dateOnly(dateFrom),
        'p_date_to': _dateOnly(dateTo),
      },
    );

    final report = SalesAnalyticsReportModel.fromMap(
      Map<String, dynamic>.from(data as Map),
    );

    await SalesReportLocalStore.saveReportCache(report);

    return report;
  }

  // ════════════════════════════════════════
  // EXPORT
  // ════════════════════════════════════════

  Future<String> buildCsvExport({
    required DateTime dateFrom,
    required DateTime dateTo,
    bool allBranches = false,
  }) async {
    await _gate.require('reports.sales');
    await _gate.require('reports.export');
    if (allBranches) {
      await _ensureAllBranchesAccess();
    }

    final report = await fetchSalesReport(
      dateFrom: dateFrom,
      dateTo: dateTo,
      allBranches: allBranches,
    );

    return _buildCsvFromReport(report);
  }

  String _buildCsvFromReport(SalesAnalyticsReportModel report) {
    final buffer = StringBuffer();

    buffer.writeln('Sales Analytics Report');
    buffer.writeln('Date From,${_dateOnly(report.dateFrom)}');
    buffer.writeln('Date To,${_dateOnly(report.dateTo)}');
    buffer.writeln('Plan,${_csv(report.plan)}');
    buffer.writeln('');

    buffer.writeln('Summary');
    buffer.writeln('Metric,Value');
    buffer.writeln('Total Orders,${report.summary.totalOrders}');
    buffer.writeln('Total Units,${report.summary.totalUnits}');
    buffer.writeln('Revenue,${report.summary.revenue.toStringAsFixed(2)}');
    buffer.writeln('Discount,${report.summary.discount.toStringAsFixed(2)}');
    buffer.writeln('Tax,${report.summary.tax.toStringAsFixed(2)}');
    buffer.writeln('COGS,${report.summary.cogs.toStringAsFixed(2)}');
    buffer.writeln(
      'Gross Profit,${report.summary.grossProfit.toStringAsFixed(2)}',
    );
    buffer.writeln(
      'Gross Margin %,${report.summary.grossMarginPercent.toStringAsFixed(2)}',
    );
    buffer.writeln('Returned Units,${report.summary.returnedUnits}');
    buffer.writeln(
      'Returns,${report.summary.returnsAmount.toStringAsFixed(2)}',
    );
    buffer.writeln('Net Sales,${report.summary.netRevenue.toStringAsFixed(2)}');
    buffer.writeln('');

    buffer.writeln('Product Breakdown');
    buffer.writeln(
      'Product Name,SKU,Quantity,Revenue,COGS,Gross Profit,Margin %',
    );

    for (final item in report.productBreakdown) {
      buffer.writeln(
        [
          _csv(item.productName),
          _csv(item.sku ?? ''),
          item.quantity,
          item.revenue.toStringAsFixed(2),
          item.cogs.toStringAsFixed(2),
          item.grossProfit.toStringAsFixed(2),
          item.marginPercent.toStringAsFixed(2),
        ].join(','),
      );
    }

    buffer.writeln('');
    buffer.writeln('Customer Breakdown');
    buffer.writeln('Customer Name,Orders,Revenue,Gross Profit');

    for (final item in report.customerBreakdown) {
      buffer.writeln(
        [
          _csv(item.customerName),
          item.orders,
          item.revenue.toStringAsFixed(2),
          item.grossProfit.toStringAsFixed(2),
        ].join(','),
      );
    }

    buffer.writeln('');
    buffer.writeln('Branch Breakdown');
    buffer.writeln('Branch Name,Orders,Revenue,COGS,Gross Profit,Margin %');

    for (final item in report.branchBreakdown) {
      buffer.writeln(
        [
          _csv(item.branchName),
          item.orders,
          item.revenue.toStringAsFixed(2),
          item.cogs.toStringAsFixed(2),
          item.grossProfit.toStringAsFixed(2),
          item.marginPercent.toStringAsFixed(2),
        ].join(','),
      );
    }

    buffer.writeln('');
    buffer.writeln('Category Breakdown');
    buffer.writeln('Category Name,Quantity,Revenue,COGS,Gross Profit,Margin %');

    for (final item in report.categoryBreakdown) {
      buffer.writeln(
        [
          _csv(item.categoryName),
          item.quantity,
          item.revenue.toStringAsFixed(2),
          item.cogs.toStringAsFixed(2),
          item.grossProfit.toStringAsFixed(2),
          item.marginPercent.toStringAsFixed(2),
        ].join(','),
      );
    }

    buffer.writeln('');
    buffer.writeln('Daily Breakdown');
    buffer.writeln('Date,Orders,Revenue,COGS,Gross Profit');

    for (final item in report.dailyBreakdown) {
      buffer.writeln(
        [
          _dateOnly(item.date),
          item.orders,
          item.revenue.toStringAsFixed(2),
          item.cogs.toStringAsFixed(2),
          item.grossProfit.toStringAsFixed(2),
        ].join(','),
      );
    }

    return buffer.toString();
  }

  String _csv(String value) {
    final escaped = value.replaceAll('"', '""');
    return '"$escaped"';
  }

  // ════════════════════════════════════════
  // SCHEDULED REPORTS
  // ════════════════════════════════════════

  Future<SalesReportScheduleModel> createSchedule({
    required String name,
    required SalesReportCadence cadence,
    required SalesReportScope reportScope,
    required SalesReportExportFormat exportFormat,
    required String sendToEmail,
    DateTime? nextRunAt,
  }) async {
    await _gate.require('reports.sales');
    await _gate.require('reports.scheduled');
    final tenantId = await _tenantId();
    final currentBranchId = await _branchId(tenantId);
    if (reportScope == SalesReportScope.allBranches) {
      await _ensureAllBranchesAccess();
    }

    if (!_isValidEmail(sendToEmail)) {
      throw Exception('Enter a valid email address.');
    }

    final now = DateTime.now();

    final schedule = SalesReportScheduleModel(
      id: const Uuid().v4(),
      tenantId: tenantId,
      branchId: reportScope == SalesReportScope.branch ? currentBranchId : null,
      name: name.trim(),
      cadence: cadence,
      reportScope: reportScope,
      exportFormat: exportFormat,
      sendToEmail: sendToEmail.trim(),
      nextRunAt: nextRunAt ?? _defaultNextRun(cadence),
      status: 'active',
      createdBy: _currentUser.id,
      createdAt: now,
      updatedAt: now,
    );

    await SalesReportLocalStore.saveSchedule(schedule);

    try {
      final id = await _client
          .rpc(
            'create_sales_report_schedule',
            params: {
              'p_schedule_id': schedule.id,
              'p_tenant_id': tenantId,
              'p_branch_id': schedule.branchId,
              'p_name': schedule.name,
              'p_cadence': schedule.cadence.code,
              'p_report_scope': schedule.reportScope.code,
              'p_export_format': schedule.exportFormat.code,
              'p_send_to_email': schedule.sendToEmail,
              'p_next_run_at': schedule.nextRunAt.toIso8601String(),
            },
          )
          .timeout(_networkTimeout);

      final saved = await fetchScheduleById(id.toString());
      return saved ?? schedule;
    } catch (e) {
      OfflineErrorClassifier.rethrowIfTerminal(e);
      await OfflineStore.enqueueMutation(
        userId: _currentUser.id,
        type: 'create_sales_report_schedule',
        payload: schedule.toMap(),
      );

      debugPrint('Sales report schedule saved offline: $e');
      return schedule;
    }
  }

  Future<List<SalesReportScheduleModel>> fetchSchedules() async {
    await _gate.require('reports.sales');
    await _gate.require('reports.scheduled');
    final tenantId = await _tenantId();
    final branchId = await _branchId(tenantId);
    final includeAllBranches = await _canAccessAllBranches();

    final cached = await SalesReportLocalStore.loadSchedules(
      tenantId: tenantId,
      branchId: branchId,
      includeAllBranches: includeAllBranches,
    );

    if (cached.isNotEmpty) {
      unawaited(
        _refreshSchedules(
          tenantId: tenantId,
          branchId: branchId,
          includeAllBranches: includeAllBranches,
        ),
      );
      unawaited(syncOfflineMutations());
      return cached;
    }

    try {
      return await _fetchRemoteSchedules(
        tenantId: tenantId,
        branchId: branchId,
        includeAllBranches: includeAllBranches,
      ).timeout(_networkTimeout);
    } catch (_) {
      return SalesReportLocalStore.loadSchedules(
        tenantId: tenantId,
        branchId: branchId,
        includeAllBranches: includeAllBranches,
      );
    }
  }

  Future<SalesReportScheduleModel?> fetchScheduleById(String scheduleId) async {
    await _gate.require('reports.sales');
    await _gate.require('reports.scheduled');
    final tenantId = await _tenantId();
    final branchId = await _branchId(tenantId);
    final includeAllBranches = await _canAccessAllBranches();

    try {
      final data =
          includeAllBranches
              ? await _client
                  .from('sales_report_schedules')
                  .select()
                  .eq('id', scheduleId)
                  .eq('tenant_id', tenantId)
                  .or('branch_id.eq.$branchId,branch_id.is.null')
                  .maybeSingle()
                  .timeout(_networkTimeout)
              : await _client
                  .from('sales_report_schedules')
                  .select()
                  .eq('id', scheduleId)
                  .eq('tenant_id', tenantId)
                  .eq('branch_id', branchId)
                  .maybeSingle()
                  .timeout(_networkTimeout);

      if (data == null) return null;

      final schedule = SalesReportScheduleModel.fromMap(data);
      await SalesReportLocalStore.saveSchedule(schedule);

      return schedule;
    } catch (_) {
      final schedules = await SalesReportLocalStore.loadSchedules(
        tenantId: tenantId,
        branchId: branchId,
        includeAllBranches: includeAllBranches,
      );

      for (final schedule in schedules) {
        if (schedule.id == scheduleId) return schedule;
      }

      return null;
    }
  }

  Future<void> _refreshSchedules({
    required String tenantId,
    required String branchId,
    required bool includeAllBranches,
  }) async {
    try {
      await _fetchRemoteSchedules(
        tenantId: tenantId,
        branchId: branchId,
        includeAllBranches: includeAllBranches,
      ).timeout(_networkTimeout);
    } catch (_) {}
  }

  Future<List<SalesReportScheduleModel>> _fetchRemoteSchedules({
    required String tenantId,
    required String branchId,
    required bool includeAllBranches,
  }) async {
    final data =
        includeAllBranches
            ? await _client
                .from('sales_report_schedules')
                .select()
                .eq('tenant_id', tenantId)
                .or('branch_id.eq.$branchId,branch_id.is.null')
                .order('next_run_at', ascending: true)
            : await _client
                .from('sales_report_schedules')
                .select()
                .eq('tenant_id', tenantId)
                .eq('branch_id', branchId)
                .order('next_run_at', ascending: true);

    final schedules =
        (data as List)
            .map((row) => SalesReportScheduleModel.fromMap(row))
            .toList();

    await SalesReportLocalStore.saveSchedules(schedules);

    return schedules;
  }

  Future<void> updateScheduleStatus({
    required SalesReportScheduleModel schedule,
    required String status,
  }) async {
    await _gate.require('reports.sales');
    await _gate.require('reports.scheduled');
    if (!['active', 'paused', 'cancelled'].contains(status)) {
      throw Exception('Invalid schedule status.');
    }

    final tenantId = await _tenantId();
    final branchId = await _branchId(tenantId);
    final includeAllBranches = await _canAccessAllBranches();

    if (schedule.tenantId != tenantId ||
        (schedule.branchId == null && !includeAllBranches) ||
        (schedule.branchId != null && schedule.branchId != branchId)) {
      throw Exception('Schedule not available for this user or branch.');
    }

    await SalesReportLocalStore.updateScheduleStatus(
      scheduleId: schedule.id,
      tenantId: tenantId,
      branchId: branchId,
      includeAllBranches: includeAllBranches,
      status: status,
    );

    try {
      final update = _client
          .from('sales_report_schedules')
          .update({
            'status': status,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', schedule.id)
          .eq('tenant_id', tenantId);

      if (includeAllBranches) {
        await update
            .or('branch_id.eq.$branchId,branch_id.is.null')
            .timeout(_networkTimeout);
      } else {
        await update.eq('branch_id', branchId).timeout(_networkTimeout);
      }
    } catch (e) {
      OfflineErrorClassifier.rethrowIfTerminal(e);
      await OfflineStore.enqueueMutation(
        userId: _currentUser.id,
        type: 'update_sales_report_schedule_status',
        payload: {
          'schedule_id': schedule.id,
          'tenant_id': tenantId,
          'status': status,
        },
      );

      debugPrint('Schedule status saved offline: $e');
    }
  }

  Future<List<SalesReportDeliveryJobModel>> fetchDeliveryJobs() async {
    await _gate.require('reports.sales');
    await _gate.require('reports.scheduled');
    final tenantId = await _tenantId();
    final branchId = await _branchId(tenantId);
    final includeAllBranches = await _canAccessAllBranches();

    final cached = await SalesReportLocalStore.loadDeliveryJobs(
      tenantId: tenantId,
      branchId: branchId,
      includeAllBranches: includeAllBranches,
    );

    if (cached.isNotEmpty) {
      unawaited(
        _refreshDeliveryJobs(
          tenantId: tenantId,
          branchId: branchId,
          includeAllBranches: includeAllBranches,
        ),
      );
      return cached;
    }

    try {
      return await _fetchRemoteDeliveryJobs(
        tenantId: tenantId,
        branchId: branchId,
        includeAllBranches: includeAllBranches,
      ).timeout(_networkTimeout);
    } catch (_) {
      return SalesReportLocalStore.loadDeliveryJobs(
        tenantId: tenantId,
        branchId: branchId,
        includeAllBranches: includeAllBranches,
      );
    }
  }

  Future<void> _refreshDeliveryJobs({
    required String tenantId,
    required String branchId,
    required bool includeAllBranches,
  }) async {
    try {
      await _fetchRemoteDeliveryJobs(
        tenantId: tenantId,
        branchId: branchId,
        includeAllBranches: includeAllBranches,
      ).timeout(_networkTimeout);
    } catch (_) {}
  }

  Future<List<SalesReportDeliveryJobModel>> _fetchRemoteDeliveryJobs({
    required String tenantId,
    required String branchId,
    required bool includeAllBranches,
  }) async {
    final data =
        includeAllBranches
            ? await _client
                .from('sales_report_delivery_jobs')
                .select()
                .eq('tenant_id', tenantId)
                .order('created_at', ascending: false)
                .limit(100)
            : await _client
                .from('sales_report_delivery_jobs')
                .select()
                .eq('tenant_id', tenantId)
                .eq('branch_id', branchId)
                .order('created_at', ascending: false)
                .limit(100);

    final jobs =
        (data as List)
            .map((row) => SalesReportDeliveryJobModel.fromMap(row))
            .toList();

    await SalesReportLocalStore.saveDeliveryJobs(jobs);

    return jobs;
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
          case 'create_sales_report_schedule':
            await _syncCreateSchedule(mutation.payload);
            break;

          case 'update_sales_report_schedule_status':
            await _syncScheduleStatus(mutation.payload);
            break;

          default:
            remaining.add(mutation);
        }
      } catch (e) {
        debugPrint('Sales report mutation sync failed: $e');
        remaining.add(mutation);
      }
    }

    await OfflineStore.saveMutations(userId, remaining);
  }

  Future<void> _syncCreateSchedule(Map<String, dynamic> payload) async {
    final schedule = SalesReportScheduleModel.fromMap(payload);

    await _client.rpc(
      'create_sales_report_schedule',
      params: {
        'p_schedule_id': schedule.id,
        'p_tenant_id': schedule.tenantId,
        'p_branch_id': schedule.branchId,
        'p_name': schedule.name,
        'p_cadence': schedule.cadence.code,
        'p_report_scope': schedule.reportScope.code,
        'p_export_format': schedule.exportFormat.code,
        'p_send_to_email': schedule.sendToEmail,
        'p_next_run_at': schedule.nextRunAt.toIso8601String(),
      },
    );

    final saved = await fetchScheduleById(schedule.id);
    if (saved != null) {
      await SalesReportLocalStore.saveSchedule(saved);
    }
  }

  Future<void> _syncScheduleStatus(Map<String, dynamic> payload) async {
    final tenantId = payload['tenant_id'] as String? ?? await _tenantId();

    await _client
        .from('sales_report_schedules')
        .update({
          'status': payload['status'],
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', payload['schedule_id'])
        .eq('tenant_id', tenantId);
  }

  // ════════════════════════════════════════
  // HELPERS
  // ════════════════════════════════════════

  DateTime _defaultNextRun(SalesReportCadence cadence) {
    final now = DateTime.now();

    switch (cadence) {
      case SalesReportCadence.daily:
        return DateTime(now.year, now.month, now.day + 1, 8);

      case SalesReportCadence.weekly:
        return now.add(const Duration(days: 7));

      case SalesReportCadence.monthly:
        return DateTime(now.year, now.month + 1, 1, 8);
    }
  }

  bool _isValidEmail(String value) {
    final trimmed = value.trim();

    if (trimmed.isEmpty) return false;

    return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(trimmed);
  }

  String _dateOnly(DateTime date) {
    final year = date.year.toString().padLeft(4, '0');
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }
}
