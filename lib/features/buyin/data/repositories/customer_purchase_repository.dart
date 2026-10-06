import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:mobileshop_saas/core/local/local_store.dart';
import 'package:mobileshop_saas/core/offline/offline_store.dart';
import 'package:mobileshop_saas/core/utils/offline_error_classifier.dart';
import 'package:mobileshop_saas/core/utils/secure_rpc_compatibility.dart';
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
    if (paymentAccountId != null &&
        paymentAccountId.isNotEmpty &&
        purchasePrice > 0) {
      final account = await AccountsLocalStore.loadAccountById(
        paymentAccountId,
      );
      if (account != null && account.currentBalance < purchasePrice) {
        throw Exception(
          'Account "${account.name}" has insufficient balance.\n'
          'Available: Rs. ${account.currentBalance.toStringAsFixed(0)}, Required: Rs. ${purchasePrice.toStringAsFixed(0)}',
        );
      }
    }

    // ── 1. Determine Product ID & Update/Create Product ──
    final securePurchase = await _trySecureBuyin(
      tenantId: tenantId,
      branchId: branchId,
      userId: userId,
      existingProductId: existingProductId,
      sellerName: sellerName,
      sellerCnic: sellerCnic,
      sellerPhone: sellerPhone,
      sellerAddress: sellerAddress,
      sellerPhotoUrl: sellerPhotoUrl,
      cnicFrontUrl: cnicFrontUrl,
      cnicBackUrl: cnicBackUrl,
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
      now: now,
    );
    if (securePurchase != null) return securePurchase;

    String effectiveProductId = existingProductId ?? '';
    final cleanImei = imei1.trim();
    final generatedSku =
        'USED-${cleanImei.length >= 6 ? cleanImei.substring(cleanImei.length - 6) : cleanImei}';
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
        final found =
            existingProducts.where((p) => p.id == effectiveProductId).toList();
        if (found.isNotEmpty) {
          targetStock = found.first.stock + 1;
          final updatedProduct = ProductModel(
            id: found.first.id,
            tenantId: found.first.tenantId,
            branchId: found.first.branchId,
            categoryId: found.first.categoryId,
            name: found.first.name,
            salePrice:
                expectedSalePrice > 0
                    ? expectedSalePrice
                    : found.first.salePrice,
            costPrice:
                purchasePrice > 0 ? purchasePrice : found.first.costPrice,
            barcode:
                (found.first.barcode != null && found.first.barcode!.isNotEmpty)
                    ? found.first.barcode
                    : cleanImei,
            sku:
                (found.first.sku != null && found.first.sku!.isNotEmpty)
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
      await _client
          .from('products')
          .upsert(productPayload, onConflict: 'id')
          .timeout(_networkTimeout);
      await _client
          .from('inventory')
          .upsert({
            'branch_id': branchId,
            'product_id': effectiveProductId,
            'quantity': targetStock,
          }, onConflict: 'branch_id,product_id')
          .timeout(_networkTimeout);
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
      await _client
          .from('inventory_units')
          .upsert(inventoryUnit.toMap(), onConflict: 'id')
          .timeout(_networkTimeout);
    } catch (e) {
      debugPrint('Inventory unit remote sync in buy-in failed: $e');
    }

    // ── 3. Record Financial Outflow (if payment account selected) ──
    if (paymentAccountId != null &&
        paymentAccountId.isNotEmpty &&
        purchasePrice > 0) {
      final transactionId = const Uuid().v4();
      final transaction = AccountTransactionModel(
        id: transactionId,
        tenantId: tenantId,
        branchId: branchId,
        accountId: paymentAccountId,
        type: AccountTransactionType.purchase,
        direction: AccountTransactionDirection.moneyOut,
        amount: purchasePrice,
        description:
            'Second-Hand Mobile Buy-In: $productName (IMEI: $cleanImei) from $sellerName',
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
        await _client
            .rpc(
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
            )
            .timeout(_networkTimeout);
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
      debugPrint(
        'Customer purchase remote insert failed (queued for sync): $e',
      );
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

  Future<CustomerPurchaseModel?> _trySecureBuyin({
    required String tenantId,
    required String branchId,
    required String userId,
    required String? existingProductId,
    required String sellerName,
    required String sellerCnic,
    required String sellerPhone,
    required String? sellerAddress,
    required String? sellerPhotoUrl,
    required String? cnicFrontUrl,
    required String? cnicBackUrl,
    required String productName,
    required String? categoryId,
    required String imei1,
    required String? imei2,
    required String? color,
    required String? storage,
    required String? deviceCondition,
    required String? accessories,
    required double purchasePrice,
    required double expectedSalePrice,
    required String? paymentAccountId,
    required String? paymentMethod,
    required String? notes,
    required bool declarationAgreed,
    required DateTime now,
  }) async {
    final purchaseId = const Uuid().v4();
    final isNewProduct = existingProductId?.trim().isNotEmpty != true;
    final productId =
        isNewProduct ? const Uuid().v4() : existingProductId!.trim();
    final unitId = const Uuid().v4();
    final cleanImei = imei1.trim();
    final sku =
        'USED-${cleanImei.length >= 6 ? cleanImei.substring(cleanImei.length - 6) : cleanImei}';
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
      productId: productId,
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
    final payload = {
      ...purchase.toMap(),
      'inventory_unit_id': unitId,
      'create_product': isNewProduct,
      'declaration_agreed': declarationAgreed,
      'sku': sku,
    };

    dynamic result;
    try {
      result = await _client
          .rpc('commit_customer_buyin_v2', params: {'p_buyin': payload})
          .timeout(_networkTimeout);
    } on PostgrestException catch (error) {
      if (isMissingSecureRpc(
        error,
        'commit_customer_buyin_v2',
        argumentName: 'p_buyin',
      )) {
        return null;
      }
      rethrow;
    } catch (error) {
      if (!OfflineErrorClassifier.isRetryable(error)) rethrow;
      await _cacheSecureBuyin(
        purchase: purchase,
        unitId: unitId,
        sku: sku,
        queueForSync: true,
        payload: payload,
      );
      return purchase;
    }

    if (result is! Map || result['purchase_id']?.toString() != purchaseId) {
      throw StateError('Secure buy-in returned an invalid commit response.');
    }
    await _cacheSecureBuyin(
      purchase: purchase,
      unitId: unitId,
      sku: sku,
      committedQuantity: (result['quantity'] as num?)?.toInt(),
    );
    return purchase;
  }

  Future<void> _cacheSecureBuyin({
    required CustomerPurchaseModel purchase,
    required String unitId,
    required String sku,
    Map<String, dynamic>? payload,
    int? committedQuantity,
    bool queueForSync = false,
  }) async {
    List<ProductModel> cachedProducts = const [];
    try {
      cachedProducts = await OfflineStore.loadProducts(purchase.branchId);
    } catch (error) {
      debugPrint('Secure buy-in product cache read failed: $error');
    }
    final matches = cachedProducts.where((p) => p.id == purchase.productId);
    final existing = matches.isEmpty ? null : matches.first;
    final cleanImei = purchase.imei1.trim();
    final product = ProductModel(
      id: purchase.productId,
      tenantId: existing?.tenantId ?? purchase.tenantId,
      branchId: existing?.branchId ?? purchase.branchId,
      categoryId: existing?.categoryId ?? purchase.categoryId,
      name: existing?.name ?? purchase.productName,
      salePrice: existing?.salePrice ?? purchase.expectedSalePrice,
      costPrice: existing?.costPrice ?? purchase.purchasePrice,
      barcode: existing?.barcode ?? cleanImei,
      sku: existing?.sku ?? sku,
      imeiTracked: true,
      isActive: true,
      stock: committedQuantity ?? ((existing?.stock ?? 0) + 1),
      reorderThreshold: existing?.reorderThreshold ?? 0,
    );
    try {
      await OfflineStore.upsertCachedProduct(product);
    } catch (error) {
      debugPrint('Secure buy-in product cache update failed: $error');
    }

    final now = DateTime.now();
    final unit = InventoryUnitModel(
      id: unitId,
      tenantId: purchase.tenantId,
      branchId: purchase.branchId,
      productId: purchase.productId,
      imei: cleanImei,
      status: InventoryUnitStatus.available,
      createdAt: purchase.createdAt,
      updatedAt: now,
    );
    try {
      await OfflineStore.upsertInventoryUnit(unit);
    } catch (error) {
      debugPrint('Secure buy-in unit cache update failed: $error');
    }

    final accountId = purchase.paymentAccountId;
    if (accountId != null &&
        accountId.isNotEmpty &&
        purchase.purchasePrice > 0) {
      final transaction = AccountTransactionModel(
        id: const Uuid().v5(
          Namespace.url.value,
          'customer-buyin:${purchase.id}',
        ),
        tenantId: purchase.tenantId,
        branchId: purchase.branchId,
        accountId: accountId,
        type: AccountTransactionType.purchase,
        direction: AccountTransactionDirection.moneyOut,
        amount: purchase.purchasePrice,
        description:
            'Second-hand mobile buy-in ${purchase.productName} (IMEI: $cleanImei)',
        referenceType: 'customer_buyin',
        referenceId: purchase.id,
        sourceEventKey: 'customer_buyin:${purchase.id}',
        transactionAt: purchase.createdAt,
        createdBy: purchase.createdBy,
        createdAt: purchase.createdAt,
      );
      try {
        await AccountsLocalStore.applyTransaction(transaction);
      } catch (error) {
        debugPrint('Secure buy-in local ledger update skipped: $error');
      }
    }

    try {
      await OfflineStore.saveCustomerPurchase(purchase);
    } catch (error) {
      debugPrint('Secure buy-in purchase cache update failed: $error');
    }

    if (queueForSync && payload != null) {
      await OfflineStore.enqueueMutation(
        userId: purchase.createdBy,
        type: 'commit_customer_buyin_v2',
        payload: payload,
      );
    }
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

      final remoteList =
          (rows as List)
              .map(
                (r) => CustomerPurchaseModel.fromMap(
                  Map<String, dynamic>.from(r as Map),
                ),
              )
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
    final buyinMutations =
        mutations
            .where(
              (m) =>
                  m.type == 'create_customer_buyin' ||
                  m.type == 'commit_customer_buyin_v2' ||
                  m.type == 'delete_customer_buyin' ||
                  m.type == 'update_customer_buyin_status',
            )
            .toList();
    if (buyinMutations.isEmpty) return;

    final remaining = <OfflineMutation>[];
    final random = Random();

    for (final mutation in mutations) {
      if (mutation.type != 'create_customer_buyin' &&
          mutation.type != 'commit_customer_buyin_v2' &&
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
              .update({
                'status': status,
                'updated_at': DateTime.now().toIso8601String(),
              })
              .eq('id', id)
              .timeout(_networkTimeout);
        } else {
          final payload = Map<String, dynamic>.from(mutation.payload);
          if (mutation.type == 'commit_customer_buyin_v2') {
            try {
              final result = await _client
                  .rpc('commit_customer_buyin_v2', params: {'p_buyin': payload})
                  .timeout(_networkTimeout);
              if (result is! Map ||
                  result['purchase_id']?.toString() !=
                      payload['id']?.toString()) {
                throw StateError(
                  'Secure buy-in retry returned an invalid response.',
                );
              }
              await _cacheSecureBuyin(
                purchase: CustomerPurchaseModel.fromMap(payload),
                unitId: payload['inventory_unit_id'] as String,
                sku: payload['sku'] as String? ?? '',
                committedQuantity: (result['quantity'] as num?)?.toInt(),
              );
              continue;
            } on PostgrestException catch (error) {
              if (!isMissingSecureRpc(
                error,
                'commit_customer_buyin_v2',
                argumentName: 'p_buyin',
              )) {
                rethrow;
              }
              await _syncLegacyBuyinPayload(payload);
              continue;
            }
          }
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
                await _client
                    .from('products')
                    .upsert({
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
                    }, onConflict: 'id')
                    .timeout(_networkTimeout);

                await _client
                    .from('inventory')
                    .upsert({
                      'branch_id': p.branchId,
                      'product_id': p.id,
                      'quantity': p.stock,
                    }, onConflict: 'branch_id,product_id')
                    .timeout(_networkTimeout);
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

  Future<void> _syncLegacyBuyinPayload(Map<String, dynamic> payload) async {
    final branchId = payload['branch_id'] as String;
    final productId = payload['product_id'] as String;
    final imei = payload['imei1'] as String? ?? '';
    final products = await OfflineStore.loadProducts(branchId);
    final matches = products.where((p) => p.id == productId);
    if (matches.isNotEmpty) {
      final product = matches.first;
      await _client
          .from('products')
          .upsert({
            'id': product.id,
            'tenant_id': product.tenantId,
            'branch_id': product.branchId,
            'category_id': product.categoryId,
            'name': product.name,
            'sale_price': product.salePrice,
            'cost_price': product.costPrice,
            'barcode': product.barcode,
            'sku': product.sku,
            'imei_tracked': product.imeiTracked,
            'is_active': product.isActive,
          }, onConflict: 'id')
          .timeout(_networkTimeout);
      await _client
          .from('inventory')
          .upsert({
            'branch_id': product.branchId,
            'product_id': product.id,
            'quantity': product.stock,
          }, onConflict: 'branch_id,product_id')
          .timeout(_networkTimeout);
    }

    final unit = await OfflineStore.loadInventoryUnitByImei(
      branchId: branchId,
      imei: imei,
    );
    if (unit != null) {
      await _client
          .from('inventory_units')
          .upsert(unit.toMap(), onConflict: 'id')
          .timeout(_networkTimeout);
    }

    final paymentAccountId = payload['payment_account_id'] as String?;
    final purchasePrice = (payload['purchase_price'] as num?)?.toDouble() ?? 0;
    if (paymentAccountId != null &&
        paymentAccountId.isNotEmpty &&
        purchasePrice > 0) {
      await _client
          .rpc(
            'record_account_transaction',
            params: {
              'p_account_id': paymentAccountId,
              'p_type': 'purchase',
              'p_direction': 'out',
              'p_amount': purchasePrice,
              'p_description':
                  'Second-Hand Mobile Buy-In: ${payload['product_name']} (IMEI: $imei) from ${payload['seller_name']}',
              'p_reference_type': 'customer_buyin',
              'p_reference_id': payload['id'],
              'p_source_event_key': 'customer_buyin:${payload['id']}',
              'p_transaction_at': payload['created_at'],
            },
          )
          .timeout(_networkTimeout);
    }

    final purchaseRow =
        Map<String, dynamic>.from(payload)
          ..remove('inventory_unit_id')
          ..remove('create_product')
          ..remove('sku');
    await _client
        .from('customer_purchases')
        .upsert(purchaseRow, onConflict: 'id')
        .timeout(_networkTimeout);
  }
}
