import 'package:mobileshop_saas/core/extensions/repair_ticket_ext.dart';

class RepairStatusLogModel {
  final String id;
  final String ticketId;
  final String tenantId;
  final String branchId;

  final RepairTicketStatus? oldStatus;
  final RepairTicketStatus newStatus;

  final String changedBy;
  final String? note;
  final DateTime createdAt;

  const RepairStatusLogModel({
    required this.id,
    required this.ticketId,
    required this.tenantId,
    required this.branchId,
    this.oldStatus,
    required this.newStatus,
    required this.changedBy,
    this.note,
    required this.createdAt,
  });

  factory RepairStatusLogModel.fromMap(Map<String, dynamic> map) {
    return RepairStatusLogModel(
      id: map['id'] as String,
      ticketId: map['ticket_id'] as String,
      tenantId: map['tenant_id'] as String,
      branchId: map['branch_id'] as String,
      oldStatus:
          map['old_status'] == null
              ? null
              : RepairTicketStatusX.fromCode(map['old_status'] as String?),
      newStatus: RepairTicketStatusX.fromCode(map['new_status'] as String?),
      changedBy: map['changed_by'] as String,
      note: map['note'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  Map<String, dynamic> toCacheMap() {
    return {
      'id': id,
      'ticket_id': ticketId,
      'tenant_id': tenantId,
      'branch_id': branchId,
      'old_status': oldStatus?.code,
      'new_status': newStatus.code,
      'changed_by': changedBy,
      'note': note,
      'created_at': createdAt.toIso8601String(),
    };
  }
}
