import 'package:mobileshop_saas/core/utils/adjustment_extention.dart';

enum AdjustmentReason { damaged, expired, lost, theft, other }

enum AdjustmentType { stockIn, stockOut }

class StockAdjustmentModel {
  final String id;
  final String branchId;
  final String productId;
  final String productName;
  final String userId;
  final AdjustmentType type;
  final int quantity;
  final AdjustmentReason reason;
  final String? reasonNote;
  final DateTime createdAt;
  final bool isOverride;
  final double unitCost;
  final double totalValue;

  const StockAdjustmentModel({
    required this.id,
    required this.branchId,
    required this.productId,
    required this.productName,
    required this.userId,
    required this.type,
    required this.quantity,
    required this.reason,
    this.reasonNote,
    this.isOverride = false,
    required this.unitCost,
    required this.totalValue,
    required this.createdAt,
  });

  factory StockAdjustmentModel.fromMap(Map<String, dynamic> map) {
    // products join se naam aayega
    final product = map['products'] as Map<String, dynamic>?;

    return StockAdjustmentModel(
      id: map['id'] as String,
      branchId: map['branch_id'] as String,
      productId: map['product_id'] as String,
      productName: product?['name'] as String? ?? 'Unknown',
      userId: map['user_id'] as String,
      type: AdjustmentTypeX.fromCode(map['type'] as String),
      quantity: (map['quantity'] as num).toInt(),
      reason: AdjustmentReasonX.fromCode(map['reason_code'] as String),
      reasonNote: map['reason_note'] as String?,
      isOverride: map['is_override'] as bool? ?? false,
      unitCost: (map['unit_cost'] as num?)?.toDouble() ?? 0,
      totalValue: (map['total_value'] as num?)?.toDouble() ?? 0,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  // Flutter object se DB map banao (insert ke liye)
  Map<String, dynamic> toInsertMap({
    required String branchId,
    required String userId,
  }) {
    return {
      'branch_id': branchId,
      'product_id': productId,
      'user_id': userId,
      'type': type.code,
      'quantity': quantity,
      'reason_code': reason.code,
      'reason_note': reasonNote,
      'is_override': isOverride,
      'unit_cost': unitCost,
      'total_value': totalValue,
    };
  }
}
