import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_shop_platform_admin/src/billing/domain/tenant_billing.dart';

void main() {
  test('billing summary maps period-end cancellation fields', () {
    final summary = BillingSummary.fromJson({
      'subscription_id': 'subscription-id',
      'plan': 'Business',
      'subscription_status': 'active',
      'billing_cycle': 'monthly',
      'currency': 'PKR',
      'expires_at': '2026-08-19T00:00:00Z',
      'cancel_at_period_end': true,
      'cancellation_requested_at': '2026-07-19T00:00:00Z',
    });

    expect(summary.cancelAtPeriodEnd, isTrue);
    expect(summary.expiresAt, DateTime.utc(2026, 8, 19));
    expect(summary.cancellationRequestedAt, DateTime.utc(2026, 7, 19));
  });
}
