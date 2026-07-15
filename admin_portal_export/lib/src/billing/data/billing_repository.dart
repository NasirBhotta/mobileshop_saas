import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/tenant_billing.dart';

class BillingRepository {
  final SupabaseClient _client;
  BillingRepository({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;
  Future<BillingSummary?> summary(String tenantId) async {
    final rows =
        await _client.rpc(
              'platform_get_billing_summary',
              params: {'p_tenant_id': tenantId},
            )
            as List;
    return rows.isEmpty
        ? null
        : BillingSummary.fromJson(
          Map<String, dynamic>.from(rows.single as Map),
        );
  }

  Future<List<BillingInvoice>> invoices(String tenantId) async => _rows(
    'platform_list_billing_invoices',
    tenantId,
  ).then((r) => r.map(BillingInvoice.fromJson).toList());
  Future<List<BillingPayment>> payments(String tenantId) async => _rows(
    'platform_list_billing_payments',
    tenantId,
  ).then((r) => r.map(BillingPayment.fromJson).toList());
  Future<List<Map<String, dynamic>>> _rows(String rpc, String id) async =>
      (await _client.rpc(rpc, params: {'p_tenant_id': id}) as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
  Future<void> record({
    required String tenantId,
    String? invoiceId,
    required double amount,
    required String method,
    required String reference,
    required DateTime paidAt,
  }) => _client.rpc(
    'platform_record_manual_payment',
    params: {
      'p_tenant_id': tenantId,
      'p_invoice_id': invoiceId,
      'p_amount': amount,
      'p_currency': 'PKR',
      'p_method': method,
      'p_external_reference': reference,
      'p_paid_at': paidAt.toUtc().toIso8601String(),
    },
  );
  Future<void> verify(String id, bool verified) => _client.rpc(
    'platform_verify_manual_payment',
    params: {'p_payment_id': id, 'p_verified': verified},
  );
  Future<void> manage({
    required String tenantId,
    required String action,
    DateTime? until,
    String? cycle,
    String? reason,
  }) => _client.rpc(
    'platform_manage_subscription',
    params: {
      'p_tenant_id': tenantId,
      'p_action': action,
      'p_until': until?.toUtc().toIso8601String(),
      'p_billing_cycle': cycle,
      'p_reason': reason,
    },
  );
}
