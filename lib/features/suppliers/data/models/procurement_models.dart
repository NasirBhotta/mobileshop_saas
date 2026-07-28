import 'dart:convert';

import 'package:mobileshop_saas/features/suppliers/domain/supplier_accounting_contract.dart';

class SupplierModel {
  final String id;
  final String tenantId;
  final String? branchId;
  final String name;
  final String? contactPerson;
  final String? phone;
  final String? email;
  final String? address;
  final String? city;
  final String? paymentTerms;
  final double outstandingBalance;
  final String? notes;
  final bool isActive;
  final String? createdBy;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const SupplierModel({
    required this.id,
    required this.tenantId,
    this.branchId,
    required this.name,
    this.contactPerson,
    this.phone,
    this.email,
    this.address,
    this.city,
    this.paymentTerms,
    this.outstandingBalance = 0,
    this.notes,
    this.isActive = true,
    this.createdBy,
    this.createdAt,
    this.updatedAt,
  });

  factory SupplierModel.fromMap(Map<String, dynamic> map) {
    return SupplierModel(
      id: map['id'] as String,
      tenantId: map['tenant_id'] as String,
      branchId: map['branch_id'] as String?,
      name: map['name'] as String,
      contactPerson: map['contact_person'] as String?,
      phone: map['phone'] as String?,
      email: map['email'] as String?,
      address: map['address'] as String?,
      city: map['city'] as String?,
      paymentTerms: map['payment_terms'] as String?,
      outstandingBalance: (map['outstanding_balance'] as num?)?.toDouble() ?? 0,
      notes: map['notes'] as String?,
      isActive: _bool(map['is_active']),
      createdBy: map['created_by'] as String?,
      createdAt: _date(map['created_at']),
      updatedAt: _date(map['updated_at']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'tenant_id': tenantId,
      'branch_id': branchId,
      'name': name,
      'contact_person': contactPerson,
      'phone': phone,
      'email': email,
      'address': address,
      'city': city,
      'payment_terms': paymentTerms,
      'outstanding_balance': outstandingBalance,
      'notes': notes,
      'is_active': isActive,
      'created_by': createdBy,
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  static DateTime? _date(dynamic value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString());
  }

  static bool _bool(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value.toInt() == 1;
    return value == 'true';
  }
}

enum PurchaseOrderStatus { draft, sent, partiallyReceived, received, cancelled }

extension PurchaseOrderStatusX on PurchaseOrderStatus {
  String get code {
    switch (this) {
      case PurchaseOrderStatus.draft:
        return 'draft';
      case PurchaseOrderStatus.sent:
        return 'sent';
      case PurchaseOrderStatus.partiallyReceived:
        return 'partially_received';
      case PurchaseOrderStatus.received:
        return 'received';
      case PurchaseOrderStatus.cancelled:
        return 'cancelled';
    }
  }

  String get label {
    switch (this) {
      case PurchaseOrderStatus.draft:
        return 'Draft';
      case PurchaseOrderStatus.sent:
        return 'Sent';
      case PurchaseOrderStatus.partiallyReceived:
        return 'Partially Received';
      case PurchaseOrderStatus.received:
        return 'Received';
      case PurchaseOrderStatus.cancelled:
        return 'Cancelled';
    }
  }

  static PurchaseOrderStatus fromCode(String? code) {
    switch (code) {
      case 'sent':
        return PurchaseOrderStatus.sent;
      case 'partially_received':
        return PurchaseOrderStatus.partiallyReceived;
      case 'received':
        return PurchaseOrderStatus.received;
      case 'cancelled':
        return PurchaseOrderStatus.cancelled;
      case 'draft':
      default:
        return PurchaseOrderStatus.draft;
    }
  }
}

class PurchaseOrderItemModel {
  final String id;
  final String tenantId;
  final String purchaseOrderId;
  final String? productId;
  final PurchaseProductResolution productResolution;
  final Map<String, dynamic>? productDraft;
  final String? resolvedProductId;
  final String productName;
  final String? productSku;
  final int orderedQuantity;
  final int receivedQuantity;
  final double negotiatedUnitCost;
  final double? actualUnitCost;
  final double lineTotal;
  final DateTime? createdAt;

  const PurchaseOrderItemModel({
    required this.id,
    required this.tenantId,
    required this.purchaseOrderId,
    required this.productId,
    this.productResolution = PurchaseProductResolution.existingProduct,
    this.productDraft,
    this.resolvedProductId,
    required this.productName,
    this.productSku,
    required this.orderedQuantity,
    this.receivedQuantity = 0,
    required this.negotiatedUnitCost,
    this.actualUnitCost,
    required this.lineTotal,
    this.createdAt,
  });

  int get remainingQuantity => orderedQuantity - receivedQuantity;

  factory PurchaseOrderItemModel.fromMap(Map<String, dynamic> map) {
    return PurchaseOrderItemModel(
      id: map['id'] as String,
      tenantId: map['tenant_id'] as String,
      purchaseOrderId: map['purchase_order_id'] as String,
      productId: map['product_id'] as String?,
      productResolution: PurchaseProductResolutionX.fromCode(
        map['product_resolution'] as String?,
      ),
      productDraft: _jsonMap(map['product_draft'] ?? map['product_draft_json']),
      resolvedProductId: map['resolved_product_id'] as String?,
      productName: map['product_name'] as String,
      productSku: map['product_sku'] as String?,
      orderedQuantity: (map['ordered_quantity'] as num).toInt(),
      receivedQuantity: (map['received_quantity'] as num?)?.toInt() ?? 0,
      negotiatedUnitCost: (map['negotiated_unit_cost'] as num).toDouble(),
      actualUnitCost: (map['actual_unit_cost'] as num?)?.toDouble(),
      lineTotal: (map['line_total'] as num?)?.toDouble() ?? 0,
      createdAt: _date(map['created_at']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'tenant_id': tenantId,
      'purchase_order_id': purchaseOrderId,
      'product_id': productId,
      'product_resolution': productResolution.code,
      'product_draft': productDraft,
      'resolved_product_id': resolvedProductId,
      'product_name': productName,
      'product_sku': productSku,
      'ordered_quantity': orderedQuantity,
      'received_quantity': receivedQuantity,
      'negotiated_unit_cost': negotiatedUnitCost,
      'actual_unit_cost': actualUnitCost,
      'line_total': lineTotal,
      'created_at': createdAt?.toIso8601String(),
    };
  }

  Map<String, dynamic> toRpcMap() {
    return {
      'id': id,
      'product_id': productId,
      'product_resolution': productResolution.code,
      'product_draft': productDraft,
      'resolved_product_id': resolvedProductId,
      'product_name': productName,
      'product_sku': productSku,
      'ordered_quantity': orderedQuantity,
      'negotiated_unit_cost': negotiatedUnitCost,
    };
  }

  static DateTime? _date(dynamic value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString());
  }

  static Map<String, dynamic>? _jsonMap(dynamic value) {
    if (value is Map) return Map<String, dynamic>.from(value);
    if (value is String && value.isNotEmpty) {
      final decoded = jsonDecode(value);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    }
    return null;
  }
}

class PurchaseOrderModel {
  final String id;
  final String tenantId;
  final String branchId;
  final String supplierId;
  final String poNo;
  final PurchaseOrderStatus status;
  final DateTime? expectedDeliveryAt;
  final String? notes;
  final double totalExpectedCost;
  final double totalReceivedCost;
  final String? createdBy;
  final DateTime? sentAt;
  final DateTime? cancelledAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final List<PurchaseOrderItemModel> items;

  const PurchaseOrderModel({
    required this.id,
    required this.tenantId,
    required this.branchId,
    required this.supplierId,
    required this.poNo,
    this.status = PurchaseOrderStatus.draft,
    this.expectedDeliveryAt,
    this.notes,
    this.totalExpectedCost = 0,
    this.totalReceivedCost = 0,
    this.createdBy,
    this.sentAt,
    this.cancelledAt,
    this.createdAt,
    this.updatedAt,
    this.items = const [],
  });

  factory PurchaseOrderModel.fromMap(
    Map<String, dynamic> map, {
    List<PurchaseOrderItemModel> items = const [],
  }) {
    return PurchaseOrderModel(
      id: map['id'] as String,
      tenantId: map['tenant_id'] as String,
      branchId: map['branch_id'] as String,
      supplierId: map['supplier_id'] as String,
      poNo: map['po_no'] as String,
      status: PurchaseOrderStatusX.fromCode(map['status'] as String?),
      expectedDeliveryAt: _date(map['expected_delivery_at']),
      notes: map['notes'] as String?,
      totalExpectedCost: (map['total_expected_cost'] as num?)?.toDouble() ?? 0,
      totalReceivedCost: (map['total_received_cost'] as num?)?.toDouble() ?? 0,
      createdBy: map['created_by'] as String?,
      sentAt: _date(map['sent_at']),
      cancelledAt: _date(map['cancelled_at']),
      createdAt: _date(map['created_at']),
      updatedAt: _date(map['updated_at']),
      items: items,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'tenant_id': tenantId,
      'branch_id': branchId,
      'supplier_id': supplierId,
      'po_no': poNo,
      'status': status.code,
      'expected_delivery_at': expectedDeliveryAt?.toIso8601String(),
      'notes': notes,
      'total_expected_cost': totalExpectedCost,
      'total_received_cost': totalReceivedCost,
      'created_by': createdBy,
      'sent_at': sentAt?.toIso8601String(),
      'cancelled_at': cancelledAt?.toIso8601String(),
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  PurchaseOrderModel copyWith({
    PurchaseOrderStatus? status,
    double? totalReceivedCost,
    DateTime? sentAt,
    List<PurchaseOrderItemModel>? items,
  }) {
    return PurchaseOrderModel(
      id: id,
      tenantId: tenantId,
      branchId: branchId,
      supplierId: supplierId,
      poNo: poNo,
      status: status ?? this.status,
      expectedDeliveryAt: expectedDeliveryAt,
      notes: notes,
      totalExpectedCost: totalExpectedCost,
      totalReceivedCost: totalReceivedCost ?? this.totalReceivedCost,
      createdBy: createdBy,
      sentAt: sentAt ?? this.sentAt,
      cancelledAt: cancelledAt,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
      items: items ?? this.items,
    );
  }

  static DateTime? _date(dynamic value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString());
  }
}

class GoodsReceiptItemInput {
  final String purchaseOrderItemId;
  final int receivedQuantity;
  final double actualUnitCost;
  final bool updateProductCost;
  final String? resolvedProductId;
  final Map<String, dynamic>? productDraft;

  const GoodsReceiptItemInput({
    required this.purchaseOrderItemId,
    required this.receivedQuantity,
    required this.actualUnitCost,
    this.updateProductCost = false,
    this.resolvedProductId,
    this.productDraft,
  });

  Map<String, dynamic> toRpcMap() {
    return {
      'purchase_order_item_id': purchaseOrderItemId,
      'received_quantity': receivedQuantity,
      'actual_unit_cost': actualUnitCost,
      'update_product_cost': updateProductCost,
      'resolved_product_id': resolvedProductId,
      'product_draft': productDraft,
    };
  }
}

class GoodsReceiptModel {
  final String id;
  final String tenantId;
  final String branchId;
  final String purchaseOrderId;
  final String supplierId;
  final String receiptNo;
  final String? note;
  final double totalReceivedValue;
  final String? receivedBy;
  final DateTime? receivedAt;

  const GoodsReceiptModel({
    required this.id,
    required this.tenantId,
    required this.branchId,
    required this.purchaseOrderId,
    required this.supplierId,
    required this.receiptNo,
    this.note,
    this.totalReceivedValue = 0,
    this.receivedBy,
    this.receivedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'tenant_id': tenantId,
      'branch_id': branchId,
      'purchase_order_id': purchaseOrderId,
      'supplier_id': supplierId,
      'receipt_no': receiptNo,
      'note': note,
      'total_received_value': totalReceivedValue,
      'received_by': receivedBy,
      'received_at': receivedAt?.toIso8601String(),
    };
  }
}

class SupplierPaymentModel {
  final String id;
  final String tenantId;
  final String branchId;
  final String supplierId;
  final double amount;
  final String? method;
  final String? accountId;
  final String? ledgerTransactionId;
  final String? note;
  final String? paidBy;
  final DateTime? paidAt;
  final DateTime? createdAt;

  const SupplierPaymentModel({
    required this.id,
    required this.tenantId,
    required this.branchId,
    required this.supplierId,
    required this.amount,
    this.method,
    this.accountId,
    this.ledgerTransactionId,
    this.note,
    this.paidBy,
    this.paidAt,
    this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'tenant_id': tenantId,
      'branch_id': branchId,
      'supplier_id': supplierId,
      'amount': amount,
      'method': method,
      'account_id': accountId,
      'ledger_transaction_id': ledgerTransactionId,
      'note': note,
      'paid_by': paidBy,
      'paid_at': paidAt?.toIso8601String(),
      'created_at': createdAt?.toIso8601String(),
    };
  }
}

enum SupplierLedgerDirection { increase, decrease }

class SupplierLedgerEntryModel {
  final String id;
  final String tenantId;
  final String branchId;
  final String supplierId;
  final String entryType;
  final SupplierLedgerDirection direction;
  final double amount;
  final String sourceEventKey;
  final String referenceType;
  final String referenceId;
  final String? description;
  final DateTime occurredAt;
  final String? createdBy;
  final DateTime createdAt;

  const SupplierLedgerEntryModel({
    required this.id,
    required this.tenantId,
    required this.branchId,
    required this.supplierId,
    required this.entryType,
    required this.direction,
    required this.amount,
    required this.sourceEventKey,
    required this.referenceType,
    required this.referenceId,
    this.description,
    required this.occurredAt,
    this.createdBy,
    required this.createdAt,
  });

  double get signedAmount =>
      direction == SupplierLedgerDirection.increase ? amount : -amount;

  factory SupplierLedgerEntryModel.fromMap(Map<String, dynamic> map) {
    return SupplierLedgerEntryModel(
      id: map['id'] as String,
      tenantId: map['tenant_id'] as String,
      branchId: map['branch_id'] as String,
      supplierId: map['supplier_id'] as String,
      entryType: map['entry_type'] as String,
      direction:
          map['direction'] == 'decrease'
              ? SupplierLedgerDirection.decrease
              : SupplierLedgerDirection.increase,
      amount: (map['amount'] as num).toDouble(),
      sourceEventKey: map['source_event_key'] as String,
      referenceType: map['reference_type'] as String,
      referenceId: map['reference_id'] as String,
      description: map['description'] as String?,
      occurredAt: DateTime.parse(map['occurred_at'].toString()),
      createdBy: map['created_by'] as String?,
      createdAt: DateTime.parse(map['created_at'].toString()),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'tenant_id': tenantId,
      'branch_id': branchId,
      'supplier_id': supplierId,
      'entry_type': entryType,
      'direction':
          direction == SupplierLedgerDirection.increase
              ? 'increase'
              : 'decrease',
      'amount': amount,
      'source_event_key': sourceEventKey,
      'reference_type': referenceType,
      'reference_id': referenceId,
      'description': description,
      'occurred_at': occurredAt.toIso8601String(),
      'created_by': createdBy,
      'created_at': createdAt.toIso8601String(),
    };
  }
}

class SupplierOverviewModel {
  final SupplierModel supplier;
  final List<PurchaseOrderModel> purchaseOrders;
  final List<SupplierLedgerEntryModel> ledgerEntries;

  const SupplierOverviewModel({
    required this.supplier,
    required this.purchaseOrders,
    required this.ledgerEntries,
  });

  Iterable<PurchaseOrderModel> get activeOrders =>
      purchaseOrders.where((po) => po.status != PurchaseOrderStatus.cancelled);

  double get totalOrdered =>
      activeOrders.fold(0, (total, po) => total + po.totalExpectedCost);

  double get totalReceived =>
      activeOrders.fold(0, (total, po) => total + po.totalReceivedCost);

  double get pendingOrderValue => activeOrders.fold(
    0,
    (total, po) =>
        total +
        (po.totalExpectedCost - po.totalReceivedCost).clamp(0, double.infinity),
  );

  int get openOrderCount =>
      activeOrders
          .where((po) => po.status != PurchaseOrderStatus.received)
          .length;

  double get totalPaid => ledgerEntries
      .where(
        (entry) =>
            entry.direction == SupplierLedgerDirection.decrease &&
            entry.entryType == 'supplier_payment',
      )
      .fold(0, (total, entry) => total + entry.amount);

  double get statementBalance =>
      ledgerEntries.fold(0, (total, entry) => total + entry.signedAmount);

  bool get hasStatementMismatch =>
      (statementBalance - supplier.outstandingBalance).abs() > 0.01;

  DateTime? get firstActivityAt {
    final dates = <DateTime>[
      ...purchaseOrders.map((po) => po.createdAt).whereType<DateTime>(),
      ...ledgerEntries.map((entry) => entry.occurredAt),
    ]..sort();
    return dates.isEmpty ? null : dates.first;
  }

  DateTime? get lastActivityAt {
    final dates = <DateTime>[
      ...purchaseOrders.map((po) => po.createdAt).whereType<DateTime>(),
      ...ledgerEntries.map((entry) => entry.occurredAt),
    ]..sort();
    return dates.isEmpty ? null : dates.last;
  }
}
