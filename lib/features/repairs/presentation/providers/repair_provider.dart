import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:mobileshop_saas/core/extensions/repair_ticket_ext.dart';

import '../../data/models/repair_status_log_model.dart';
import '../../data/models/repair_ticket_model.dart';
import '../../data/repositories/repair_repository.dart';
import '../../../../core/entitlements/entitlement_provider.dart';
import '../../../../core/entitlements/entitlement_evaluator.dart';

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
      if (!await _ref
          .read(entitlementEvaluatorProvider)
          .hasFeature('repairs.tickets')) {
        throw const EntitlementDeniedException('repairs.tickets');
      }
      if (imei?.trim().isNotEmpty == true &&
          !await _ref
              .read(entitlementEvaluatorProvider)
              .hasFeature('repairs.imei_linking')) {
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
      if (!await _ref
          .read(entitlementEvaluatorProvider)
          .hasFeature('repairs.tickets')) {
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

      state = const AsyncData(null);

      /// Sync ke baad list refresh.
      _ref.invalidate(repairTicketsProvider);
    } catch (e, st) {
      state = AsyncError(e, st);
    }
  }
}
