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
  Future<List<BillingPlan>> plans() async {
    final rows = await _client.rpc('platform_admin_list_plans') as List;
    return rows
        .map(
          (row) => BillingPlan.fromJson(Map<String, dynamic>.from(row as Map)),
        )
        .toList();
  }

  Future<void> createInvoice({
    required String tenantId,
    required String planId,
    required String billingCycle,
    required double originalAmount,
    double discountAmount = 0,
    DateTime? dueAt,
    String? note,
  }) => _client.rpc(
    'platform_create_package_invoice',
    params: {
      'p_tenant_id': tenantId,
      'p_plan_id': planId,
      'p_billing_cycle': billingCycle,
      'p_original_amount': originalAmount,
      'p_discount_amount': discountAmount,
      'p_due_at': dueAt?.toUtc().toIso8601String(),
      'p_note': note,
    },
  );
  Future<List<Map<String, dynamic>>> _rows(String rpc, String id) async =>
      (await _client.rpc(rpc, params: {'p_tenant_id': id}) as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
  Future<void> record({
    required String tenantId,
    required String invoiceId,
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
  Future<void> voidInvoice(String id) => _client.rpc(
    'platform_void_billing_invoice',
    params: {'p_invoice_id': id, 'p_reason': 'Voided from admin portal'},
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
