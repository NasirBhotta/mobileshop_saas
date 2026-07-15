import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_shop_platform_admin/src/support/domain/support_models.dart';

void main() {
  test(
    'failed report exposes diagnostic identifiers without payload fields',
    () {
      final job = FailedJob.fromJson({
        'job_type': 'sales',
        'job_id': 'job-id',
        'tenant_id': 'tenant-id',
        'schedule_id': 'schedule-id',
        'status': 'failed',
        'error_code': 'REPORT_DELIVERY_FAILED',
        'created_at': '2026-07-15T00:00:00Z',
        'customer_payload': {'email': 'hidden@example.com'},
      });
      expect(job.id, 'job-id');
      expect(job.errorCode, 'REPORT_DELIVERY_FAILED');
      expect(job.toString(), isNot(contains('hidden@example.com')));
    },
  );
  test('audit entry maps filter-safe admin and tenant identifiers', () {
    final entry = AuditEntry.fromJson({
      'id': 'audit-id',
      'tenant_id': 'tenant-id',
      'tenant_name': 'Shop',
      'admin_user_id': 'admin-id',
      'action': 'support.note_added',
      'entity_type': 'support_note',
      'entity_id': 'note-id',
      'reason': null,
      'created_at': '2026-07-15T00:00:00Z',
    });
    expect(entry.adminId, 'admin-id');
    expect(entry.tenantId, 'tenant-id');
  });
}
