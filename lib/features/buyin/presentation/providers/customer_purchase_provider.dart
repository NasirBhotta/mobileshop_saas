import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:mobileshop_saas/features/accounts/presentation/providers/accounts_provider.dart';
import 'package:mobileshop_saas/features/buyin/data/models/customer_purchase_model.dart';
import 'package:mobileshop_saas/features/buyin/data/repositories/customer_purchase_repository.dart';

final customerPurchaseRepositoryProvider = Provider<CustomerPurchaseRepository>((ref) {
  return CustomerPurchaseRepository();
});

final customerPurchasesQueryProvider = StateProvider.autoDispose<String>((ref) => '');

final customerPurchasesProvider = FutureProvider.autoDispose<List<CustomerPurchaseModel>>((ref) async {
  final repository = ref.watch(customerPurchaseRepositoryProvider);
  final query = ref.watch(customerPurchasesQueryProvider);
  return repository.fetchPurchases(query: query);
});

class CustomerPurchaseController extends StateNotifier<AsyncValue<CustomerPurchaseModel?>> {
  final CustomerPurchaseRepository _repository;
  final Ref _ref;

  CustomerPurchaseController(this._repository, this._ref)
      : super(const AsyncValue.data(null));

  Future<CustomerPurchaseModel?> createPurchase({
    required String sellerName,
    required String sellerCnic,
    required String sellerPhone,
    String? sellerAddress,
    String? sellerPhotoUrl,
    String? cnicFrontUrl,
    String? cnicBackUrl,
    String? existingProductId,
    required String productName,
    String? categoryId,
    required String imei1,
    String? imei2,
    String? color,
    String? storage,
    String? deviceCondition,
    String? accessories,
    required double purchasePrice,
    required double expectedSalePrice,
    String? paymentAccountId,
    String? paymentMethod,
    String? notes,
    bool declarationAgreed = true,
  }) async {
    state = const AsyncValue.loading();
    try {
      final purchase = await _repository.createPurchase(
        sellerName: sellerName,
        sellerCnic: sellerCnic,
        sellerPhone: sellerPhone,
        sellerAddress: sellerAddress,
        sellerPhotoUrl: sellerPhotoUrl,
        cnicFrontUrl: cnicFrontUrl,
        cnicBackUrl: cnicBackUrl,
        existingProductId: existingProductId,
        productName: productName,
        categoryId: categoryId,
        imei1: imei1,
        imei2: imei2,
        color: color,
        storage: storage,
        deviceCondition: deviceCondition,
        accessories: accessories,
        purchasePrice: purchasePrice,
        expectedSalePrice: expectedSalePrice,
        paymentAccountId: paymentAccountId,
        paymentMethod: paymentMethod,
        notes: notes,
        declarationAgreed: declarationAgreed,
      );

      _ref.invalidate(customerPurchasesProvider);
      _ref.invalidate(accountsProvider);
      state = AsyncValue.data(purchase);
      return purchase;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      rethrow;
    }
  }

  Future<bool> deletePurchase(String id) async {
    try {
      await _repository.deletePurchase(id);
      _ref.invalidate(customerPurchasesProvider);
      return true;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      return false;
    }
  }
}

final customerPurchaseControllerProvider =
    StateNotifierProvider<CustomerPurchaseController, AsyncValue<CustomerPurchaseModel?>>((ref) {
  final repository = ref.watch(customerPurchaseRepositoryProvider);
  return CustomerPurchaseController(repository, ref);
});
