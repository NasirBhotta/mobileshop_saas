DateTime _date(dynamic value) => DateTime.parse(value as String);

class AuditEntry {
  final String id, action, entityType;
  final String? tenantId, tenantName, adminId, entityId, reason;
  final DateTime createdAt;
  const AuditEntry({
    required this.id,
    required this.action,
    required this.entityType,
    required this.createdAt,
    this.tenantId,
    this.tenantName,
    this.adminId,
    this.entityId,
    this.reason,
  });
  factory AuditEntry.fromJson(Map<String, dynamic> j) => AuditEntry(
    id: j['id'] as String,
    action: j['action'] as String,
    entityType: j['entity_type'] as String,
    createdAt: _date(j['created_at']),
    tenantId: j['tenant_id'] as String?,
    tenantName: j['tenant_name'] as String?,
    adminId: j['admin_user_id'] as String?,
    entityId: j['entity_id'] as String?,
    reason: j['reason'] as String?,
  );
}

class FailedJob {
  final String type, id, tenantId, status;
  final String? scheduleId, errorCode;
  final DateTime createdAt;
  const FailedJob({
    required this.type,
    required this.id,
    required this.tenantId,
    required this.status,
    required this.createdAt,
    this.scheduleId,
    this.errorCode,
  });
  factory FailedJob.fromJson(Map<String, dynamic> j) => FailedJob(
    type: j['job_type'] as String,
    id: j['job_id'] as String,
    tenantId: j['tenant_id'] as String,
    status: j['status'] as String,
    createdAt: _date(j['created_at']),
    scheduleId: j['schedule_id'] as String?,
    errorCode: j['error_code'] as String?,
  );
}

class OfflineFailure {
  final String id, tenantId, type, status;
  final String? userId, code;
  final int attempts;
  final DateTime failedAt;
  const OfflineFailure({
    required this.id,
    required this.tenantId,
    required this.type,
    required this.status,
    required this.attempts,
    required this.failedAt,
    this.userId,
    this.code,
  });
  factory OfflineFailure.fromJson(Map<String, dynamic> j) => OfflineFailure(
    id: j['id'] as String,
    tenantId: j['tenant_id'] as String,
    type: j['mutation_type'] as String,
    status: j['status'] as String,
    attempts: (j['attempt_count'] as num).toInt(),
    failedAt: _date(j['failed_at']),
    userId: j['user_id'] as String?,
    code: j['diagnostic_code'] as String?,
  );
}

class SupportNote {
  final String id, category, note, status, createdBy;
  final String? subjectUserId;
  final DateTime createdAt;
  const SupportNote({
    required this.id,
    required this.category,
    required this.note,
    required this.status,
    required this.createdBy,
    required this.createdAt,
    this.subjectUserId,
  });
  factory SupportNote.fromJson(Map<String, dynamic> j) => SupportNote(
    id: j['id'] as String,
    category: j['category'] as String,
    note: j['note'] as String,
    status: j['status'] as String,
    createdBy: j['created_by'] as String,
    createdAt: _date(j['created_at']),
    subjectUserId: j['subject_user_id'] as String?,
  );
}
