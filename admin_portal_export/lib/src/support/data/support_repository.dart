import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/support_models.dart';

class SupportRepository {
  final SupabaseClient _client;
  SupportRepository({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;
  Future<List<Map<String, dynamic>>> _rows(
    String rpc, [
    Map<String, dynamic>? params,
  ]) async =>
      (await _client.rpc(rpc, params: params) as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
  Future<List<AuditEntry>> audits({
    String? tenantId,
    String? action,
    String? adminId,
    DateTime? from,
    DateTime? to,
  }) => _rows('platform_list_audit_logs', {
    'p_tenant_id': tenantId,
    'p_action': action,
    'p_admin_user_id': adminId,
    'p_from': from?.toUtc().toIso8601String(),
    'p_to': to?.toUtc().toIso8601String(),
    'p_limit': 200,
  }).then((v) => v.map(AuditEntry.fromJson).toList());
  Future<List<AuditEntry>> activity(String id) => _rows(
    'platform_tenant_activity',
    {'p_tenant_id': id, 'p_limit': 100},
  ).then((v) => v.map(AuditEntry.fromJson).toList());
  Future<List<FailedJob>> jobs() => _rows(
    'platform_list_failed_report_jobs',
  ).then((v) => v.map(FailedJob.fromJson).toList());
  Future<void> retryJob(FailedJob j) => _client.rpc(
    'platform_retry_report_job',
    params: {'p_job_type': j.type, 'p_job_id': j.id},
  );
  Future<List<OfflineFailure>> failures() => _rows(
    'platform_list_failed_offline_mutations',
  ).then((v) => v.map(OfflineFailure.fromJson).toList());
  Future<void> updateFailure(String id, String action) => _client.rpc(
    'platform_update_offline_failure',
    params: {'p_id': id, 'p_action': action},
  );
  Future<List<SupportNote>> notes(String id) => _rows(
    'platform_list_support_notes',
    {'p_tenant_id': id},
  ).then((v) => v.map(SupportNote.fromJson).toList());
  Future<void> addNote(
    String tenantId,
    String? userId,
    String category,
    String note,
  ) => _client.rpc(
    'platform_add_support_note',
    params: {
      'p_tenant_id': tenantId,
      'p_subject_user_id': userId,
      'p_category': category,
      'p_note': note,
    },
  );
  Future<void> resolveNote(String id) =>
      _client.rpc('platform_resolve_support_note', params: {'p_id': id});
}
