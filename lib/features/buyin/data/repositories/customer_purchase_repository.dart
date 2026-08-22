import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:mobileshop_saas/core/local/local_store.dart';
import 'package:mobileshop_saas/core/offline/offline_store.dart';
import 'package:mobileshop_saas/features/accounts/data/local/accounts_local_store.dart';
import 'package:mobileshop_saas/features/accounts/data/models/account_models.dart';
import 'package:mobileshop_saas/features/buyin/data/models/customer_purchase_model.dart';
import 'package:mobileshop_saas/features/inventory/data/models/product_model.dart';
import 'package:mobileshop_saas/features/repairs/data/models/inventory_unit_model.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

class CustomerPurchaseRepository {
  static const _networkTimeout = Duration(milliseconds: 2500);

  final SupabaseClient _client;

  CustomerPurchaseRepository({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  String? get _currentUserId => _client.auth.currentUser?.id;

  Future<String> _currentTenantId() async {
    final userId = _currentUserId;
    if (userId != null) {
      final profile = await OfflineStore.loadProfile(userId);
      final tenantId = profile?['tenant_id'] as String?;
      if (tenantId != null && tenantId.isNotEmpty) {
        return tenantId;
      }
    }
    return 'default_tenant';
  }

  Future<String?> _currentBranchId() async {
    final userId = _currentUserId;
    if (userId != null) {
      final branchId = await OfflineStore.loadSelectedBranchId(userId);
      if (branchId != null && branchId.isNotEmpty) return branchId;
      final profile = await OfflineStore.loadProfile(userId);
      return profile?['branch_id'] as String?;
    }
    return null;
  }

  Future<CustomerPurchaseModel> createPurchase({
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
    final tenantId = await _currentTenantId();
    final branchId = (await _currentBranchId()) ?? 'default_branch';
    final userId = _currentUserId ?? 'default_user';
    final purchaseId = const Uuid().v4();
    final now = DateTime.now();

    // ── 0. Check Account Balance if paying from an Account ──
    if (paymentAccountId != null && paymentAccountId.isNotEmpty && purchasePrice > 0) {
      final account = await AccountsLocalStore.loadAccountById(paymentAccountId);
      if (account != null && account.currentBalance < purchasePrice) {
        throw Exception(
          'Account "${account.name}" has insufficient balance.\n'
          'Available: Rs. ${account.currentBalance.toStringAsFixed(0)}, Required: Rs. ${purchasePrice.toStringAsFixed(0)}',
        );
      }
    }

    // ── 1. Determine Product ID & Update/Create Product ──
    String effectiveProductId = existingProductId ?? '';
    final cleanImei = imei1.trim();
    final generatedSku = 'USED-${cleanImei.length >= 6 ? cleanImei.substring(cleanImei.length - 6) : cleanImei}';
    int targetStock = 1;

    if (effectiveProductId.isEmpty) {
      effectiveProductId = const Uuid().v4();
      targetStock = 1;
      final newProduct = ProductModel(
        id: effectiveProductId,
        tenantId: tenantId,
        branchId: branchId,
        categoryId: categoryId,
        name: productName.trim(),
        salePrice: expectedSalePrice,
        costPrice: purchasePrice,
        barcode: cleanImei,
        sku: generatedSku,
        imeiTracked: true,
        isActive: true,
        stock: 1,
      );
      try {
        await OfflineStore.upsertCachedProduct(newProduct);
      } catch (e) {
        debugPrint('OfflineStore upsertCachedProduct in buy-in: $e');
      }
    } else {
      // Existing product stock increment
      try {
        final existingProducts = await OfflineStore.loadProducts(branchId);
        final found = existingProducts.where((p) => p.id == effectiveProductId).toList();
        if (found.isNotEmpty) {
          targetStock = found.first.stock + 1;
          final updatedProduct = ProductModel(
            id: found.first.id,
            tenantId: found.first.tenantId,
            branchId: found.first.branchId,
            categoryId: found.first.categoryId,
            name: found.first.name,
            salePrice: expectedSalePrice > 0 ? expectedSalePrice : found.first.salePrice,
            costPrice: purchasePrice > 0 ? purchasePrice : found.first.costPrice,
            barcode: (found.first.barcode != null && found.first.barcode!.isNotEmpty)
                ? found.first.barcode
                : cleanImei,
            sku: (found.first.sku != null && found.first.sku!.isNotEmpty)
                ? found.first.sku
                : generatedSku,
            imeiTracked: true,
            isActive: true,
            stock: targetStock,
          );
          await OfflineStore.upsertCachedProduct(updatedProduct);
        }
      } catch (e) {
        debugPrint('OfflineStore stock increment in buy-in: $e');
      }
    }

    // Upsert product and inventory remotely so Supabase foreign key exists
    try {
      final productPayload = {
        'id': effectiveProductId,
        'tenant_id': tenantId,
        'branch_id': branchId,
        'category_id': categoryId,
        'name': productName.trim(),
        'sale_price': expectedSalePrice,
        'cost_price': purchasePrice,
        'barcode': cleanImei,
        'sku': generatedSku,
        'imei_tracked': true,
        'is_active': true,
      };
      await _client.from('products').upsert(productPayload, onConflict: 'id').timeout(_networkTimeout);
      await _client.from('inventory').upsert({
        'branch_id': branchId,
        'product_id': effectiveProductId,
        'quantity': targetStock,
      }, onConflict: 'branch_id,product_id').timeout(_networkTimeout);
    } catch (e) {
      debugPrint('Product remote sync for buy-in failed (will be queued): $e');
    }

    // ── 2. Create and Register IMEI Inventory Unit ──
    final inventoryUnitId = const Uuid().v4();
    final inventoryUnit = InventoryUnitModel(
      id: inventoryUnitId,
      tenantId: tenantId,
      branchId: branchId,
      productId: effectiveProductId,
      imei: cleanImei,
      status: InventoryUnitStatus.available,
      createdAt: now,
      updatedAt: now,
    );

    try {
      await OfflineStore.upsertInventoryUnit(inventoryUnit);
    } catch (e) {
      debugPrint('OfflineStore upsertInventoryUnit in buy-in: $e');
    }

    try {
      await _client.from('inventory_units').upsert(inventoryUnit.toMap(), onConflict: 'id').timeout(_networkTimeout);
    } catch (e) {
      debugPrint('Inventory unit remote sync in buy-in failed: $e');
    }

    // ── 3. Record Financial Outflow (if payment account selected) ──
    if (paymentAccountId != null && paymentAccountId.isNotEmpty && purchasePrice > 0) {
      final transactionId = const Uuid().v4();
      final transaction = AccountTransactionModel(
        id: transactionId,
        tenantId: tenantId,
        branchId: branchId,
        accountId: paymentAccountId,
        type: AccountTransactionType.purchase,
        direction: AccountTransactionDirection.moneyOut,
        amount: purchasePrice,
        description: 'Second-Hand Mobile Buy-In: $productName (IMEI: $cleanImei) from $sellerName',
        referenceType: 'customer_buyin',
        referenceId: purchaseId,
        sourceEventKey: 'customer_buyin:$purchaseId',
        transactionAt: now,
        createdBy: userId,
        createdAt: now,
      );

      try {
        await AccountsLocalStore.applyTransaction(transaction);
      } catch (e) {
        debugPrint('AccountsLocalStore applyTransaction in buy-in: $e');
      }

      try {
        await _client.rpc(
          'record_account_transaction',
          params: {
            'p_account_id': paymentAccountId,
            'p_type': transaction.type.code,
            'p_direction': transaction.direction.code,
            'p_amount': transaction.amount,
            'p_description': transaction.description,
            'p_reference_type': transaction.referenceType,
            'p_reference_id': transaction.referenceId,
            'p_source_event_key': transaction.sourceEventKey,
            'p_transaction_at': transaction.transactionAt.toIso8601String(),
          },
        ).timeout(_networkTimeout);
      } catch (e) {
        debugPrint('Account transaction remote sync failed (queued): $e');
        try {
          await OfflineStore.enqueueMutation(
            userId: userId,
            type: 'record_account_transaction',
            payload: transaction.toMap(),
          );
        } catch (_) {}
      }
    }

    // ── 4. Save Customer Purchase Record Locally ──
    final purchase = CustomerPurchaseModel(
      id: purchaseId,
      tenantId: tenantId,
      branchId: branchId,
      sellerName: sellerName.trim(),
      sellerCnic: sellerCnic.trim(),
      sellerPhone: sellerPhone.trim(),
      sellerAddress: sellerAddress?.trim(),
      sellerPhotoUrl: sellerPhotoUrl,
      cnicFrontUrl: cnicFrontUrl,
      cnicBackUrl: cnicBackUrl,
      productId: effectiveProductId,
      productName: productName.trim(),
      categoryId: categoryId,
      imei1: cleanImei,
      imei2: imei2?.trim(),
      color: color?.trim(),
      storage: storage?.trim(),
      deviceCondition: deviceCondition?.trim(),
      accessories: accessories?.trim(),
      purchasePrice: purchasePrice,
      expectedSalePrice: expectedSalePrice,
      paymentAccountId: paymentAccountId,
      paymentMethod: paymentMethod ?? 'cash',
      notes: notes?.trim(),
      declarationAgreed: declarationAgreed,
      status: 'in_stock',
      createdBy: userId,
      createdAt: now,
      updatedAt: now,
    );

    await OfflineStore.saveCustomerPurchase(purchase);

    // ── 5. Attempt Remote Supabase Sync / Queue Offline Mutation ──
    final payload = purchase.toMap();
    try {
      await _client
          .from('customer_purchases')
          .upsert(payload, onConflict: 'id')
          .timeout(_networkTimeout);
    } catch (e) {
      debugPrint('Customer purchase remote insert failed (queued for sync): $e');
      try {
        await OfflineStore.enqueueMutation(
          userId: userId,
          type: 'create_customer_buyin',
          payload: payload,
        );
      } catch (_) {}
    }

    return purchase;
  }

  Future<List<CustomerPurchaseModel>> fetchPurchases({
    String? query,
    int limit = 100,
  }) async {
    final branchId = (await _currentBranchId()) ?? 'default_branch';

    // 1. Check local cache (SQLite + SharedPreferences)
    final localPurchases = await OfflineStore.loadCustomerPurchases(
      branchId,
      query: query,
      limit: limit,
    );

    // Trigger background sync
    unawaited(syncOfflineMutations());

    // 2. Fetch remote and refresh cache in background if connected
    unawaited(_refreshPurchases(branchId));

    return localPurchases;
  }

  Future<void> _refreshPurchases(String branchId) async {
    try {
      final rows = await _client
          .from('customer_purchases')
          .select()
          .eq('branch_id', branchId)
          .order('created_at', ascending: false)
          .limit(100)
          .timeout(_networkTimeout);

      final remoteList = (rows as List)
          .map((r) => CustomerPurchaseModel.fromMap(Map<String, dynamic>.from(r as Map)))
          .toList();

      if (remoteList.isNotEmpty) {
        await OfflineStore.saveCustomerPurchases(branchId, remoteList);
      }
    } catch (_) {}
  }

  Future<CustomerPurchaseModel?> fetchPurchaseById(String id) async {
    return await LocalStore.loadCustomerPurchaseById(id);
  }

  Future<void> deletePurchase(String id) async {
    final branchId = (await _currentBranchId()) ?? 'default_branch';
    final userId = _currentUserId ?? 'default_user';

    await OfflineStore.deleteCustomerPurchase(branchId, id);

    try {
      await _client
          .from('customer_purchases')
          .delete()
          .eq('id', id)
          .timeout(_networkTimeout);
    } catch (e) {
      debugPrint('Customer purchase remote delete failed (queued): $e');
      try {
        await OfflineStore.enqueueMutation(
          userId: userId,
          type: 'delete_customer_buyin',
          payload: {'id': id},
        );
      } catch (_) {}
    }
  }

  Future<void> syncOfflineMutations() async {
    final userId = _currentUserId;
    if (userId == null) return;

    final mutations = await OfflineStore.loadMutations(userId);
    final buyinMutations = mutations.where(
      (m) =>
          m.type == 'create_customer_buyin' ||
          m.type == 'delete_customer_buyin' ||
          m.type == 'update_customer_buyin_status',
    ).toList();
    if (buyinMutations.isEmpty) return;

    final remaining = <OfflineMutation>[];
    final random = Random();

    for (final mutation in mutations) {
      if (mutation.type != 'create_customer_buyin' &&
          mutation.type != 'delete_customer_buyin' &&
          mutation.type != 'update_customer_buyin_status') {
        remaining.add(mutation);
        continue;
      }

      try {
        final jitterMs = random.nextInt(150);
        if (jitterMs > 0) {
          await Future.delayed(Duration(milliseconds: jitterMs));
        }

        if (mutation.type == 'delete_customer_buyin') {
          final id = mutation.payload['id'] as String;
          await _client
              .from('customer_purchases')
              .delete()
              .eq('id', id)
              .timeout(_networkTimeout);
        } else if (mutation.type == 'update_customer_buyin_status') {
          final id = mutation.payload['id'] as String;
          final status = mutation.payload['status'] as String? ?? 'sold';
          await _client
              .from('customer_purchases')
              .update({'status': status, 'updated_at': DateTime.now().toIso8601String()})
              .eq('id', id)
              .timeout(_networkTimeout);
        } else {
          final payload = Map<String, dynamic>.from(mutation.payload);
          final productId = payload['product_id'] as String?;
          final branchId = payload['branch_id'] as String? ?? 'default_branch';
          final imei1 = payload['imei1'] as String? ?? '';

          if (productId != null && productId.isNotEmpty) {
            // Ensure product exists on remote first to prevent FK constraint 23503 error
            try {
              final products = await OfflineStore.loadProducts(branchId);
              final matched = products.where((p) => p.id == productId).toList();
              if (matched.isNotEmpty) {
                final p = matched.first;
                await _client.from('products').upsert({
                  'id': p.id,
                  'tenant_id': p.tenantId,
                  'branch_id': p.branchId,
                  'category_id': p.categoryId,
                  'name': p.name,
                  'sale_price': p.salePrice,
                  'cost_price': p.costPrice,
                  'barcode': p.barcode,
                  'sku': p.sku,
                  'imei_tracked': p.imeiTracked,
                  'is_active': p.isActive,
                }, onConflict: 'id').timeout(_networkTimeout);

                await _client.from('inventory').upsert({
                  'branch_id': p.branchId,
                  'product_id': p.id,
                  'quantity': p.stock,
                }, onConflict: 'branch_id,product_id').timeout(_networkTimeout);
              }
            } catch (e) {
              debugPrint('Pre-sync product for buy-in failed: $e');
            }

            // Ensure inventory unit exists on remote
            if (imei1.isNotEmpty) {
              try {
                final unit = await OfflineStore.loadInventoryUnitByImei(
                  branchId: branchId,
                  imei: imei1,
                );
                if (unit != null) {
                  await _client
                      .from('inventory_units')
                      .upsert(unit.toMap(), onConflict: 'id')
                      .timeout(_networkTimeout);
                }
              } catch (_) {}
            }
          }

          // Safely upsert customer_purchases
          await _client
              .from('customer_purchases')
              .upsert(payload, onConflict: 'id')
              .timeout(_networkTimeout);
        }
      } catch (e) {
        debugPrint('Customer buy-in mutation sync failed: $e');
        remaining.add(mutation);
      }
    }

    await OfflineStore.saveMutationSyncResult(
      userId: userId,
      snapshot: mutations,
      remaining: remaining,
    );
  }
}
