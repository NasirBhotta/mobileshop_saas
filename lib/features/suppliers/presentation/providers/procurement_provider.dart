import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:mobileshop_saas/features/inventory/presentation/providers/inventory_provider.dart';
import 'package:mobileshop_saas/core/entitlements/entitlement_evaluator.dart';
import 'package:mobileshop_saas/core/entitlements/entitlement_provider.dart';
import 'package:mobileshop_saas/features/suppliers/data/models/procurement_models.dart';
import 'package:mobileshop_saas/features/suppliers/data/repositories/procurement_repository.dart';

final procurementRepositoryProvider = Provider<ProcurementRepository>((ref) {
  return ProcurementRepository(
    entitlementEvaluator: ref.watch(entitlementEvaluatorProvider),
  );
});

Future<void> _requireProcurement(Ref ref, String feature) async {
  final evaluator = ref.read(entitlementEvaluatorProvider);
  if (!await hasFeatureWithCompatibility(evaluator, feature)) {
    throw EntitlementDeniedException(feature);
  }
}

final suppliersProvider = FutureProvider.autoDispose<List<SupplierModel>>((
  ref,
) {
  return ref.read(procurementRepositoryProvider).fetchSuppliers();
});

final selectedPOStatusProvider = StateProvider<PurchaseOrderStatus?>((ref) {
  return null;
});

final purchaseOrdersProvider =
    FutureProvider.autoDispose<List<PurchaseOrderModel>>((ref) {
      final status = ref.watch(selectedPOStatusProvider);
      return ref
          .read(procurementRepositoryProvider)
          .fetchPurchaseOrders(status: status);
    });

final supplierControllerProvider =
    StateNotifierProvider<SupplierController, AsyncValue<SupplierModel?>>((
      ref,
    ) {
      return SupplierController(ref);
    });

class SupplierController extends StateNotifier<AsyncValue<SupplierModel?>> {
  final Ref _ref;

  SupplierController(this._ref) : super(const AsyncData(null));

  Future<SupplierModel?> createSupplier({
    required String name,
    String? contactPerson,
    String? phone,
    String? email,
    String? address,
    String? city,
    String? paymentTerms,
    String? notes,
  }) async {
    state = const AsyncLoading();

    try {
      await _requireProcurement(_ref, 'procurement.suppliers');
      final supplier = await _ref
          .read(procurementRepositoryProvider)
          .createSupplier(
            name: name,
            contactPerson: contactPerson,
            phone: phone,
            email: email,
            address: address,
            city: city,
            paymentTerms: paymentTerms,
            notes: notes,
          );

      state = AsyncData(supplier);
      _ref.invalidate(suppliersProvider);
      return supplier;
    } catch (e, st) {
      state = AsyncError(e, st);
      return null;
    }
  }
}

final purchaseOrderControllerProvider = StateNotifierProvider<
  PurchaseOrderController,
  AsyncValue<PurchaseOrderModel?>
>((ref) {
  return PurchaseOrderController(ref);
});

class PurchaseOrderController
    extends StateNotifier<AsyncValue<PurchaseOrderModel?>> {
  final Ref _ref;

  PurchaseOrderController(this._ref) : super(const AsyncData(null));

  Future<PurchaseOrderModel?> createPO({
    required String supplierId,
    DateTime? expectedDeliveryAt,
    String? notes,
    required List<PurchaseOrderItemModel> items,
  }) async {
    state = const AsyncLoading();

    try {
      await _requireProcurement(_ref, 'procurement.purchase_orders');
      final po = await _ref
          .read(procurementRepositoryProvider)
          .createPurchaseOrder(
            supplierId: supplierId,
            expectedDeliveryAt: expectedDeliveryAt,
            notes: notes,
            items: items,
          );

      state = AsyncData(po);
      _ref.invalidate(purchaseOrdersProvider);
      return po;
    } catch (e, st) {
      state = AsyncError(e, st);
      return null;
    }
  }

  Future<void> markSent(PurchaseOrderModel po) async {
    state = const AsyncLoading();

    try {
      await _requireProcurement(_ref, 'procurement.purchase_orders');
      await _ref.read(procurementRepositoryProvider).markPurchaseOrderSent(po);
      state = AsyncData(po.copyWith(status: PurchaseOrderStatus.sent));
      _ref.invalidate(purchaseOrdersProvider);
    } catch (e, st) {
      state = AsyncError(e, st);
    }
  }
}

final receiveGoodsControllerProvider =
    StateNotifierProvider<ReceiveGoodsController, AsyncValue<void>>((ref) {
      return ReceiveGoodsController(ref);
    });

class ReceiveGoodsController extends StateNotifier<AsyncValue<void>> {
  final Ref _ref;

  ReceiveGoodsController(this._ref) : super(const AsyncData(null));

  Future<bool> receive({
    required PurchaseOrderModel po,
    String? note,
    required List<GoodsReceiptItemInput> inputs,
  }) async {
    state = const AsyncLoading();

    try {
      await _requireProcurement(_ref, 'procurement.goods_receipts');
      await _ref
          .read(procurementRepositoryProvider)
          .receiveGoods(po: po, note: note, inputs: inputs);

      await _ref
          .read(inventoryRepositoryProvider)
          .refreshCurrentProductsCache();

      state = const AsyncData(null);
      _ref.invalidate(purchaseOrdersProvider);
      invalidateProductListProviders(_ref);
      return true;
    } catch (e, st) {
      state = AsyncError(e, st);
      return false;
    }
  }
}

final supplierPaymentControllerProvider =
    StateNotifierProvider<SupplierPaymentController, AsyncValue<void>>((ref) {
      return SupplierPaymentController(ref);
    });

class SupplierPaymentController extends StateNotifier<AsyncValue<void>> {
  final Ref _ref;

  SupplierPaymentController(this._ref) : super(const AsyncData(null));

  Future<bool> recordPayment({
    required SupplierModel supplier,
    required double amount,
    String? method,
    String? note,
  }) async {
    state = const AsyncLoading();

    try {
      await _requireProcurement(_ref, 'procurement.supplier_payments');
      await _ref
          .read(procurementRepositoryProvider)
          .recordSupplierPayment(
            supplier: supplier,
            amount: amount,
            method: method,
            note: note,
          );

      state = const AsyncData(null);
      _ref.invalidate(suppliersProvider);
      return true;
    } catch (e, st) {
      state = AsyncError(e, st);
      return false;
    }
  }
}

final procurementSyncControllerProvider =
    StateNotifierProvider<ProcurementSyncController, AsyncValue<void>>((ref) {
      return ProcurementSyncController(ref);
    });

class ProcurementSyncController extends StateNotifier<AsyncValue<void>> {
  final Ref _ref;

  ProcurementSyncController(this._ref) : super(const AsyncData(null));

  Future<void> sync() async {
    state = const AsyncLoading();

    try {
      final repository = _ref.read(procurementRepositoryProvider);
      await repository.syncOfflineMutations();

      Future<void> safelyRefresh(Future<Object?> refresh) async {
        try {
          await refresh;
        } catch (_) {
          // Keep the existing local cache when a source is unavailable.
        }
      }

      await Future.wait([
        safelyRefresh(
          repository.refreshCurrentSuppliersCache(
            timeout: const Duration(seconds: 10),
          ),
        ),
        safelyRefresh(
          repository.refreshCurrentPurchaseOrdersCache(
            status: _ref.read(selectedPOStatusProvider),
            timeout: const Duration(seconds: 10),
          ),
        ),
      ]);

      _ref
        ..invalidate(suppliersProvider)
        ..invalidate(purchaseOrdersProvider);
      await Future.wait([
        safelyRefresh(_ref.read(suppliersProvider.future)),
        safelyRefresh(_ref.read(purchaseOrdersProvider.future)),
      ]);

      state = const AsyncData(null);
    } catch (e, st) {
      state = AsyncError(e, st);
    }
  }
}
