class RepairPartModel {
  final String id;
  final String tenantId;
  final String branchId;
  final String ticketId;
  final String sourceType;
  final String? productId;
  final String? supplierId;
  final String settlementType;
  final String name;
  final int quantity;
  final double unitCostSnapshot;
  final double unitSalePrice;
  final String state;
  final String createdBy;
  final DateTime createdAt;
  final DateTime updatedAt;

  const RepairPartModel({
    required this.id,
    required this.tenantId,
    required this.branchId,
    required this.ticketId,
    required this.sourceType,
    this.productId,
    this.supplierId,
    this.settlementType = 'already_recorded',
    required this.name,
    required this.quantity,
    required this.unitCostSnapshot,
    required this.unitSalePrice,
    this.state = 'planned',
    required this.createdBy,
    required this.createdAt,
    required this.updatedAt,
  });

  double get totalCost => quantity * unitCostSnapshot;
  double get totalCharge => quantity * unitSalePrice;

  factory RepairPartModel.fromMap(Map<String, dynamic> map) => RepairPartModel(
    id: map['id'] as String,
    tenantId: map['tenant_id'] as String,
    branchId: map['branch_id'] as String,
    ticketId: map['ticket_id'] as String,
    sourceType: map['source_type'] as String,
    productId: map['product_id'] as String?,
    supplierId: map['supplier_id'] as String?,
    settlementType: map['settlement_type'] as String? ?? 'already_recorded',
    name: map['name'] as String,
    quantity: (map['quantity'] as num).toInt(),
    unitCostSnapshot: (map['unit_cost_snapshot'] as num).toDouble(),
    unitSalePrice: (map['unit_sale_price'] as num).toDouble(),
    state: map['state'] as String? ?? 'planned',
    createdBy: map['created_by'] as String,
    createdAt: DateTime.parse(map['created_at'].toString()),
    updatedAt: DateTime.parse(map['updated_at'].toString()),
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'tenant_id': tenantId,
    'branch_id': branchId,
    'ticket_id': ticketId,
    'source_type': sourceType,
    'product_id': productId,
    'supplier_id': supplierId,
    'settlement_type': settlementType,
    'name': name,
    'quantity': quantity,
    'unit_cost_snapshot': unitCostSnapshot,
    'unit_sale_price': unitSalePrice,
    'state': state,
    'created_by': createdBy,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
  };

  Map<String, dynamic> toRpcMap() => {
    'id': id,
    'source_type': sourceType,
    'product_id': productId,
    'supplier_id': supplierId,
    'settlement_type': settlementType,
    'name': name,
    'quantity': quantity,
    'unit_cost_snapshot': unitCostSnapshot,
    'unit_sale_price': unitSalePrice,
  };
}
