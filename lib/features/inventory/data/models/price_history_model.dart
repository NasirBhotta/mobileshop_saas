class PriceHistoryModel {
  final String id;
  final String productId;
  final String tenantId;
  final String branchId;
  final double oldPrice;
  final double newPrice;
  final String? changedBy;
  final DateTime changedAt;
  final String changeSource;

  const PriceHistoryModel({
    required this.id,
    required this.productId,
    required this.tenantId,
    required this.branchId,
    required this.oldPrice,
    required this.newPrice,
    required this.changedBy,
    required this.changedAt,
    required this.changeSource,
  });

  factory PriceHistoryModel.fromMap(Map<String, dynamic> map) {
    return PriceHistoryModel(
      id: map['id'] as String,
      productId: map['product_id'] as String,
      tenantId: map['tenant_id'] as String,
      branchId: map['branch_id'] as String,
      oldPrice: (map['old_price'] as num).toDouble(),
      newPrice: (map['new_price'] as num).toDouble(),
      changedBy: map['changed_by'] as String?,
      changedAt: DateTime.parse(map['changed_at'] as String).toLocal(),
      changeSource: map['change_source'] as String? ?? 'single_update',
    );
  }
}
