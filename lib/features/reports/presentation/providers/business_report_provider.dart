import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:mobileshop_saas/core/authorization/permission_provider.dart';
import 'package:mobileshop_saas/core/entitlements/entitlement_provider.dart';
import 'package:mobileshop_saas/features/reports/data/models/business_report_models.dart';
import 'package:mobileshop_saas/features/reports/data/repositories/business_report_repository.dart';

class BusinessReportDateRange {
  final DateTime from;
  final DateTime to;

  const BusinessReportDateRange({required this.from, required this.to});

  BusinessReportDateRange copyWith({DateTime? from, DateTime? to}) {
    return BusinessReportDateRange(from: from ?? this.from, to: to ?? this.to);
  }
}

// ════════════════════════════════════════
// REPOSITORY
// ════════════════════════════════════════

final businessReportRepositoryProvider = Provider<BusinessReportRepository>((
  ref,
) {
  return BusinessReportRepository(
    permissions: ref.watch(permissionEvaluatorProvider),
    entitlements: ref.watch(entitlementEvaluatorProvider),
  );
});

// ════════════════════════════════════════
// FILTERS
// ════════════════════════════════════════

final businessReportDateRangeProvider = StateProvider<BusinessReportDateRange>((
  ref,
) {
  final now = DateTime.now();

  return BusinessReportDateRange(
    from: DateTime(now.year, now.month, 1),
    to: DateTime(now.year, now.month, now.day),
  );
});

final businessReportAllBranchesProvider = StateProvider<bool>((ref) {
  return false;
});

final selectedBusinessReportTypeProvider = StateProvider<BusinessReportType>((
  ref,
) {
  return BusinessReportType.dashboard;
});

// ════════════════════════════════════════
// READ PROVIDERS
// ════════════════════════════════════════

final businessDashboardReportProvider =
    FutureProvider.autoDispose<BusinessDashboardReportModel>((ref) async {
      final repository = ref.read(businessReportRepositoryProvider);
      final range = ref.watch(businessReportDateRangeProvider);
      final allBranches = ref.watch(businessReportAllBranchesProvider);

      return repository.fetchDashboardReport(
        dateFrom: range.from,
        dateTo: range.to,
        allBranches: allBranches,
      );
    });

final profitLossReportProvider =
    FutureProvider.autoDispose<ProfitLossReportModel>((ref) async {
      final repository = ref.read(businessReportRepositoryProvider);
      final range = ref.watch(businessReportDateRangeProvider);
      final allBranches = ref.watch(businessReportAllBranchesProvider);

      return repository.fetchProfitLossReport(
        dateFrom: range.from,
        dateTo: range.to,
        allBranches: allBranches,
      );
    });

final inventoryAnalyticsReportProvider =
    FutureProvider.autoDispose<InventoryAnalyticsReportModel>((ref) async {
      final repository = ref.read(businessReportRepositoryProvider);
      final range = ref.watch(businessReportDateRangeProvider);
      final allBranches = ref.watch(businessReportAllBranchesProvider);

      return repository.fetchInventoryReport(
        dateFrom: range.from,
        dateTo: range.to,
        allBranches: allBranches,
      );
    });

final customerCreditReportProvider =
    FutureProvider.autoDispose<CustomerCreditReportModel>((ref) async {
      final repository = ref.read(businessReportRepositoryProvider);
      final range = ref.watch(businessReportDateRangeProvider);
      final allBranches = ref.watch(businessReportAllBranchesProvider);

      return repository.fetchCustomerCreditReport(
        dateFrom: range.from,
        dateTo: range.to,
        allBranches: allBranches,
      );
    });

final repairAnalyticsReportProvider =
    FutureProvider.autoDispose<RepairAnalyticsReportModel>((ref) async {
      final repository = ref.read(businessReportRepositoryProvider);
      final range = ref.watch(businessReportDateRangeProvider);
      final allBranches = ref.watch(businessReportAllBranchesProvider);

      return repository.fetchRepairReport(
        dateFrom: range.from,
        dateTo: range.to,
        allBranches: allBranches,
      );
    });

final cashFlowReportProvider = FutureProvider.autoDispose<CashFlowReportModel>((
  ref,
) async {
  final repository = ref.read(businessReportRepositoryProvider);
  final range = ref.watch(businessReportDateRangeProvider);
  final allBranches = ref.watch(businessReportAllBranchesProvider);

  return repository.fetchCashFlowReport(
    dateFrom: range.from,
    dateTo: range.to,
    allBranches: allBranches,
  );
});

final businessReportSchedulesProvider =
    FutureProvider.autoDispose<List<BusinessReportScheduleModel>>((ref) async {
      final repository = ref.read(businessReportRepositoryProvider);

      return repository.fetchSchedules();
    });

final businessReportDeliveryJobsProvider =
    FutureProvider.autoDispose<List<BusinessReportDeliveryJobModel>>((
      ref,
    ) async {
      final repository = ref.read(businessReportRepositoryProvider);

      return repository.fetchDeliveryJobs();
    });

// ════════════════════════════════════════
// REFRESH HELPER
// ════════════════════════════════════════

void invalidateBusinessReports(Ref ref) {
  ref.invalidate(businessDashboardReportProvider);
  ref.invalidate(profitLossReportProvider);
  ref.invalidate(inventoryAnalyticsReportProvider);
  ref.invalidate(customerCreditReportProvider);
  ref.invalidate(repairAnalyticsReportProvider);
  ref.invalidate(cashFlowReportProvider);
}

// ════════════════════════════════════════
// EXPORT CONTROLLER
// ════════════════════════════════════════

final businessReportExportControllerProvider =
    StateNotifierProvider<BusinessReportExportController, AsyncValue<String?>>((
      ref,
    ) {
      return BusinessReportExportController(ref);
    });

class BusinessReportExportController
    extends StateNotifier<AsyncValue<String?>> {
  final Ref _ref;

  BusinessReportExportController(this._ref) : super(const AsyncData(null));

  Future<String?> buildCsv({required BusinessReportType reportType}) async {
    state = const AsyncLoading();

    try {
      final repository = _ref.read(businessReportRepositoryProvider);
      final range = _ref.read(businessReportDateRangeProvider);
      final allBranches = _ref.read(businessReportAllBranchesProvider);

      final csv = await repository.buildCsvExport(
        reportType: reportType,
        dateFrom: range.from,
        dateTo: range.to,
        allBranches: allBranches,
      );

      state = AsyncData(csv);

      return csv;
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
// SCHEDULE CONTROLLER
// ════════════════════════════════════════

final businessReportScheduleControllerProvider = StateNotifierProvider<
  BusinessReportScheduleController,
  AsyncValue<BusinessReportScheduleModel?>
>((ref) {
  return BusinessReportScheduleController(ref);
});

class BusinessReportScheduleController
    extends StateNotifier<AsyncValue<BusinessReportScheduleModel?>> {
  final Ref _ref;

  BusinessReportScheduleController(this._ref) : super(const AsyncData(null));

  Future<BusinessReportScheduleModel?> createSchedule({
    required String name,
    required BusinessReportType reportType,
    required String cadence,
    required String reportScope,
    required String exportFormat,
    required String sendToEmail,
    required DateTime nextRunAt,
  }) async {
    state = const AsyncLoading();

    try {
      final repository = _ref.read(businessReportRepositoryProvider);

      final schedule = await repository.createSchedule(
        name: name,
        reportType: reportType,
        cadence: cadence,
        reportScope: reportScope,
        exportFormat: exportFormat,
        sendToEmail: sendToEmail,
        nextRunAt: nextRunAt,
      );

      state = AsyncData(schedule);

      _ref.invalidate(businessReportSchedulesProvider);
      _ref.invalidate(businessReportDeliveryJobsProvider);

      return schedule;
    } catch (e, st) {
      state = AsyncError(e, st);
      return null;
    }
  }

  Future<bool> updateStatus({
    required BusinessReportScheduleModel schedule,
    required String status,
  }) async {
    state = const AsyncLoading();

    try {
      final repository = _ref.read(businessReportRepositoryProvider);

      await repository.updateScheduleStatus(schedule: schedule, status: status);

      state = AsyncData(schedule);

      _ref.invalidate(businessReportSchedulesProvider);

      return true;
    } catch (e, st) {
      state = AsyncError(e, st);
      return false;
    }
  }

  void reset() {
    state = const AsyncData(null);
  }
}

// ════════════════════════════════════════
// SYNC CONTROLLER
// ════════════════════════════════════════

final businessReportSyncControllerProvider =
    StateNotifierProvider<BusinessReportSyncController, AsyncValue<void>>((
      ref,
    ) {
      return BusinessReportSyncController(ref);
    });

class BusinessReportSyncController extends StateNotifier<AsyncValue<void>> {
  final Ref _ref;

  BusinessReportSyncController(this._ref) : super(const AsyncData(null));

  Future<void> sync() async {
    state = const AsyncLoading();

    try {
      final repository = _ref.read(businessReportRepositoryProvider);

      await repository.syncOfflineMutations();

      state = const AsyncData(null);

      invalidateBusinessReports(_ref);
      _ref.invalidate(businessReportSchedulesProvider);
      _ref.invalidate(businessReportDeliveryJobsProvider);
    } catch (e, st) {
      state = AsyncError(e, st);
    }
  }
}
