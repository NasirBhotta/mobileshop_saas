import 'package:mobileshop_saas/core/extensions/repair_ticket_ext.dart';

class RepairTicketModel {
  final String id;
  final String tenantId;
  final String branchId;

  final String? ticketNo;

  final String? customerId;
  final String customerName;
  final String? customerPhone;

  final String? productId;
  final String? inventoryUnitId;

  final String deviceBrand;
  final String deviceModel;
  final String? deviceColor;
  final String? imei;

  final String faultDescription;
  final String? technicianId;

  final RepairTicketStatus status;

  final double? estimatedCost;
  final DateTime? estimatedCompletionAt;
  final String? estimateNote;

  final double? partsCost;
  final double? laborCost;
  final double? totalCost;

  final String? warrantyReference;
  final String? warrantyNote;
  final bool isWarrantyRepair;

  final String createdBy;

  final DateTime? completedAt;
  final DateTime? deliveredAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? archivedAt;
  final String? archivedBy;

  const RepairTicketModel({
    required this.id,
    required this.tenantId,
    required this.branchId,
    this.ticketNo,
    this.customerId,
    required this.customerName,
    this.customerPhone,
    this.productId,
    this.inventoryUnitId,
    required this.deviceBrand,
    required this.deviceModel,
    this.deviceColor,
    this.imei,
    required this.faultDescription,
    this.technicianId,
    this.status = RepairTicketStatus.received,
    this.estimatedCost,
    this.estimatedCompletionAt,
    this.estimateNote,
    this.partsCost,
    this.laborCost,
    this.totalCost,
    this.warrantyReference,
    this.warrantyNote,
    this.isWarrantyRepair = false,
    required this.createdBy,
    this.completedAt,
    this.deliveredAt,
    this.createdAt,
    this.updatedAt,
    this.archivedAt,
    this.archivedBy,
  });

  factory RepairTicketModel.fromMap(Map<String, dynamic> map) {
    return RepairTicketModel(
      id: map['id'] as String,
      tenantId: map['tenant_id'] as String,
      branchId: map['branch_id'] as String,
      ticketNo: map['ticket_no'] as String?,
      customerId: map['customer_id'] as String?,
      customerName: map['customer_name'] as String,
      customerPhone: map['customer_phone'] as String?,
      productId: map['product_id'] as String?,
      inventoryUnitId: map['inventory_unit_id'] as String?,
      deviceBrand: map['device_brand'] as String,
      deviceModel: map['device_model'] as String,
      deviceColor: map['device_color'] as String?,
      imei: map['imei'] as String?,
      faultDescription: map['fault_description'] as String,
      technicianId: map['technician_id'] as String?,
      status: RepairTicketStatusX.fromCode(map['status'] as String?),
      estimatedCost: (map['estimated_cost'] as num?)?.toDouble(),
      estimatedCompletionAt: _date(map['estimated_completion_at']),
      estimateNote: map['estimate_note'] as String?,
      partsCost: (map['parts_cost'] as num?)?.toDouble(),
      laborCost: (map['labor_cost'] as num?)?.toDouble(),
      totalCost: (map['total_cost'] as num?)?.toDouble(),
      warrantyReference: map['warranty_reference'] as String?,
      warrantyNote: map['warranty_note'] as String?,
      isWarrantyRepair: _bool(map['is_warranty_repair']),
      createdBy: map['created_by'] as String,
      completedAt: _date(map['completed_at']),
      deliveredAt: _date(map['delivered_at']),
      createdAt: _date(map['created_at']),
      updatedAt: _date(map['updated_at']),
      archivedAt: _date(map['archived_at']),
      archivedBy: map['archived_by'] as String?,
    );
  }

  Map<String, dynamic> toInsertMap() {
    return {
      'id': id,
      'tenant_id': tenantId,
      'branch_id': branchId,
      'ticket_no': ticketNo,
      'customer_id': customerId,
      'customer_name': customerName,
      'customer_phone': customerPhone,
      'product_id': productId,
      'inventory_unit_id': inventoryUnitId,
      'device_brand': deviceBrand,
      'device_model': deviceModel,
      'device_color': deviceColor,
      'imei': imei,
      'fault_description': faultDescription,
      'technician_id': technicianId,
      'status': status.code,
      'estimated_cost': estimatedCost,
      'estimated_completion_at': estimatedCompletionAt?.toIso8601String(),
      'estimate_note': estimateNote,
      'parts_cost': partsCost,
      'labor_cost': laborCost,
      'total_cost': totalCost,
      'warranty_reference': warrantyReference,
      'warranty_note': warrantyNote,
      'is_warranty_repair': isWarrantyRepair,
      'created_by': createdBy,
      'completed_at': completedAt?.toIso8601String(),
      'delivered_at': deliveredAt?.toIso8601String(),
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
      'archived_at': archivedAt?.toIso8601String(),
      'archived_by': archivedBy,
    };
  }

  Map<String, dynamic> toCacheMap() => toInsertMap();

  RepairTicketModel copyWith({
    String? id,
    String? tenantId,
    String? branchId,
    String? ticketNo,
    String? customerId,
    String? customerName,
    String? customerPhone,
    String? productId,
    String? inventoryUnitId,
    String? deviceBrand,
    String? deviceModel,
    String? deviceColor,
    String? imei,
    String? faultDescription,
    String? technicianId,
    RepairTicketStatus? status,
    double? estimatedCost,
    DateTime? estimatedCompletionAt,
    String? estimateNote,
    double? partsCost,
    double? laborCost,
    double? totalCost,
    String? warrantyReference,
    String? warrantyNote,
    bool? isWarrantyRepair,
    String? createdBy,
    DateTime? completedAt,
    DateTime? deliveredAt,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? archivedAt,
    String? archivedBy,
  }) {
    return RepairTicketModel(
      id: id ?? this.id,
      tenantId: tenantId ?? this.tenantId,
      branchId: branchId ?? this.branchId,
      ticketNo: ticketNo ?? this.ticketNo,
      customerId: customerId ?? this.customerId,
      customerName: customerName ?? this.customerName,
      customerPhone: customerPhone ?? this.customerPhone,
      productId: productId ?? this.productId,
      inventoryUnitId: inventoryUnitId ?? this.inventoryUnitId,
      deviceBrand: deviceBrand ?? this.deviceBrand,
      deviceModel: deviceModel ?? this.deviceModel,
      deviceColor: deviceColor ?? this.deviceColor,
      imei: imei ?? this.imei,
      faultDescription: faultDescription ?? this.faultDescription,
      technicianId: technicianId ?? this.technicianId,
      status: status ?? this.status,
      estimatedCost: estimatedCost ?? this.estimatedCost,
      estimatedCompletionAt:
          estimatedCompletionAt ?? this.estimatedCompletionAt,
      estimateNote: estimateNote ?? this.estimateNote,
      partsCost: partsCost ?? this.partsCost,
      laborCost: laborCost ?? this.laborCost,
      totalCost: totalCost ?? this.totalCost,
      warrantyReference: warrantyReference ?? this.warrantyReference,
      warrantyNote: warrantyNote ?? this.warrantyNote,
      isWarrantyRepair: isWarrantyRepair ?? this.isWarrantyRepair,
      createdBy: createdBy ?? this.createdBy,
      completedAt: completedAt ?? this.completedAt,
      deliveredAt: deliveredAt ?? this.deliveredAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      archivedAt: archivedAt ?? this.archivedAt,
      archivedBy: archivedBy ?? this.archivedBy,
    );
  }

  static DateTime? _date(dynamic value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString());
  }

  static bool _bool(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value.toInt() == 1;
    return value == true || value == 'true';
  }
}
