import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:mobileshop_saas/core/offline/offline_store.dart';
import 'package:mobileshop_saas/features/reports/data/local/business_report_local_store.dart';
import 'package:mobileshop_saas/features/reports/data/models/business_report_models.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

class BusinessReportRepository {
  static const _networkTimeout = Duration(milliseconds: 1200);

  final SupabaseClient _client = Supabase.instance.client;

  User get _currentUser {
    final user = _client.auth.currentUser;
    if (user == null) throw Exception('User not logged in');
    return user;
  }

  // ════════════════════════════════════════
  // CURRENT USER / TENANT / BRANCH
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

  bool _exportAllowedByPlan(String plan) {
    final normalized = plan.toLowerCase();
    return normalized == 'business' || normalized == 'enterprise';
  }

  Future<bool> _canAccessAllBranches() async {
    final profile = await _currentProfile();
    final role = (profile['role'] as String? ?? 'cashier').toLowerCase();

    return role == 'owner';
  }

  Future<void> _ensureAllBranchesAccess() async {
    if (await _canAccessAllBranches()) return;

    throw Exception(
      'All-branch business reports are available only to owners.',
    );
  }

  // ════════════════════════════════════════
  // GENERIC REPORT FETCH
  // ════════════════════════════════════════

  Future<Map<String, dynamic>> fetchRawReport({
    required BusinessReportType reportType,
    required DateTime dateFrom,
    required DateTime dateTo,
    bool allBranches = false,
  }) async {
    if (dateTo.isBefore(dateFrom)) {
      throw Exception('Invalid date range');
    }

    final tenantId = await _tenantId();
    if (allBranches) {
      await _ensureAllBranchesAccess();
    }

    final branchId = allBranches ? null : await _branchId(tenantId);
    final plan = await _tenantPlan(tenantId);

    try {
      final report = await BusinessReportLocalStore.buildLocalReport(
        reportType: reportType,
        tenantId: tenantId,
        branchId: branchId,
        dateFrom: dateFrom,
        dateTo: dateTo,
        plan: plan,
        exportAllowed: _exportAllowedByPlan(plan),
      );

      unawaited(syncOfflineMutations());

      return report;
    } catch (e) {
      debugPrint(
        'Local business report failed, using cache/remote fallback: $e',
      );

      final cached = await BusinessReportLocalStore.loadReportCache(
        reportType: reportType,
        tenantId: tenantId,
        branchId: branchId,
        dateFrom: dateFrom,
        dateTo: dateTo,
      );

      if (cached != null) return cached;

      return _fetchRemoteRawReport(
        reportType: reportType,
        tenantId: tenantId,
        branchId: branchId,
        dateFrom: dateFrom,
        dateTo: dateTo,
      ).timeout(_networkTimeout);
    }
  }

  Future<Map<String, dynamic>> _fetchRemoteRawReport({
    required BusinessReportType reportType,
    required String tenantId,
    required String? branchId,
    required DateTime dateFrom,
    required DateTime dateTo,
  }) async {
    final functionName = _rpcName(reportType);

    final data = await _client
        .rpc(
          functionName,
          params: {
            'p_tenant_id': tenantId,
            'p_branch_id': branchId,
            'p_date_from': _dateOnly(dateFrom),
            'p_date_to': _dateOnly(dateTo),
          },
        )
        .timeout(_networkTimeout);

    final map = Map<String, dynamic>.from(data as Map);

    await BusinessReportLocalStore.saveReportCache(
      reportType: reportType,
      tenantId: tenantId,
      branchId: branchId,
      dateFrom: dateFrom,
      dateTo: dateTo,
      report: map,
    );

    return map;
  }

  Future<ProfitLossReportModel> fetchProfitLossReport({
    required DateTime dateFrom,
    required DateTime dateTo,
    bool allBranches = false,
  }) async {
    final map = await fetchRawReport(
      reportType: BusinessReportType.profitLoss,
      dateFrom: dateFrom,
      dateTo: dateTo,
      allBranches: allBranches,
    );

    return ProfitLossReportModel.fromMap(map);
  }

  Future<InventoryAnalyticsReportModel> fetchInventoryReport({
    required DateTime dateFrom,
    required DateTime dateTo,
    bool allBranches = false,
  }) async {
    final map = await fetchRawReport(
      reportType: BusinessReportType.inventory,
      dateFrom: dateFrom,
      dateTo: dateTo,
      allBranches: allBranches,
    );

    return InventoryAnalyticsReportModel.fromMap(map);
  }

  Future<CustomerCreditReportModel> fetchCustomerCreditReport({
    required DateTime dateFrom,
    required DateTime dateTo,
    bool allBranches = false,
  }) async {
    final map = await fetchRawReport(
      reportType: BusinessReportType.customerCredit,
      dateFrom: dateFrom,
      dateTo: dateTo,
      allBranches: allBranches,
    );

    return CustomerCreditReportModel.fromMap(map);
  }

  Future<RepairAnalyticsReportModel> fetchRepairReport({
    required DateTime dateFrom,
    required DateTime dateTo,
    bool allBranches = false,
  }) async {
    final map = await fetchRawReport(
      reportType: BusinessReportType.repairs,
      dateFrom: dateFrom,
      dateTo: dateTo,
      allBranches: allBranches,
    );

    return RepairAnalyticsReportModel.fromMap(map);
  }

  Future<CashFlowReportModel> fetchCashFlowReport({
    required DateTime dateFrom,
    required DateTime dateTo,
    bool allBranches = false,
  }) async {
    final map = await fetchRawReport(
      reportType: BusinessReportType.cashFlow,
      dateFrom: dateFrom,
      dateTo: dateTo,
      allBranches: allBranches,
    );

    return CashFlowReportModel.fromMap(map);
  }

  Future<BusinessDashboardReportModel> fetchDashboardReport({
    required DateTime dateFrom,
    required DateTime dateTo,
    bool allBranches = false,
  }) async {
    final map = await fetchRawReport(
      reportType: BusinessReportType.dashboard,
      dateFrom: dateFrom,
      dateTo: dateTo,
      allBranches: allBranches,
    );

    return BusinessDashboardReportModel.fromMap(map);
  }

  String _rpcName(BusinessReportType reportType) {
    switch (reportType) {
      case BusinessReportType.sales:
        return 'get_sales_analytics_report';

      case BusinessReportType.profitLoss:
        return 'get_profit_loss_report';

      case BusinessReportType.inventory:
        return 'get_inventory_analytics_report';

      case BusinessReportType.customerCredit:
        return 'get_customer_credit_report';

      case BusinessReportType.repairs:
        return 'get_repair_analytics_report';

      case BusinessReportType.cashFlow:
        return 'get_cash_flow_report';

      case BusinessReportType.dashboard:
        return 'get_business_dashboard_report';
    }
  }

  // ════════════════════════════════════════
  // EXPORT
  // ════════════════════════════════════════

  Future<String> buildCsvExport({
    required BusinessReportType reportType,
    required DateTime dateFrom,
    required DateTime dateTo,
    bool allBranches = false,
  }) async {
    final tenantId = await _tenantId();
    if (allBranches) {
      await _ensureAllBranchesAccess();
    }

    final plan = await _tenantPlan(tenantId);

    if (!_exportAllowedByPlan(plan)) {
      throw Exception(
        'CSV/PDF export is available only on Business and Enterprise plans.',
      );
    }

    final map = await fetchRawReport(
      reportType: reportType,
      dateFrom: dateFrom,
      dateTo: dateTo,
      allBranches: allBranches,
    );

    return _buildGenericCsv(title: reportType.label, map: map);
  }

  String _buildGenericCsv({
    required String title,
    required Map<String, dynamic> map,
  }) {
    final buffer = StringBuffer();

    buffer.writeln(_csv(title));
    buffer.writeln('Generated At,${_csv(DateTime.now().toIso8601String())}');
    buffer.writeln('');

    _writeMapAsCsv(buffer: buffer, title: 'Report Data', value: map);

    return buffer.toString();
  }

  void _writeMapAsCsv({
    required StringBuffer buffer,
    required String title,
    required dynamic value,
  }) {
    buffer.writeln(_csv(title));

    if (value is Map) {
      for (final entry in value.entries) {
        final key = entry.key.toString();
        final item = entry.value;

        if (item is Map || item is List) {
          buffer.writeln('');
          _writeMapAsCsv(buffer: buffer, title: key, value: item);
        } else {
          buffer.writeln('${_csv(key)},${_csv(item?.toString() ?? '')}');
        }
      }

      buffer.writeln('');
      return;
    }

    if (value is List) {
      if (value.isEmpty) {
        buffer.writeln('No data');
        buffer.writeln('');
        return;
      }

      final firstMap = value.first is Map ? value.first as Map : null;

      if (firstMap == null) {
        for (final item in value) {
          buffer.writeln(_csv(item.toString()));
        }

        buffer.writeln('');
        return;
      }

      final headers = firstMap.keys.map((e) => e.toString()).toList();
      buffer.writeln(headers.map(_csv).join(','));

      for (final row in value) {
        if (row is! Map) continue;

        final line = headers
            .map((header) {
              final cell = row[header];

              if (cell is Map || cell is List) {
                return _csv(jsonEncode(cell));
              }

              return _csv(cell?.toString() ?? '');
            })
            .join(',');

        buffer.writeln(line);
      }

      buffer.writeln('');
      return;
    }

    buffer.writeln(_csv(value?.toString() ?? ''));
    buffer.writeln('');
  }

  String _csv(String value) {
    final escaped = value.replaceAll('"', '""');
    return '"$escaped"';
  }

  // ════════════════════════════════════════
  // GENERIC SCHEDULED BUSINESS REPORTS
  // ════════════════════════════════════════

  Future<BusinessReportScheduleModel> createSchedule({
    required String name,
    required BusinessReportType reportType,
    required String cadence,
    required String reportScope,
    required String exportFormat,
    required String sendToEmail,
    required DateTime nextRunAt,
  }) async {
    final tenantId = await _tenantId();
    final branchId = await _branchId(tenantId);
    final plan = await _tenantPlan(tenantId);

    if (reportScope == 'all_branches') {
      await _ensureAllBranchesAccess();
    }

    if (!_exportAllowedByPlan(plan)) {
      throw Exception(
        'Scheduled reports are available only on Business and Enterprise plans.',
      );
    }

    if (!_isValidEmail(sendToEmail)) {
      throw Exception('Enter a valid email address.');
    }

    if (!['daily', 'weekly', 'monthly'].contains(cadence)) {
      throw Exception('Invalid cadence.');
    }

    if (!['branch', 'all_branches'].contains(reportScope)) {
      throw Exception('Invalid report scope.');
    }

    if (!['csv', 'pdf'].contains(exportFormat)) {
      throw Exception('Invalid export format.');
    }

    final now = DateTime.now();

    final schedule = BusinessReportScheduleModel(
      id: const Uuid().v4(),
      tenantId: tenantId,
      branchId: reportScope == 'branch' ? branchId : null,
      name: name.trim(),
      reportType: reportType,
      cadence: cadence,
      reportScope: reportScope,
      exportFormat: exportFormat,
      sendToEmail: sendToEmail.trim(),
      nextRunAt: nextRunAt,
      status: 'active',
      createdBy: _currentUser.id,
      createdAt: now,
      updatedAt: now,
    );

    await BusinessReportLocalStore.saveSchedule(schedule);

    try {
      final id = await _client
          .rpc(
            'create_business_report_schedule',
            params: {
              'p_schedule_id': schedule.id,
              'p_tenant_id': schedule.tenantId,
              'p_branch_id': schedule.branchId,
              'p_name': schedule.name,
              'p_report_type': schedule.reportType.code,
              'p_cadence': schedule.cadence,
              'p_report_scope': schedule.reportScope,
              'p_export_format': schedule.exportFormat,
              'p_send_to_email': schedule.sendToEmail,
              'p_next_run_at': schedule.nextRunAt.toIso8601String(),
            },
          )
          .timeout(_networkTimeout);

      final saved = await fetchScheduleById(id.toString());

      return saved ?? schedule;
    } catch (e) {
      await OfflineStore.enqueueMutation(
        userId: _currentUser.id,
        type: 'create_business_report_schedule',
        payload: schedule.toMap(),
      );

      debugPrint('Business report schedule saved offline: $e');
      return schedule;
    }
  }

  Future<List<BusinessReportScheduleModel>> fetchSchedules() async {
    final tenantId = await _tenantId();
    final branchId = await _branchId(tenantId);
    final includeAllBranches = await _canAccessAllBranches();

    final cached = await BusinessReportLocalStore.loadSchedules(
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
    } catch (e) {
      debugPrint('Fetch business report schedules failed: $e');
      return BusinessReportLocalStore.loadSchedules(
        tenantId: tenantId,
        branchId: branchId,
        includeAllBranches: includeAllBranches,
      );
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

  Future<List<BusinessReportScheduleModel>> _fetchRemoteSchedules({
    required String tenantId,
    required String branchId,
    required bool includeAllBranches,
  }) async {
    final data =
        includeAllBranches
            ? await _client
                .from('business_report_schedules')
                .select()
                .eq('tenant_id', tenantId)
                .or('branch_id.eq.$branchId,branch_id.is.null')
                .order('next_run_at', ascending: true)
            : await _client
                .from('business_report_schedules')
                .select()
                .eq('tenant_id', tenantId)
                .eq('branch_id', branchId)
                .order('next_run_at', ascending: true);

    final schedules =
        (data as List)
            .map(
              (row) => BusinessReportScheduleModel.fromMap(
                Map<String, dynamic>.from(row as Map),
              ),
            )
            .toList();

    await BusinessReportLocalStore.saveSchedules(schedules);

    return schedules;
  }

  Future<BusinessReportScheduleModel?> fetchScheduleById(
    String scheduleId,
  ) async {
    final tenantId = await _tenantId();
    final branchId = await _branchId(tenantId);
    final includeAllBranches = await _canAccessAllBranches();

    try {
      final data =
          includeAllBranches
              ? await _client
                  .from('business_report_schedules')
                  .select()
                  .eq('id', scheduleId)
                  .eq('tenant_id', tenantId)
                  .or('branch_id.eq.$branchId,branch_id.is.null')
                  .maybeSingle()
                  .timeout(_networkTimeout)
              : await _client
                  .from('business_report_schedules')
                  .select()
                  .eq('id', scheduleId)
                  .eq('tenant_id', tenantId)
                  .eq('branch_id', branchId)
                  .maybeSingle()
                  .timeout(_networkTimeout);

      if (data == null) return null;

      final schedule = BusinessReportScheduleModel.fromMap(
        Map<String, dynamic>.from(data),
      );
      await BusinessReportLocalStore.saveSchedule(schedule);

      return schedule;
    } catch (_) {
      final schedules = await BusinessReportLocalStore.loadSchedules(
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

  Future<void> updateScheduleStatus({
    required BusinessReportScheduleModel schedule,
    required String status,
  }) async {
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

    await BusinessReportLocalStore.updateScheduleStatus(
      scheduleId: schedule.id,
      tenantId: tenantId,
      branchId: branchId,
      includeAllBranches: includeAllBranches,
      status: status,
    );

    try {
      final update = _client
          .from('business_report_schedules')
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
      await OfflineStore.enqueueMutation(
        userId: _currentUser.id,
        type: 'update_business_report_schedule_status',
        payload: {
          'schedule_id': schedule.id,
          'tenant_id': tenantId,
          'branch_id': schedule.branchId,
          'status': status,
        },
      );

      debugPrint('Business schedule status saved offline: $e');
    }
  }

  Future<List<BusinessReportDeliveryJobModel>> fetchDeliveryJobs() async {
    final tenantId = await _tenantId();
    final branchId = await _branchId(tenantId);
    final includeAllBranches = await _canAccessAllBranches();

    final cached = await BusinessReportLocalStore.loadDeliveryJobs(
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
    } catch (e) {
      debugPrint('Fetch business delivery jobs failed: $e');
      return BusinessReportLocalStore.loadDeliveryJobs(
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

  Future<List<BusinessReportDeliveryJobModel>> _fetchRemoteDeliveryJobs({
    required String tenantId,
    required String branchId,
    required bool includeAllBranches,
  }) async {
    final data =
        includeAllBranches
            ? await _client
                .from('business_report_delivery_jobs')
                .select()
                .eq('tenant_id', tenantId)
                .order('created_at', ascending: false)
                .limit(100)
            : await _client
                .from('business_report_delivery_jobs')
                .select()
                .eq('tenant_id', tenantId)
                .eq('branch_id', branchId)
                .order('created_at', ascending: false)
                .limit(100);

    final jobs =
        (data as List)
            .map(
              (row) => BusinessReportDeliveryJobModel.fromMap(
                Map<String, dynamic>.from(row as Map),
              ),
            )
            .toList();

    await BusinessReportLocalStore.saveDeliveryJobs(jobs);

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
          case 'create_business_report_schedule':
            await _syncCreateSchedule(mutation.payload);
            break;

          case 'update_business_report_schedule_status':
            await _syncScheduleStatus(mutation.payload);
            break;

          default:
            remaining.add(mutation);
        }
      } catch (e) {
        debugPrint('Business report mutation sync failed: $e');
        remaining.add(mutation);
      }
    }

    await OfflineStore.saveMutations(userId, remaining);
  }

  Future<void> _syncCreateSchedule(Map<String, dynamic> payload) async {
    final schedule = BusinessReportScheduleModel.fromMap(payload);

    await _client.rpc(
      'create_business_report_schedule',
      params: {
        'p_schedule_id': schedule.id,
        'p_tenant_id': schedule.tenantId,
        'p_branch_id': schedule.branchId,
        'p_name': schedule.name,
        'p_report_type': schedule.reportType.code,
        'p_cadence': schedule.cadence,
        'p_report_scope': schedule.reportScope,
        'p_export_format': schedule.exportFormat,
        'p_send_to_email': schedule.sendToEmail,
        'p_next_run_at': schedule.nextRunAt.toIso8601String(),
      },
    );

    final saved = await fetchScheduleById(schedule.id);
    if (saved != null) {
      await BusinessReportLocalStore.saveSchedule(saved);
    }
  }

  Future<void> _syncScheduleStatus(Map<String, dynamic> payload) async {
    final tenantId = payload['tenant_id'] as String? ?? await _tenantId();
    final branchId = payload['branch_id'] as String?;

    final update = _client
        .from('business_report_schedules')
        .update({
          'status': payload['status'],
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', payload['schedule_id'])
        .eq('tenant_id', tenantId);

    if (branchId != null) {
      await update.eq('branch_id', branchId);
      return;
    }

    await _ensureAllBranchesAccess();
    await update;
  }

  // ════════════════════════════════════════
  // HELPERS
  // ════════════════════════════════════════

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
