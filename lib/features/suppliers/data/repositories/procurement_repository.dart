import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:mobileshop_saas/core/entitlements/entitlement_evaluator.dart';
import 'package:mobileshop_saas/core/entitlements/supabase_entitlement_data_source.dart';
import 'package:mobileshop_saas/core/local/local_database.dart';
import 'package:mobileshop_saas/core/offline/offline_store.dart';
import 'package:mobileshop_saas/core/utils/offline_error_classifier.dart';
import 'package:mobileshop_saas/core/utils/network.dart';
import 'package:mobileshop_saas/features/suppliers/data/local/procurement_local_store.dart';
import 'package:mobileshop_saas/features/suppliers/data/local/supplier_payment_local_committer.dart';
import 'package:mobileshop_saas/features/suppliers/data/models/procurement_models.dart';
import 'package:mobileshop_saas/features/suppliers/data/models/supplier_sales_analytics_models.dart';
import 'package:mobileshop_saas/features/suppliers/domain/procurement_entitlement_gate.dart';
import 'package:mobileshop_saas/features/suppliers/domain/supplier_accounting_contract.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

class ProcurementRepository {
  // Procurement RPCs perform multiple transactional writes. A 1.2 second
  // timeout was short enough to classify successful server commits as offline.
  static const _networkTimeout = Duration(seconds: 8);
  static Future<void>? _procurementSyncInFlight;

  final SupabaseClient _client;
  final ProcurementEntitlementGate _entitlements;

  ProcurementRepository({
    SupabaseClient? client,
    EntitlementEvaluator? entitlementEvaluator,
  }) : _client = client ?? Supabase.instance.client,
       _entitlements = ProcurementEntitlementGate(
         entitlementEvaluator ??
             EntitlementEvaluator(
               dataSource: SupabaseEntitlementDataSource(client: client),
             ),
       );

  User get _currentUser {
    final user = _client.auth.currentUser;
    if (user == null) throw Exception('User not logged in');
    return user;
  }

  Future<Map<String, dynamic>> _currentProfile() async {
    final cached = await OfflineStore.loadProfile(_currentUser.id);
    if (cached != null) return cached;

    final profile = await _client
        .from('users')
        .select('id, tenant_id, branch_id')
        .eq('id', _currentUser.id)
        .maybeSingle()
        .timeout(_networkTimeout);

    if (profile == null) throw Exception('User profile not found');

    final selectedBranchId = await OfflineStore.loadSelectedBranchId(
      _currentUser.id,
    );
    if (selectedBranchId != null) profile['branch_id'] = selectedBranchId;

    await OfflineStore.saveProfile(_currentUser.id, profile);
    return profile;
  }

  Future<String> _tenantId() async {
    final profile = await _currentProfile();
    final id = profile['tenant_id'] as String?;
    if (id == null) throw Exception('Tenant not found');
    return id;
  }

  Future<String> _branchId(String tenantId) async {
    final profile = await _currentProfile();
    final selected = profile['branch_id'] as String?;
    if (selected != null) return selected;

    final branches = await OfflineStore.loadBranches(tenantId);
    if (branches.isNotEmpty && branches.first.id != null) {
      return branches.first.id!;
    }

    final branch = await _client
        .from('branches')
        .select('id')
        .eq('tenant_id', tenantId)
        .limit(1)
        .maybeSingle()
        .timeout(_networkTimeout);

    final id = branch?['id'] as String?;
    if (id == null) throw Exception('Branch not found');
    return id;
  }

  Future<SupplierModel> createSupplier({
    required String name,
    String? contactPerson,
    String? phone,
    String? email,
    String? address,
    String? city,
    String? paymentTerms,
    String? notes,
  }) async {
    await _entitlements.require('procurement.suppliers');
    final tenantId = await _tenantId();
    final branchId = await _branchId(tenantId);

    final now = DateTime.now();

    final supplier = SupplierModel(
      id: const Uuid().v4(),
      tenantId: tenantId,
      branchId: branchId,
      name: name.trim(),
      contactPerson: _clean(contactPerson),
      phone: _clean(phone),
      email: _clean(email),
      address: _clean(address),
      city: _clean(city),
      paymentTerms: _clean(paymentTerms),
      notes: _clean(notes),
      createdBy: _currentUser.id,
      createdAt: now,
      updatedAt: now,
    );

    await ProcurementLocalStore.saveSupplier(supplier);

    try {
      final data = await _client
          .from('suppliers')
          .insert(supplier.toMap())
          .select()
          .single()
          .timeout(_networkTimeout);

      final saved = SupplierModel.fromMap(data);
      await ProcurementLocalStore.saveSupplier(saved);
      return saved;
    } catch (e) {
      OfflineErrorClassifier.rethrowIfTerminal(e);
      await OfflineStore.enqueueMutation(
        userId: _currentUser.id,
        type: 'upsert_supplier',
        payload: supplier.toMap(),
      );
      debugPrint('Supplier saved offline: $e');
      return supplier;
    }
  }

  Future<List<SupplierModel>> fetchSuppliers() async {
    await _entitlements.require('procurement.suppliers');
    final tenantId = await _tenantId();
    final branchId = await _branchId(tenantId);

    final cached = await ProcurementLocalStore.loadSuppliers(
      tenantId,
      branchId,
    );
    if (cached.isNotEmpty) {
      unawaited(_syncThenRefreshSuppliers(tenantId, branchId));
      return cached;
    }

    try {
      return await _fetchRemoteSuppliers(
        tenantId,
        branchId,
      ).timeout(_networkTimeout);
    } catch (_) {
      return ProcurementLocalStore.loadSuppliers(tenantId, branchId);
    }
  }

  Future<void> _syncThenRefreshSuppliers(
    String tenantId,
    String branchId,
  ) async {
    await syncOfflineMutations();
    if (await _hasPendingProcurementMutations()) return;
    await _refreshSuppliers(tenantId, branchId);
  }

  Future<SupplierOverviewModel> fetchSupplierOverview(
    SupplierModel supplier,
  ) async {
    await _entitlements.require('procurement.suppliers');
    final branchId = await _branchId(supplier.tenantId);

    try {
      await _fetchRemotePurchaseOrders(
        supplier.tenantId,
        branchId,
      ).timeout(_networkTimeout);
      final rows = await _client
          .from('supplier_ledger_entries')
          .select()
          .eq('tenant_id', supplier.tenantId)
          .eq('branch_id', branchId)
          .eq('supplier_id', supplier.id)
          .order('occurred_at', ascending: false)
          .timeout(_networkTimeout);
      for (final row in rows as List) {
        await ProcurementLocalStore.saveSupplierLedgerEntry(
          SupplierLedgerEntryModel.fromMap(row),
        );
      }
      final paymentRows = await _client
          .from('supplier_payments')
          .select()
          .eq('tenant_id', supplier.tenantId)
          .eq('branch_id', branchId)
          .eq('supplier_id', supplier.id)
          .order('paid_at', ascending: false)
          .timeout(_networkTimeout);
      for (final row in paymentRows as List) {
        await ProcurementLocalStore.saveSupplierPayment(
          SupplierPaymentModel.fromMap(row),
        );
      }
    } catch (error) {
      OfflineErrorClassifier.rethrowIfTerminal(error);
      debugPrint('Supplier overview using offline data: $error');
    }

    final orders = await ProcurementLocalStore.loadPurchaseOrders(branchId);
    final ledger = await ProcurementLocalStore.loadSupplierLedger(supplier.id);
    final payments = await ProcurementLocalStore.loadSupplierPayments(
      supplier.id,
    );
    final currentSupplier =
        await ProcurementLocalStore.loadSupplierById(supplier.id) ?? supplier;
    return SupplierOverviewModel(
      supplier: currentSupplier,
      purchaseOrders:
          orders.where((order) => order.supplierId == supplier.id).toList(),
      ledgerEntries: ledger,
      payments: payments,
    );
  }

  /// Reads only the already-synced supplier payment prerequisites.
  ///
  /// The payment dialog must remain instant when there is no connection, so it
  /// must not wait for the history screen's remote refresh path.
  Future<SupplierOverviewModel> loadCachedSupplierOverview(
    SupplierModel supplier,
  ) async {
    final branchId = supplier.branchId ?? await _branchId(supplier.tenantId);
    final orders = await ProcurementLocalStore.loadPurchaseOrders(branchId);
    final ledger = await ProcurementLocalStore.loadSupplierLedger(supplier.id);
    final payments = await ProcurementLocalStore.loadSupplierPayments(
      supplier.id,
    );
    final currentSupplier =
        await ProcurementLocalStore.loadSupplierById(supplier.id) ?? supplier;
    return SupplierOverviewModel(
      supplier: currentSupplier,
      purchaseOrders:
          orders.where((order) => order.supplierId == supplier.id).toList(),
      ledgerEntries: ledger,
      payments: payments,
    );
  }

  Future<SupplierSalesAnalyticsModel> fetchSupplierSalesAnalytics(
    SupplierModel supplier, {
    int? days,
  }) async {
    await _entitlements.require('procurement.suppliers');
    final branchId = await _branchId(supplier.tenantId);
    final since =
        days == null ? null : DateTime.now().subtract(Duration(days: days));

    final linkRows = await _client
        .from('supplier_products')
        .select(
          'product_id, supplier_sku, last_cost, '
          'products!inner(id, name, sku, branch_id)',
        )
        .eq('tenant_id', supplier.tenantId)
        .eq('supplier_id', supplier.id);

    final links =
        (linkRows as List).where((row) {
          final product = row['products'] as Map<String, dynamic>?;
          return product?['branch_id'] == branchId;
        }).toList();
    if (links.isEmpty) {
      return SupplierSalesAnalyticsModel.empty(since: since);
    }

    final productIds = links.map((row) => row['product_id'] as String).toList();
    final stockRows = await _client
        .from('inventory')
        .select('product_id, quantity')
        .eq('branch_id', branchId)
        .inFilter('product_id', productIds);
    final stockByProduct = <String, int>{
      for (final row in stockRows as List)
        row['product_id'] as String: (row['quantity'] as num?)?.toInt() ?? 0,
    };

    var salesQuery = _client
        .from('sales')
        .select(
          'created_at, sale_items(product_id, quantity, line_total, '
          'cogs_total, unit_cost_at_sale)',
        )
        .eq('branch_id', branchId)
        .eq('status', 'completed');
    if (since != null) {
      salesQuery = salesQuery.gte('created_at', since.toIso8601String());
    }
    final saleRows = await salesQuery;

    final soldByProduct = <String, int>{};
    final revenueByProduct = <String, double>{};
    final costByProduct = <String, double>{};
    final linkedIds = productIds.toSet();
    for (final sale in saleRows as List) {
      for (final rawItem in (sale['sale_items'] as List? ?? const [])) {
        final item = rawItem as Map<String, dynamic>;
        final productId = item['product_id'] as String?;
        if (productId == null || !linkedIds.contains(productId)) continue;
        final quantity = (item['quantity'] as num?)?.toInt() ?? 0;
        final revenue = (item['line_total'] as num?)?.toDouble() ?? 0;
        final unitCost = (item['unit_cost_at_sale'] as num?)?.toDouble() ?? 0;
        final cost =
            (item['cogs_total'] as num?)?.toDouble() ?? unitCost * quantity;
        soldByProduct.update(
          productId,
          (value) => value + quantity,
          ifAbsent: () => quantity,
        );
        revenueByProduct.update(
          productId,
          (value) => value + revenue,
          ifAbsent: () => revenue,
        );
        costByProduct.update(
          productId,
          (value) => value + cost,
          ifAbsent: () => cost,
        );
      }
    }

    final products =
        links.map((row) {
            final product = row['products'] as Map<String, dynamic>;
            final productId = row['product_id'] as String;
            return SupplierProductAnalyticsModel(
              productId: productId,
              productName: product['name'] as String? ?? 'Unnamed product',
              sku: (row['supplier_sku'] ?? product['sku']) as String?,
              lastPurchaseCost: (row['last_cost'] as num?)?.toDouble() ?? 0,
              stockOnHand: stockByProduct[productId] ?? 0,
              soldQuantity: soldByProduct[productId] ?? 0,
              salesRevenue: revenueByProduct[productId] ?? 0,
              costOfSales: costByProduct[productId] ?? 0,
            );
          }).toList()
          ..sort((a, b) => b.salesRevenue.compareTo(a.salesRevenue));

    return SupplierSalesAnalyticsModel(
      products: products,
      linkedProductCount: products.length,
      soldQuantity: products.fold(
        0,
        (total, item) => total + item.soldQuantity,
      ),
      revenue: products.fold(0, (total, item) => total + item.salesRevenue),
      costOfSales: products.fold(0, (total, item) => total + item.costOfSales),
      since: since,
    );
  }

  Future<void> _refreshSuppliers(String tenantId, String branchId) async {
    try {
      await _fetchRemoteSuppliers(tenantId, branchId).timeout(_networkTimeout);
    } catch (_) {}
  }

  Future<void> refreshCurrentSuppliersCache({
    Duration timeout = _networkTimeout,
  }) async {
    final tenantId = await _tenantId();
    final branchId = await _branchId(tenantId);
    await _fetchRemoteSuppliers(tenantId, branchId).timeout(timeout);
  }

  Future<List<SupplierModel>> _fetchRemoteSuppliers(
    String tenantId,
    String branchId,
  ) async {
    final data = await _client
        .from('suppliers')
        .select()
        .eq('tenant_id', tenantId)
        .eq('branch_id', branchId)
        .eq('is_active', true)
        .order('name');

    final suppliers =
        (data as List).map((e) => SupplierModel.fromMap(e)).toList();

    for (final supplier in suppliers) {
      await ProcurementLocalStore.saveSupplier(supplier);
    }

    return suppliers;
  }

  Future<PurchaseOrderModel> createPurchaseOrder({
    required String supplierId,
    DateTime? expectedDeliveryAt,
    String? notes,
    required List<PurchaseOrderItemModel> items,
  }) async {
    await _entitlements.require('procurement.purchase_orders');
    if (items.isEmpty) throw Exception('Add at least one product.');

    final tenantId = await _tenantId();
    final branchId = await _branchId(tenantId);

    final now = DateTime.now();
    final poId = const Uuid().v4();
    final poNo = _generateNo('PO', poId, now);

    final total = items.fold<double>(0, (sum, item) => sum + item.lineTotal);

    final normalizedItems =
        items
            .map(
              (item) => PurchaseOrderItemModel(
                id: item.id,
                tenantId: tenantId,
                purchaseOrderId: poId,
                productId: item.productId,
                productResolution: item.productResolution,
                productDraft: item.productDraft,
                resolvedProductId:
                    item.resolvedProductId ??
                    (item.productResolution ==
                            PurchaseProductResolution.createOnReceipt
                        ? const Uuid().v4()
                        : null),
                productName: item.productName,
                productSku: item.productSku,
                orderedQuantity: item.orderedQuantity,
                negotiatedUnitCost: item.negotiatedUnitCost,
                lineTotal: item.orderedQuantity * item.negotiatedUnitCost,
                createdAt: now,
              ),
            )
            .toList();

    final po = PurchaseOrderModel(
      id: poId,
      tenantId: tenantId,
      branchId: branchId,
      supplierId: supplierId,
      poNo: poNo,
      status: PurchaseOrderStatus.draft,
      expectedDeliveryAt: expectedDeliveryAt,
      notes: _clean(notes),
      totalExpectedCost: total,
      createdBy: _currentUser.id,
      createdAt: now,
      updatedAt: now,
      items: normalizedItems,
    );

    await ProcurementLocalStore.savePurchaseOrder(po);

    try {
      await _client
          .rpc(
            'create_purchase_order',
            params: {
              'p_po_id': po.id,
              'p_po_no': po.poNo,
              'p_tenant_id': tenantId,
              'p_branch_id': branchId,
              'p_supplier_id': supplierId,
              'p_expected_delivery_at': expectedDeliveryAt?.toIso8601String(),
              'p_notes': _clean(notes),
              'p_items': normalizedItems.map((e) => e.toRpcMap()).toList(),
            },
          )
          .timeout(_networkTimeout);

      final saved = await fetchPurchaseOrderById(po.id);
      return saved ?? po;
    } catch (e) {
      OfflineErrorClassifier.rethrowIfTerminal(e);
      await OfflineStore.enqueueMutation(
        userId: _currentUser.id,
        type: 'create_purchase_order',
        payload: {
          'po': po.toMap(),
          'items': normalizedItems.map((e) => e.toMap()).toList(),
        },
      );
      debugPrint('PO saved offline: $e');
      return po;
    }
  }

  Future<List<PurchaseOrderModel>> fetchPurchaseOrders({
    PurchaseOrderStatus? status,
  }) async {
    await _entitlements.require('procurement.purchase_orders');
    final tenantId = await _tenantId();
    final branchId = await _branchId(tenantId);

    final cached = await ProcurementLocalStore.loadPurchaseOrders(
      branchId,
      status: status,
    );

    if (cached.isNotEmpty) {
      unawaited(
        _syncThenRefreshPurchaseOrders(tenantId, branchId, status: status),
      );
      return cached;
    }

    try {
      return await _fetchRemotePurchaseOrders(
        tenantId,
        branchId,
        status: status,
      ).timeout(_networkTimeout);
    } catch (_) {
      return ProcurementLocalStore.loadPurchaseOrders(branchId, status: status);
    }
  }

  Future<void> _syncThenRefreshPurchaseOrders(
    String tenantId,
    String branchId, {
    PurchaseOrderStatus? status,
  }) async {
    await syncOfflineMutations();
    if (await _hasPendingProcurementMutations()) return;
    await _refreshPurchaseOrders(tenantId, branchId, status: status);
  }

  Future<bool> _hasPendingProcurementMutations() async {
    const types = {
      'upsert_supplier',
      'create_purchase_order',
      'mark_po_sent',
      'receive_po_goods',
      'record_supplier_payment',
      'reverse_purchase_order',
    };
    final pending = await OfflineStore.loadMutations(_currentUser.id);
    return pending.any((mutation) => types.contains(mutation.type));
  }

  Future<PurchaseOrderModel?> fetchPurchaseOrderById(String poId) async {
    await _entitlements.require('procurement.purchase_orders');
    try {
      final poRows = await _client
          .from('purchase_orders')
          .select()
          .eq('id', poId)
          .limit(1);

      if ((poRows as List).isEmpty) {
        return ProcurementLocalStore.loadPurchaseOrderById(poId);
      }

      final itemRows = await _client
          .from('purchase_order_items')
          .select()
          .eq('purchase_order_id', poId)
          .order('created_at');

      final items =
          (itemRows as List)
              .map((e) => PurchaseOrderItemModel.fromMap(e))
              .toList();

      final po = PurchaseOrderModel.fromMap(poRows.first, items: items);
      await ProcurementLocalStore.savePurchaseOrder(po);
      return po;
    } catch (_) {
      return ProcurementLocalStore.loadPurchaseOrderById(poId);
    }
  }

  Future<void> _refreshPurchaseOrders(
    String tenantId,
    String branchId, {
    PurchaseOrderStatus? status,
  }) async {
    try {
      await _fetchRemotePurchaseOrders(tenantId, branchId, status: status);
    } catch (_) {}
  }

  Future<void> refreshCurrentPurchaseOrdersCache({
    PurchaseOrderStatus? status,
    Duration timeout = _networkTimeout,
  }) async {
    final tenantId = await _tenantId();
    final branchId = await _branchId(tenantId);
    await _fetchRemotePurchaseOrders(
      tenantId,
      branchId,
      status: status,
    ).timeout(timeout);
  }

  Future<List<PurchaseOrderModel>> _fetchRemotePurchaseOrders(
    String tenantId,
    String branchId, {
    PurchaseOrderStatus? status,
  }) async {
    final base = _client
        .from('purchase_orders')
        .select()
        .eq('tenant_id', tenantId)
        .eq('branch_id', branchId);

    final poRows =
        status == null
            ? await base.order('created_at', ascending: false)
            : await base
                .eq('status', status.code)
                .order('created_at', ascending: false);

    final result = <PurchaseOrderModel>[];

    for (final row in poRows as List) {
      final itemRows = await _client
          .from('purchase_order_items')
          .select()
          .eq('purchase_order_id', row['id'])
          .order('created_at');

      final items =
          (itemRows as List)
              .map((e) => PurchaseOrderItemModel.fromMap(e))
              .toList();

      final po = PurchaseOrderModel.fromMap(row, items: items);
      await ProcurementLocalStore.savePurchaseOrder(po);
      result.add(po);
    }

    return result;
  }

  Future<void> markPurchaseOrderSent(PurchaseOrderModel po) async {
    await _entitlements.require('procurement.purchase_orders');
    final updated = po.copyWith(
      status: PurchaseOrderStatus.sent,
      sentAt: DateTime.now(),
    );

    await ProcurementLocalStore.markPurchaseOrderSent(updated);

    try {
      await _client
          .from('purchase_orders')
          .update({
            'status': PurchaseOrderStatus.sent.code,
            'sent_at': DateTime.now().toIso8601String(),
          })
          .eq('id', po.id)
          .timeout(_networkTimeout);
    } catch (e) {
      OfflineErrorClassifier.rethrowIfTerminal(e);
      await OfflineStore.enqueueMutation(
        userId: _currentUser.id,
        type: 'mark_po_sent',
        payload: {'po_id': po.id},
      );
      debugPrint('PO sent offline: $e');
    }
  }

  Future<void> reversePurchaseOrder({
    required PurchaseOrderModel po,
    required String resolution,
    required String reason,
    String? recoveryAccountId,
  }) async {
    await _entitlements.require('procurement.purchase_orders');
    if (reason.trim().isEmpty) {
      throw Exception('Cancellation/return reason is required.');
    }
    final reversalId = const Uuid().v4();
    final recoveryLedgerId =
        resolution == 'supplier_refund' ? const Uuid().v4() : null;
    try {
      await _client
          .rpc(
            'reverse_purchase_order_v2',
            params: {
              'p_po_id': po.id,
              'p_reversal_id': reversalId,
              'p_resolution': resolution,
              'p_reason': reason.trim(),
              'p_recovery_account_id': recoveryAccountId,
              'p_recovery_ledger_transaction_id': recoveryLedgerId,
            },
          )
          .timeout(_networkTimeout);
    } catch (error) {
      OfflineErrorClassifier.rethrowIfTerminal(error);
      throw StateError(
        'Purchase order cancellation/return needs internet so stock, payable '
        'and any refund can be reversed atomically.',
      );
    }
    await ProcurementLocalStore.reconcileReversedPurchaseOrderInventory(
      purchaseOrderId: po.id,
      branchId: po.branchId,
    );
    try {
      await fetchPurchaseOrderById(po.id);
    } catch (error) {
      // The atomic RPC has already committed. A follow-up cache refresh must
      // not report the completed reversal itself as failed.
      debugPrint('PO reversed; follow-up cache refresh failed: $error');
    }
  }

  Future<double> loadPaidForPurchaseOrder(String purchaseOrderId) async {
    final payments = await LocalDatabase.select(
      'SELECT COALESCE(SUM(amount), 0) AS paid '
      'FROM supplier_payments WHERE purchase_order_id = ?',
      [purchaseOrderId],
    );
    return (payments.first['paid'] as num?)?.toDouble() ?? 0;
  }

  Future<void> receiveGoods({
    required PurchaseOrderModel po,
    String? note,
    required List<GoodsReceiptItemInput> inputs,
  }) async {
    await _entitlements.require('procurement.goods_receipts');
    final receiptId = const Uuid().v4();
    final receiptNo = _generateNo('GR', receiptId, DateTime.now());

    try {
      await _client
          .rpc(
            'receive_purchase_order_goods',
            params: {
              'p_receipt_id': receiptId,
              'p_receipt_no': receiptNo,
              'p_po_id': po.id,
              'p_note': _clean(note),
              'p_items': inputs.map((e) => e.toRpcMap()).toList(),
            },
          )
          .timeout(_networkTimeout);

      await fetchPurchaseOrderById(po.id);
    } catch (e) {
      OfflineErrorClassifier.rethrowIfTerminal(e);
      await ProcurementLocalStore.applyReceiptLocally(
        po: po,
        receiptId: receiptId,
        receiptNo: receiptNo,
        userId: _currentUser.id,
        note: _clean(note),
        inputs: inputs,
      );
      await OfflineStore.enqueueMutation(
        userId: _currentUser.id,
        type: 'receive_po_goods',
        payload: {
          'receipt_id': receiptId,
          'receipt_no': receiptNo,
          'po': po.toMap(),
          'items': po.items.map((e) => e.toMap()).toList(),
          'note': _clean(note),
          'inputs': inputs.map((e) => e.toRpcMap()).toList(),
        },
      );
      debugPrint('Goods receipt saved offline: $e');
    }
  }

  Future<void> recordSupplierPayment({
    required SupplierModel supplier,
    required double amount,
    required String accountId,
    required String purchaseOrderId,
    String? method,
    String? note,
  }) async {
    await _entitlements.require('procurement.supplier_payments');
    if (amount <= 0) throw Exception('Amount must be greater than zero.');

    final tenantId = await _tenantId();
    final branchId = await _branchId(tenantId);
    final now = DateTime.now();

    final payment = SupplierPaymentModel(
      id: const Uuid().v4(),
      tenantId: tenantId,
      branchId: branchId,
      supplierId: supplier.id,
      purchaseOrderId: purchaseOrderId,
      amount: amount,
      method: _clean(method),
      accountId: accountId,
      ledgerTransactionId: const Uuid().v4(),
      note: _clean(note),
      paidBy: _currentUser.id,
      paidAt: now,
      createdAt: now,
    );

    await SupplierPaymentLocalCommitter.commit(payment);

    if (!await const NetworkService().hasConnection) {
      await _enqueueSupplierPayment(payment);
      debugPrint('Supplier payment saved offline; remote sync queued.');
      return;
    }

    try {
      await _client
          .rpc(
            'record_supplier_payment_v3',
            params: {
              'p_payment_id': payment.id,
              'p_tenant_id': tenantId,
              'p_branch_id': branchId,
              'p_supplier_id': supplier.id,
              'p_purchase_order_id': purchaseOrderId,
              'p_amount': amount,
              'p_method': _clean(method),
              'p_note': _clean(note),
              'p_account_id': payment.accountId,
              'p_ledger_transaction_id': payment.ledgerTransactionId,
            },
          )
          .timeout(_networkTimeout);
    } catch (e) {
      OfflineErrorClassifier.rethrowIfTerminal(e);
      await _enqueueSupplierPayment(payment);
      debugPrint('Supplier payment saved offline: $e');
    }
  }

  Future<void> _enqueueSupplierPayment(SupplierPaymentModel payment) {
    return OfflineStore.enqueueMutation(
      userId: _currentUser.id,
      type: 'record_supplier_payment',
      payload: payment.toMap(),
    );
  }

  Future<void> syncOfflineMutations() async {
    final running = _procurementSyncInFlight;
    if (running != null) return running;
    final operation = _syncOfflineMutationsInternal();
    _procurementSyncInFlight = operation;
    try {
      await operation;
    } finally {
      if (identical(_procurementSyncInFlight, operation)) {
        _procurementSyncInFlight = null;
      }
    }
  }

  Future<void> _syncOfflineMutationsInternal() async {
    final userId = _currentUser.id;
    final mutations = await OfflineStore.loadMutations(userId);
    if (mutations.isEmpty) return;

    final remaining = <OfflineMutation>[];
    final failedPurchaseOrderIds = <String>{};
    final failedSupplierIds = <String>{};

    for (final mutation in mutations) {
      final dependentPoId = switch (mutation.type) {
        'mark_po_sent' => mutation.payload['po_id'] as String?,
        'reverse_purchase_order' => mutation.payload['po_id'] as String?,
        'receive_po_goods' =>
          (mutation.payload['po'] as Map?)?['id'] as String?,
        'record_supplier_payment' =>
          mutation.payload['purchase_order_id'] as String?,
        _ => null,
      };
      final dependentSupplierId = switch (mutation.type) {
        'create_purchase_order' =>
          (mutation.payload['po'] as Map?)?['supplier_id'] as String?,
        'record_supplier_payment' => mutation.payload['supplier_id'] as String?,
        _ => null,
      };

      // Preserve queue dependency: do not send child mutations when creating
      // their parent PO failed earlier in this sync pass.
      if (dependentPoId != null &&
          failedPurchaseOrderIds.contains(dependentPoId)) {
        remaining.add(mutation);
        continue;
      }
      if (dependentSupplierId != null &&
          failedSupplierIds.contains(dependentSupplierId)) {
        remaining.add(mutation);
        if (dependentPoId != null) {
          failedPurchaseOrderIds.add(dependentPoId);
        }
        continue;
      }

      try {
        switch (mutation.type) {
          case 'upsert_supplier':
            await _client.from('suppliers').upsert(mutation.payload);
            break;

          case 'create_purchase_order':
            final poMap = Map<String, dynamic>.from(
              mutation.payload['po'] as Map,
            );
            final items =
                (mutation.payload['items'] as List)
                    .map((e) => Map<String, dynamic>.from(e as Map))
                    .toList();

            await _client.rpc(
              'create_purchase_order',
              params: {
                'p_po_id': poMap['id'],
                'p_po_no': poMap['po_no'],
                'p_tenant_id': poMap['tenant_id'],
                'p_branch_id': poMap['branch_id'],
                'p_supplier_id': poMap['supplier_id'],
                'p_expected_delivery_at': poMap['expected_delivery_at'],
                'p_notes': poMap['notes'],
                'p_items':
                    items.map((e) {
                      return {
                        'id': e['id'],
                        'product_id': e['product_id'],
                        'product_resolution': e['product_resolution'],
                        'product_draft': e['product_draft'],
                        'resolved_product_id': e['resolved_product_id'],
                        'product_name': e['product_name'],
                        'product_sku': e['product_sku'],
                        'ordered_quantity': e['ordered_quantity'],
                        'negotiated_unit_cost': e['negotiated_unit_cost'],
                      };
                    }).toList(),
              },
            );
            break;

          case 'mark_po_sent':
            await _client
                .from('purchase_orders')
                .update({
                  'status': PurchaseOrderStatus.sent.code,
                  'sent_at': DateTime.now().toIso8601String(),
                })
                .eq('id', mutation.payload['po_id']);
            break;

          case 'receive_po_goods':
            await _client.rpc(
              'receive_purchase_order_goods',
              params: {
                'p_receipt_id': mutation.payload['receipt_id'],
                'p_receipt_no': mutation.payload['receipt_no'],
                'p_po_id': mutation.payload['po']['id'],
                'p_note': mutation.payload['note'],
                'p_items': mutation.payload['inputs'],
              },
            );
            break;

          case 'reverse_purchase_order':
            await _client.rpc(
              'reverse_purchase_order_v2',
              params: {
                'p_po_id': mutation.payload['po_id'],
                'p_reversal_id': mutation.payload['reversal_id'],
                'p_resolution': mutation.payload['resolution'],
                'p_reason': mutation.payload['reason'],
                'p_recovery_account_id':
                    mutation.payload['recovery_account_id'],
                'p_recovery_ledger_transaction_id':
                    mutation.payload['recovery_ledger_transaction_id'],
              },
            );
            break;

          case 'record_supplier_payment':
            await _client.rpc(
              'record_supplier_payment_v3',
              params: {
                'p_payment_id': mutation.payload['id'],
                'p_tenant_id': mutation.payload['tenant_id'],
                'p_branch_id': mutation.payload['branch_id'],
                'p_supplier_id': mutation.payload['supplier_id'],
                'p_purchase_order_id': mutation.payload['purchase_order_id'],
                'p_amount': mutation.payload['amount'],
                'p_method': mutation.payload['method'],
                'p_note': mutation.payload['note'],
                'p_account_id': mutation.payload['account_id'],
                'p_ledger_transaction_id':
                    mutation.payload['ledger_transaction_id'],
              },
            );
            break;

          default:
            remaining.add(mutation);
        }
      } catch (e) {
        debugPrint('Procurement sync failed: $e');
        if (dependentPoId != null) {
          failedPurchaseOrderIds.add(dependentPoId);
        } else if (mutation.type == 'create_purchase_order') {
          final po = mutation.payload['po'] as Map?;
          final poId = po?['id'] as String?;
          if (poId != null) failedPurchaseOrderIds.add(poId);
        }
        if (mutation.type == 'upsert_supplier') {
          final supplierId = mutation.payload['id'] as String?;
          if (supplierId != null) failedSupplierIds.add(supplierId);
        }
        remaining.add(mutation);
      }
    }

    await OfflineStore.saveMutationSyncResult(
      userId: userId,
      snapshot: mutations,
      remaining: remaining,
    );
  }

  String buildPurchaseOrderDocument({
    required PurchaseOrderModel po,
    SupplierModel? supplier,
  }) {
    final buffer = StringBuffer();

    buffer.writeln('PURCHASE ORDER');
    buffer.writeln('PO No: ${po.poNo}');
    buffer.writeln('Status: ${po.status.label}');
    buffer.writeln('Supplier: ${supplier?.name ?? po.supplierId}');
    buffer.writeln('Expected Delivery: ${_dateText(po.expectedDeliveryAt)}');
    buffer.writeln('');
    buffer.writeln('Items:');
    buffer.writeln('----------------------------------------');

    for (final item in po.items) {
      buffer.writeln('${item.productName} (${item.productSku ?? '-'})');
      buffer.writeln('Qty: ${item.orderedQuantity}');
      buffer.writeln(
        'Unit Cost: Rs ${item.negotiatedUnitCost.toStringAsFixed(2)}',
      );
      buffer.writeln('Line Total: Rs ${item.lineTotal.toStringAsFixed(2)}');
      buffer.writeln('----------------------------------------');
    }

    buffer.writeln('');
    buffer.writeln(
      'Total Expected Cost: Rs ${po.totalExpectedCost.toStringAsFixed(2)}',
    );

    if (po.notes != null && po.notes!.trim().isNotEmpty) {
      buffer.writeln('');
      buffer.writeln('Notes: ${po.notes}');
    }

    return buffer.toString();
  }

  String _generateNo(String prefix, String id, DateTime now) {
    final year = now.year.toString().padLeft(4, '0');
    final month = now.month.toString().padLeft(2, '0');
    final day = now.day.toString().padLeft(2, '0');
    final shortId = id.substring(0, 6).toUpperCase();
    return '$prefix-$year$month$day-$shortId';
  }

  String _dateText(DateTime? date) {
    if (date == null) return '-';
    return '${date.day.toString().padLeft(2, '0')}-${date.month.toString().padLeft(2, '0')}-${date.year}';
  }

  String? _clean(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    return trimmed;
  }

  Future<SupplierSalesSummary> fetchSupplierSalesSummary(
    SupplierModel supplier, {
    required SupplierAnalyticsPeriod period,
  }) async {
    await _entitlements.require('procurement.suppliers');
    final branchId = await _branchId(supplier.tenantId);
    return ProcurementLocalStore.loadSupplierSalesSummary(
      supplierId: supplier.id,
      branchId: branchId,
      dateFrom: period.dateFrom,
    );
  }

  Future<SupplierProductSalesPage> fetchSupplierProductSalesPage(
    SupplierModel supplier, {
    required SupplierAnalyticsPeriod period,
    required String search,
    required SupplierProfitFilter profitFilter,
    required SupplierAnalyticsSort sort,
    required int limit,
    required int offset,
  }) async {
    await _entitlements.require('procurement.suppliers');
    final branchId = await _branchId(supplier.tenantId);
    return ProcurementLocalStore.loadSupplierProductSalesPage(
      supplierId: supplier.id,
      branchId: branchId,
      dateFrom: period.dateFrom,
      search: search,
      profitFilter: profitFilter,
      sort: sort,
      limit: limit,
      offset: offset,
    );
  }
}
