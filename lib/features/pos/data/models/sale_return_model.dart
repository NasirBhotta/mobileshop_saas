import 'cart_item_model.dart';

class SaleReturnRefundLegModel {
  final String id;
  final String originalPaymentId;
  final String accountId;
  final double amount;
  final String ledgerTransactionId;

  const SaleReturnRefundLegModel({
    required this.id,
    required this.originalPaymentId,
    required this.accountId,
    required this.amount,
    required this.ledgerTransactionId,
  });

  factory SaleReturnRefundLegModel.fromMap(Map<String, dynamic> map) {
    return SaleReturnRefundLegModel(
      id: map['id'] as String,
      originalPaymentId: map['original_payment_id'] as String,
      accountId: map['account_id'] as String,
      amount: (map['amount'] as num).toDouble(),
      ledgerTransactionId: map['ledger_transaction_id'] as String,
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'original_payment_id': originalPaymentId,
    'account_id': accountId,
    'amount': amount,
    'ledger_transaction_id': ledgerTransactionId,
  };
}

enum SaleReturnStatus { approved, pendingApproval }

extension SaleReturnStatusX on SaleReturnStatus {
  String get code {
    switch (this) {
      case SaleReturnStatus.approved:
        return 'approved';
      case SaleReturnStatus.pendingApproval:
        return 'pending_approval';
    }
  }

  String get label {
    switch (this) {
      case SaleReturnStatus.approved:
        return 'Approved';
      case SaleReturnStatus.pendingApproval:
        return 'Pending approval';
    }
  }

  static SaleReturnStatus fromCode(String code) {
    switch (code) {
      case 'pending_approval':
        return SaleReturnStatus.pendingApproval;
      default:
        return SaleReturnStatus.approved;
    }
  }
}

enum RefundMethod { cash, credit }

extension RefundMethodX on RefundMethod {
  String get code {
    switch (this) {
      case RefundMethod.cash:
        return 'cash';
      case RefundMethod.credit:
        return 'credit';
    }
  }

  String get label {
    switch (this) {
      case RefundMethod.cash:
        return 'Cash';
      case RefundMethod.credit:
        return 'Credit';
    }
  }

  static RefundMethod fromCode(String code) {
    switch (code) {
      case 'credit':
        return RefundMethod.credit;
      default:
        return RefundMethod.cash;
    }
  }
}

class SaleReturnItemModel {
  final String productId;
  final String productName;
  final String? productSku;
  final int quantity;
  final double refundAmount;
  final String? restockProductId;
  final String restockCondition;
  final double? resalePrice;

  const SaleReturnItemModel({
    required this.productId,
    required this.productName,
    this.productSku,
    required this.quantity,
    required this.refundAmount,
    this.restockProductId,
    this.restockCondition = 'returned',
    this.resalePrice,
  });

  factory SaleReturnItemModel.fromSaleItem({
    required CartItemModel item,
    required int quantity,
  }) {
    final unitRefund =
        item.quantity == 0 ? 0.0 : item.lineTotal / item.quantity;
    return SaleReturnItemModel(
      productId: item.productId,
      productName: item.productName,
      productSku: item.productSku,
      quantity: quantity,
      refundAmount: unitRefund * quantity,
    );
  }

  factory SaleReturnItemModel.fromMap(Map<String, dynamic> map) {
    return SaleReturnItemModel(
      productId: map['product_id'] as String,
      productName: map['product_name'] as String,
      productSku: map['product_sku'] as String?,
      quantity: (map['quantity'] as num).toInt(),
      refundAmount: (map['refund_amount'] as num).toDouble(),
      restockProductId: map['restock_product_id'] as String?,
      restockCondition: map['restock_condition'] as String? ?? 'returned',
      resalePrice: (map['resale_price'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toMap() => {
    'product_id': productId,
    'product_name': productName,
    'product_sku': productSku,
    'quantity': quantity,
    'refund_amount': refundAmount,
    'restock_product_id': restockProductId,
    'restock_condition': restockCondition,
    'resale_price': resalePrice,
  };
}

class SaleReturnModel {
  final String id;
  final String originalSaleId;
  final String branchId;
  final String userId;
  final SaleReturnStatus status;
  final RefundMethod refundMethod;
  final double refundAmount;
  final String? approvalRequiredReason;
  final String? overrideReason;
  final String? approvedBy;
  final DateTime createdAt;
  final List<SaleReturnItemModel> items;
  final List<SaleReturnRefundLegModel> refundLegs;

  const SaleReturnModel({
    required this.id,
    required this.originalSaleId,
    required this.branchId,
    required this.userId,
    required this.status,
    required this.refundMethod,
    required this.refundAmount,
    this.approvalRequiredReason,
    this.overrideReason,
    this.approvedBy,
    required this.createdAt,
    required this.items,
    this.refundLegs = const [],
  });

  factory SaleReturnModel.fromMap(Map<String, dynamic> map) {
    final items = map['items'] ?? map['sale_return_items'] ?? const [];
    final refundLegs =
        map['refund_legs'] ?? map['sale_return_refund_legs'] ?? const [];
    return SaleReturnModel(
      id: map['id'] as String,
      originalSaleId: map['original_sale_id'] as String,
      branchId: map['branch_id'] as String,
      userId: map['user_id'] as String,
      status: SaleReturnStatusX.fromCode(map['status'] as String? ?? ''),
      refundMethod: RefundMethodX.fromCode(
        map['refund_method'] as String? ?? '',
      ),
      refundAmount: (map['refund_amount'] as num).toDouble(),
      approvalRequiredReason: map['approval_required_reason'] as String?,
      overrideReason: map['override_reason'] as String?,
      approvedBy: map['approved_by'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      items:
          (items as List)
              .map(
                (item) => SaleReturnItemModel.fromMap(
                  Map<String, dynamic>.from(item as Map),
                ),
              )
              .toList(),
      refundLegs:
          (refundLegs as List)
              .map(
                (leg) => SaleReturnRefundLegModel.fromMap(
                  Map<String, dynamic>.from(leg as Map),
                ),
              )
              .toList(),
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'original_sale_id': originalSaleId,
    'branch_id': branchId,
    'user_id': userId,
    'status': status.code,
    'refund_method': refundMethod.code,
    'refund_amount': refundAmount,
    'approval_required_reason': approvalRequiredReason,
    'override_reason': overrideReason,
    'approved_by': approvedBy,
    'created_at': createdAt.toIso8601String(),
    'items': items.map((item) => item.toMap()).toList(),
    'refund_legs': refundLegs.map((leg) => leg.toMap()).toList(),
  };

  SaleReturnModel copyWith({
    SaleReturnStatus? status,
    String? approvalRequiredReason,
    String? overrideReason,
    String? approvedBy,
    List<SaleReturnRefundLegModel>? refundLegs,
  }) {
    return SaleReturnModel(
      id: id,
      originalSaleId: originalSaleId,
      branchId: branchId,
      userId: userId,
      status: status ?? this.status,
      refundMethod: refundMethod,
      refundAmount: refundAmount,
      approvalRequiredReason:
          approvalRequiredReason ?? this.approvalRequiredReason,
      overrideReason: overrideReason ?? this.overrideReason,
      approvedBy: approvedBy ?? this.approvedBy,
      createdAt: createdAt,
      items: items,
      refundLegs: refundLegs ?? this.refundLegs,
    );
  }
}
