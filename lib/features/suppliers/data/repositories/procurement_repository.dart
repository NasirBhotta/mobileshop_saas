import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:mobileshop_saas/core/offline/offline_store.dart';
import 'package:mobileshop_saas/features/suppliers/data/local/procurement_local_store.dart';
import 'package:mobileshop_saas/features/suppliers/data/models/procurement_models.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

class ProcurementRepository {
  static const _networkTimeout = Duration(milliseconds: 1200);

  final SupabaseClient _client = Supabase.instance.client;

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
    final tenantId = await _tenantId();

    final cached = await ProcurementLocalStore.loadSuppliers(tenantId);
    if (cached.isNotEmpty) {
      unawaited(_refreshSuppliers(tenantId));
      unawaited(syncOfflineMutations());
      return cached;
    }

    try {
      return await _fetchRemoteSuppliers(tenantId).timeout(_networkTimeout);
    } catch (_) {
      return ProcurementLocalStore.loadSuppliers(tenantId);
    }
  }

  Future<void> _refreshSuppliers(String tenantId) async {
    try {
      await _fetchRemoteSuppliers(tenantId).timeout(_networkTimeout);
    } catch (_) {}
  }

  Future<List<SupplierModel>> _fetchRemoteSuppliers(String tenantId) async {
    final data = await _client
        .from('suppliers')
        .select()
        .eq('tenant_id', tenantId)
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
    final tenantId = await _tenantId();
    final branchId = await _branchId(tenantId);

    final cached = await ProcurementLocalStore.loadPurchaseOrders(
      branchId,
      status: status,
    );

    if (cached.isNotEmpty) {
      unawaited(_refreshPurchaseOrders(tenantId, branchId, status: status));
      unawaited(syncOfflineMutations());
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

  Future<PurchaseOrderModel?> fetchPurchaseOrderById(String poId) async {
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
      await OfflineStore.enqueueMutation(
        userId: _currentUser.id,
        type: 'mark_po_sent',
        payload: {'po_id': po.id},
      );
      debugPrint('PO sent offline: $e');
    }
  }

  Future<void> receiveGoods({
    required PurchaseOrderModel po,
    String? note,
    required List<GoodsReceiptItemInput> inputs,
  }) async {
    final receiptId = const Uuid().v4();
    final receiptNo = _generateNo('GR', receiptId, DateTime.now());

    await ProcurementLocalStore.applyReceiptLocally(
      po: po,
      receiptId: receiptId,
      receiptNo: receiptNo,
      userId: _currentUser.id,
      note: _clean(note),
      inputs: inputs,
    );

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
    String? method,
    String? note,
  }) async {
    if (amount <= 0) throw Exception('Amount must be greater than zero.');

    final tenantId = await _tenantId();
    final branchId = await _branchId(tenantId);
    final now = DateTime.now();

    final payment = SupplierPaymentModel(
      id: const Uuid().v4(),
      tenantId: tenantId,
      branchId: branchId,
      supplierId: supplier.id,
      amount: amount,
      method: _clean(method),
      note: _clean(note),
      paidBy: _currentUser.id,
      paidAt: now,
      createdAt: now,
    );

    await ProcurementLocalStore.saveSupplierPayment(payment);

    try {
      await _client
          .rpc(
            'record_supplier_payment',
            params: {
              'p_payment_id': payment.id,
              'p_tenant_id': tenantId,
              'p_branch_id': branchId,
              'p_supplier_id': supplier.id,
              'p_amount': amount,
              'p_method': _clean(method),
              'p_note': _clean(note),
            },
          )
          .timeout(_networkTimeout);
    } catch (e) {
      await OfflineStore.enqueueMutation(
        userId: _currentUser.id,
        type: 'record_supplier_payment',
        payload: payment.toMap(),
      );
      debugPrint('Supplier payment saved offline: $e');
    }
  }

  Future<void> syncOfflineMutations() async {
    final userId = _currentUser.id;
    final mutations = await OfflineStore.loadMutations(userId);
    if (mutations.isEmpty) return;

    final remaining = <OfflineMutation>[];

    for (final mutation in mutations) {
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

          case 'record_supplier_payment':
            await _client.rpc(
              'record_supplier_payment',
              params: {
                'p_payment_id': mutation.payload['id'],
                'p_tenant_id': mutation.payload['tenant_id'],
                'p_branch_id': mutation.payload['branch_id'],
                'p_supplier_id': mutation.payload['supplier_id'],
                'p_amount': mutation.payload['amount'],
                'p_method': mutation.payload['method'],
                'p_note': mutation.payload['note'],
              },
            );
            break;

          default:
            remaining.add(mutation);
        }
      } catch (e) {
        debugPrint('Procurement sync failed: $e');
        remaining.add(mutation);
      }
    }

    await OfflineStore.saveMutations(userId, remaining);
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
}
