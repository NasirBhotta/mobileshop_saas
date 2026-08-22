enum InventoryUnitStatus { available, sold, inRepair, returned, lost, damaged }

extension InventoryUnitStatusX on InventoryUnitStatus {
  String get code {
    switch (this) {
      case InventoryUnitStatus.available:
        return 'available';
      case InventoryUnitStatus.sold:
        return 'sold';
      case InventoryUnitStatus.inRepair:
        return 'in_repair';
      case InventoryUnitStatus.returned:
        return 'returned';
      case InventoryUnitStatus.lost:
        return 'lost';
      case InventoryUnitStatus.damaged:
        return 'damaged';
    }
  }

  String get label {
    switch (this) {
      case InventoryUnitStatus.available:
        return 'Available';
      case InventoryUnitStatus.sold:
        return 'Sold';
      case InventoryUnitStatus.inRepair:
        return 'In Repair';
      case InventoryUnitStatus.returned:
        return 'Returned';
      case InventoryUnitStatus.lost:
        return 'Lost';
      case InventoryUnitStatus.damaged:
        return 'Damaged';
    }
  }

  static InventoryUnitStatus fromCode(String? code) {
    switch (code) {
      case 'available':
        return InventoryUnitStatus.available;
      case 'sold':
        return InventoryUnitStatus.sold;
      case 'in_repair':
        return InventoryUnitStatus.inRepair;
      case 'returned':
        return InventoryUnitStatus.returned;
      case 'lost':
        return InventoryUnitStatus.lost;
      case 'damaged':
        return InventoryUnitStatus.damaged;
      default:
        return InventoryUnitStatus.available;
    }
  }
}

class InventoryUnitModel {
  final String id;
  final String tenantId;
  final String branchId;
  final String productId;

  final String imei;
  final InventoryUnitStatus status;

  final String? saleId;
  final String? customerId;

  final DateTime? warrantyStartAt;
  final DateTime? warrantyEndAt;

  final String? currentRepairTicketId;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  const InventoryUnitModel({
    required this.id,
    required this.tenantId,
    required this.branchId,
    required this.productId,
    required this.imei,
    this.status = InventoryUnitStatus.available,
    this.saleId,
    this.customerId,
    this.warrantyStartAt,
    this.warrantyEndAt,
    this.currentRepairTicketId,
    this.createdAt,
    this.updatedAt,
  });

  factory InventoryUnitModel.fromMap(Map<String, dynamic> map) {
    return InventoryUnitModel(
      id: map['id'] as String,
      tenantId: map['tenant_id'] as String,
      branchId: map['branch_id'] as String,
      productId: map['product_id'] as String,
      imei: map['imei'] as String,
      status: InventoryUnitStatusX.fromCode(map['status'] as String?),
      saleId: map['sale_id'] as String?,
      customerId: map['customer_id'] as String?,
      warrantyStartAt: _date(map['warranty_start_at']),
      warrantyEndAt: _date(map['warranty_end_at']),
      currentRepairTicketId: map['current_repair_ticket_id'] as String?,
      createdAt: _date(map['created_at']),
      updatedAt: _date(map['updated_at']),
    );
  }

  Map<String, dynamic> toMap() => toCacheMap();

  Map<String, dynamic> toCacheMap() {
    return {
      'id': id,
      'tenant_id': tenantId,
      'branch_id': branchId,
      'product_id': productId,
      'imei': imei,
      'status': status.code,
      'sale_id': saleId,
      'customer_id': customerId,
      'warranty_start_at': warrantyStartAt?.toIso8601String(),
      'warranty_end_at': warrantyEndAt?.toIso8601String(),
      'current_repair_ticket_id': currentRepairTicketId,
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  static DateTime? _date(dynamic value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString());
  }
}
