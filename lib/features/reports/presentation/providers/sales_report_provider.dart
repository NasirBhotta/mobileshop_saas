import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:mobileshop_saas/core/authorization/permission_provider.dart';
import 'package:mobileshop_saas/core/entitlements/entitlement_provider.dart';
import 'package:mobileshop_saas/features/reports/data/models/sales_report_models.dart';
import 'package:mobileshop_saas/features/reports/data/repositories/sales_report_repository.dart';

class SalesReportDateRange {
  final DateTime from;
  final DateTime to;

  const SalesReportDateRange({required this.from, required this.to});

  SalesReportDateRange copyWith({DateTime? from, DateTime? to}) {
    return SalesReportDateRange(from: from ?? this.from, to: to ?? this.to);
  }
}

final salesReportRepositoryProvider = Provider<SalesReportRepository>((ref) {
  return SalesReportRepository(
    permissions: ref.watch(permissionEvaluatorProvider),
    entitlements: ref.watch(entitlementEvaluatorProvider),
  );
});

// ════════════════════════════════════════
// FILTERS
// ════════════════════════════════════════

final salesReportDateRangeProvider = StateProvider<SalesReportDateRange>((ref) {
  final now = DateTime.now();

  return SalesReportDateRange(
    from: DateTime(now.year, now.month, 1),
    to: DateTime(now.year, now.month, now.day),
  );
});

final salesReportAllBranchesProvider = StateProvider<bool>((ref) {
  return false;
});

// ════════════════════════════════════════
// READ PROVIDERS
// ════════════════════════════════════════

final salesAnalyticsReportProvider =
    FutureProvider.autoDispose<SalesAnalyticsReportModel>((ref) async {
      final repository = ref.read(salesReportRepositoryProvider);
      final range = ref.watch(salesReportDateRangeProvider);
      final allBranches = ref.watch(salesReportAllBranchesProvider);

      return repository.fetchSalesReport(
        dateFrom: range.from,
        dateTo: range.to,
        allBranches: allBranches,
      );
    });

final salesReportSchedulesProvider =
    FutureProvider.autoDispose<List<SalesReportScheduleModel>>((ref) async {
      final repository = ref.read(salesReportRepositoryProvider);

      return repository.fetchSchedules();
    });

final salesReportDeliveryJobsProvider =
    FutureProvider.autoDispose<List<SalesReportDeliveryJobModel>>((ref) async {
      final repository = ref.read(salesReportRepositoryProvider);

      return repository.fetchDeliveryJobs();
    });

// ════════════════════════════════════════
// SCHEDULE CONTROLLER
// ════════════════════════════════════════

final salesReportScheduleControllerProvider = StateNotifierProvider<
  SalesReportScheduleController,
  AsyncValue<SalesReportScheduleModel?>
>((ref) {
  return SalesReportScheduleController(ref);
});

class SalesReportScheduleController
    extends StateNotifier<AsyncValue<SalesReportScheduleModel?>> {
  final Ref _ref;

  SalesReportScheduleController(this._ref) : super(const AsyncData(null));

  Future<SalesReportScheduleModel?> createSchedule({
    required String name,
    required SalesReportCadence cadence,
    required SalesReportScope reportScope,
    required SalesReportExportFormat exportFormat,
    required String sendToEmail,
    DateTime? nextRunAt,
  }) async {
    state = const AsyncLoading();

    try {
      final repository = _ref.read(salesReportRepositoryProvider);

      final schedule = await repository.createSchedule(
        name: name,
        cadence: cadence,
        reportScope: reportScope,
        exportFormat: exportFormat,
        sendToEmail: sendToEmail,
        nextRunAt: nextRunAt,
      );

      state = AsyncData(schedule);

      _ref.invalidate(salesReportSchedulesProvider);
      _ref.invalidate(salesReportDeliveryJobsProvider);

      return schedule;
    } catch (e, st) {
      state = AsyncError(e, st);
      return null;
    }
  }

  Future<bool> updateStatus({
    required SalesReportScheduleModel schedule,
    required String status,
  }) async {
    state = const AsyncLoading();

    try {
      final repository = _ref.read(salesReportRepositoryProvider);

      await repository.updateScheduleStatus(schedule: schedule, status: status);

      state = AsyncData(schedule);

      _ref.invalidate(salesReportSchedulesProvider);

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
// EXPORT CONTROLLER
// ════════════════════════════════════════

final salesReportExportControllerProvider =
    StateNotifierProvider<SalesReportExportController, AsyncValue<String?>>((
      ref,
    ) {
      return SalesReportExportController(ref);
    });

class SalesReportExportController extends StateNotifier<AsyncValue<String?>> {
  final Ref _ref;

  SalesReportExportController(this._ref) : super(const AsyncData(null));

  Future<String?> buildCsvExport() async {
    state = const AsyncLoading();

    try {
      final repository = _ref.read(salesReportRepositoryProvider);
      final range = _ref.read(salesReportDateRangeProvider);
      final allBranches = _ref.read(salesReportAllBranchesProvider);

      final csv = await repository.buildCsvExport(
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

  void clear() {
    state = const AsyncData(null);
  }
}

// ════════════════════════════════════════
// SYNC CONTROLLER
// ════════════════════════════════════════

final salesReportSyncControllerProvider =
    StateNotifierProvider<SalesReportSyncController, AsyncValue<void>>((ref) {
      return SalesReportSyncController(ref);
    });

class SalesReportSyncController extends StateNotifier<AsyncValue<void>> {
  final Ref _ref;

  SalesReportSyncController(this._ref) : super(const AsyncData(null));

  Future<void> sync() async {
    state = const AsyncLoading();

    try {
      final repository = _ref.read(salesReportRepositoryProvider);

      await repository.syncOfflineMutations();

      state = const AsyncData(null);

      _ref.invalidate(salesAnalyticsReportProvider);
      _ref.invalidate(salesReportSchedulesProvider);
      _ref.invalidate(salesReportDeliveryJobsProvider);
    } catch (e, st) {
      state = AsyncError(e, st);
    }
  }
}
