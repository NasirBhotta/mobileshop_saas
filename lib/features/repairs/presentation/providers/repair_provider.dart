import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:mobileshop_saas/core/extensions/repair_ticket_ext.dart';

import '../../data/models/repair_status_log_model.dart';
import '../../data/models/repair_ticket_model.dart';
import '../../data/models/repair_payment_model.dart';
import '../../data/models/repair_part_model.dart';
import '../../data/repositories/repair_repository.dart';
import '../../../../core/entitlements/entitlement_provider.dart';
import '../../../../core/entitlements/entitlement_evaluator.dart';
import '../../../../core/authorization/branch_permission_shadow_provider.dart';
import '../../../accounts/presentation/providers/accounts_provider.dart';
import '../../../inventory/presentation/providers/inventory_provider.dart';
import '../../../reports/presentation/providers/business_report_provider.dart';

/// Repository provider.
///
/// UI ya controller directly `RepairRepository()` create nahi karega.
/// Riverpod repository instance provide karega.
///
/// Iska faida:
/// - testing easy
/// - dependency centralized
/// - future mein mock repository lagana easy
final repairRepositoryProvider = Provider<RepairRepository>((ref) {
  return RepairRepository(
    entitlementEvaluator: ref.watch(entitlementEvaluatorProvider),
  );
});

/// Status filter provider.
///
/// Repairs screen mein user filter kar sakega:
/// - All
/// - Received
/// - Diagnosed
/// - In Progress
/// - Waiting Part
/// - Completed
/// - Delivered
///
/// Null ka matlab: all tickets.
final selectedRepairStatusFilterProvider = StateProvider<RepairTicketStatus?>((
  ref,
) {
  return null;
});

/// Repair tickets list provider.
///
/// Yeh provider selected status filter ko watch karta hai.
/// Agar filter change ho:
/// - provider automatically dobara run hoga
/// - list refresh ho jayegi
///
/// Example:
/// selectedRepairStatusFilterProvider = RepairTicketStatus.received
/// then sirf received tickets load honge.
final repairTicketsProvider =
    FutureProvider.autoDispose<List<RepairTicketModel>>((ref) async {
      final repository = ref.read(repairRepositoryProvider);
      final status = ref.watch(selectedRepairStatusFilterProvider);

      return repository.fetchRepairTickets(status: status);
    });

final allRepairTicketsProvider =
    FutureProvider.autoDispose<List<RepairTicketModel>>((ref) async {
      final repository = ref.read(repairRepositoryProvider);

      return repository.fetchRepairTickets();
    });

/// Ticket status logs provider.
///
/// Family provider isliye use kiya kyunki har ticket ke logs alag hain.
///
/// Usage:
/// ref.watch(repairStatusLogsProvider(ticketId))
final repairStatusLogsProvider = FutureProvider.autoDispose
    .family<List<RepairStatusLogModel>, String>((ref, ticketId) async {
      final repository = ref.read(repairRepositoryProvider);

      return repository.fetchStatusLogs(ticketId);
    });

final repairPaymentsProvider = FutureProvider.autoDispose
    .family<List<RepairPaymentModel>, String>((ref, ticketId) {
      return ref.read(repairRepositoryProvider).fetchRepairPayments(ticketId);
    });

final repairPartsProvider = FutureProvider.autoDispose
    .family<List<RepairPartModel>, String>((ref, ticketId) {
      return ref.read(repairRepositoryProvider).fetchRepairParts(ticketId);
    });

/// Create/update controller.
///
/// Iska state `AsyncValue<RepairTicketModel?>` rakha hai.
///
/// Normal state:
/// AsyncData(null)
///
/// Create ke waqt:
/// AsyncLoading()
///
/// Success:
/// AsyncData(createdTicket)
///
/// Error:
/// AsyncError(error, stackTrace)
final repairTicketControllerProvider = StateNotifierProvider<
  RepairTicketController,
  AsyncValue<RepairTicketModel?>
>((ref) {
  return RepairTicketController(ref);
});

final repairPaymentControllerProvider =
    StateNotifierProvider<RepairPaymentController, AsyncValue<void>>((ref) {
      return RepairPaymentController(ref);
    });

class RepairPaymentController extends StateNotifier<AsyncValue<void>> {
  final Ref _ref;

  RepairPaymentController(this._ref) : super(const AsyncData(null));

  Future<bool> recordPayment({
    required RepairTicketModel ticket,
    required double amount,
    required String method,
    required String accountId,
    String? note,
  }) async {
    state = const AsyncLoading();
    try {
      if (!await hasFeatureWithCompatibility(
        _ref.read(entitlementEvaluatorProvider),
        'repairs.tickets',
      )) {
        throw const EntitlementDeniedException('repairs.tickets');
      }
      final allowed = await _ref.read(
        branchAwarePermissionProvider('repair.payment.create').future,
      );
      if (!allowed) {
        throw StateError('Permission required: repair.payment.create');
      }
      await _ref
          .read(repairRepositoryProvider)
          .recordRepairPayment(
            ticket: ticket,
            amount: amount,
            method: method,
            accountId: accountId,
            note: note,
          );
      state = const AsyncData(null);
      _ref.invalidate(repairPaymentsProvider(ticket.id));
      _ref.invalidate(accountsProvider);
      invalidateBusinessReports(_ref);
      return true;
    } catch (e, st) {
      state = AsyncError(e, st);
      return false;
    }
  }
}

class RepairTicketController
    extends StateNotifier<AsyncValue<RepairTicketModel?>> {
  final Ref _ref;

  RepairTicketController(this._ref) : super(const AsyncData(null));

  /// Create repair ticket.
  ///
  /// UI screen is method ko call karegi.
  ///
  /// Important:
  /// Screen ko tenantId, branchId, userId ka kuch nahi pata.
  /// Yeh sab repository khud handle karegi.
  Future<RepairTicketModel?> createTicket({
    String? customerId,
    required String customerName,
    String? customerPhone,
    String? productId,
    required String deviceBrand,
    required String deviceModel,
    String? deviceColor,
    String? imei,
    required String faultDescription,
    String? technicianId,
    double? estimatedCost,
    DateTime? estimatedCompletionAt,
    String? estimateNote,
  }) async {
    state = const AsyncLoading();

    try {
      if (!await hasFeatureWithCompatibility(
        _ref.read(entitlementEvaluatorProvider),
        'repairs.tickets',
      )) {
        throw const EntitlementDeniedException('repairs.tickets');
      }
      if (imei?.trim().isNotEmpty == true &&
          !await hasFeatureWithCompatibility(
            _ref.read(entitlementEvaluatorProvider),
            'repairs.imei_linking',
          )) {
        throw const EntitlementDeniedException('repairs.imei_linking');
      }
      final repository = _ref.read(repairRepositoryProvider);

      final ticket = await repository.createRepairTicket(
        customerId: customerId,
        customerName: customerName,
        customerPhone: customerPhone,
        productId: productId,
        deviceBrand: deviceBrand,
        deviceModel: deviceModel,
        deviceColor: deviceColor,
        imei: imei,
        faultDescription: faultDescription,
        technicianId: technicianId,
        estimatedCost: estimatedCost,
        estimatedCompletionAt: estimatedCompletionAt,
        estimateNote: estimateNote,
      );

      state = AsyncData(ticket);

      /// Ticket create hone ke baad tickets list refresh karni zaroori hai.
      ///
      /// Warna UI old cached list dikha sakti hai.
      _ref.invalidate(repairTicketsProvider);
      _ref.invalidate(allRepairTicketsProvider);

      return ticket;
    } catch (e, st) {
      state = AsyncError(e, st);
      return null;
    }
  }

  Future<RepairTicketModel?> updateStatus({
    required RepairTicketModel ticket,
    required RepairTicketStatus status,
    String? note,
    double? totalCost,
  }) async {
    state = const AsyncLoading();

    try {
      if (!await hasFeatureWithCompatibility(
        _ref.read(entitlementEvaluatorProvider),
        'repairs.tickets',
      )) {
        throw const EntitlementDeniedException('repairs.tickets');
      }
      final repository = _ref.read(repairRepositoryProvider);

      final updatedTicket = await repository.updateRepairTicketStatus(
        ticket: ticket,
        status: status,
        note: note,
        totalCost: totalCost,
      );

      state = AsyncData(updatedTicket);

      _ref.invalidate(repairTicketsProvider);
      _ref.invalidate(allRepairTicketsProvider);
      _ref.invalidate(repairStatusLogsProvider(ticket.id));

      return updatedTicket;
    } catch (e, st) {
      state = AsyncError(e, st);
      return null;
    }
  }

  Future<RepairTicketModel?> completeRepair({
    required RepairTicketModel ticket,
    required List<RepairPartModel> parts,
    required double customerCharge,
    double serviceCharge = 0,
    double discount = 0,
    double commission = 0,
    double otherDirectCost = 0,
  }) async {
    state = const AsyncLoading();
    try {
      final repository = _ref.read(repairRepositoryProvider);
      await repository.saveRepairParts(ticket: ticket, parts: parts);
      final updated = await repository.completeRepair(
        ticket: ticket,
        customerCharge: customerCharge,
        serviceCharge: serviceCharge,
        discount: discount,
        commission: commission,
        otherDirectCost: otherDirectCost,
      );
      state = AsyncData(updated);
      _invalidateFinancialRepair(ticket.id);
      return updated;
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      return null;
    }
  }

  Future<RepairTicketModel?> cancelRepair(RepairTicketModel ticket) async {
    state = const AsyncLoading();
    try {
      final updated = await _ref
          .read(repairRepositoryProvider)
          .cancelRepair(ticket);
      state = AsyncData(updated);
      _invalidateFinancialRepair(ticket.id);
      return updated;
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      return null;
    }
  }

  Future<bool> archiveRepair(RepairTicketModel ticket) async {
    state = const AsyncLoading();
    try {
      await _ref.read(repairRepositoryProvider).archiveRepair(ticket);
      state = const AsyncData(null);
      _ref
        ..invalidate(repairTicketsProvider)
        ..invalidate(allRepairTicketsProvider);
      return true;
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      return false;
    }
  }

  void _invalidateFinancialRepair(String ticketId) {
    _ref
      ..invalidate(repairTicketsProvider)
      ..invalidate(allRepairTicketsProvider)
      ..invalidate(repairPartsProvider(ticketId))
      ..invalidate(repairStatusLogsProvider(ticketId));
    invalidateProductListProviders(_ref);
    invalidateBusinessReports(_ref);
  }

  /// Controller state reset.
  ///
  /// Example:
  /// Form close ho gaya ya success message show ho gaya,
  /// to state wapas normal kar sakte hain.
  void reset() {
    state = const AsyncData(null);
  }
}

/// Manual sync controller.
///
/// Normally repository fetch ke waqt sync try karegi.
/// Lekin dashboard/repairs screen par pull-to-refresh ya sync button ke liye
/// yeh controller useful rahega.
final repairSyncControllerProvider =
    StateNotifierProvider<RepairSyncController, AsyncValue<void>>((ref) {
      return RepairSyncController(ref);
    });

class RepairSyncController extends StateNotifier<AsyncValue<void>> {
  final Ref _ref;

  RepairSyncController(this._ref) : super(const AsyncData(null));

  Future<void> sync() async {
    state = const AsyncLoading();

    try {
      final repository = _ref.read(repairRepositoryProvider);

      await repository.syncOfflineMutations();
      try {
        await repository.refreshCurrentRepairTicketsCache(
          timeout: const Duration(seconds: 10),
        );
      } catch (_) {
        // Keep showing the current local cache when the server is unavailable.
      }

      _ref
        ..invalidate(repairTicketsProvider)
        ..invalidate(allRepairTicketsProvider);
      await _ref.read(repairTicketsProvider.future);

      state = const AsyncData(null);
    } catch (e, st) {
      state = AsyncError(e, st);
    }
  }
}
