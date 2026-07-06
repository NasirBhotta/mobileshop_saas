enum DiscountType { fixed, percent }

extension DiscountTypeX on DiscountType {
  String get code => this == DiscountType.percent ? 'percent' : 'fixed';

  String get label => this == DiscountType.percent ? 'Percent' : 'Fixed';

  static DiscountType fromCode(String code) {
    return code == 'percent' ? DiscountType.percent : DiscountType.fixed;
  }
}

class DiscountApprovalModel {
  final String scope;
  final String? productId;
  final DiscountType type;
  final double requestedValue;
  final double discountAmount;
  final String? approvedBy;
  final String? reason;
  final bool exceededLimit;

  const DiscountApprovalModel({
    required this.scope,
    this.productId,
    required this.type,
    required this.requestedValue,
    required this.discountAmount,
    this.approvedBy,
    this.reason,
    this.exceededLimit = false,
  });

  Map<String, dynamic> toMap() => {
    'scope': scope,
    'product_id': productId,
    'type': type.code,
    'requested_value': requestedValue,
    'discount_amount': discountAmount,
    'approved_by': approvedBy,
    'reason': reason,
    'exceeded_limit': exceededLimit,
  };
}

class DiscountEvaluation {
  final bool allowed;
  final bool requiresApproval;
  final double discountAmount;
  final String? message;
  final String? approvedBy;

  const DiscountEvaluation({
    required this.allowed,
    required this.requiresApproval,
    required this.discountAmount,
    this.message,
    this.approvedBy,
  });
}
