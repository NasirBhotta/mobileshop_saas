class BillingSummary {
  final String subscriptionId, plan, status, billingCycle, currency;
  final DateTime? trialStartsAt, trialEndsAt, renewalDate, graceEndsAt;
  final double outstandingAmount;
  const BillingSummary({
    required this.subscriptionId,
    required this.plan,
    required this.status,
    required this.billingCycle,
    required this.currency,
    required this.outstandingAmount,
    this.trialStartsAt,
    this.trialEndsAt,
    this.renewalDate,
    this.graceEndsAt,
  });
  factory BillingSummary.fromJson(Map<String, dynamic> j) => BillingSummary(
    subscriptionId: j['subscription_id'] as String,
    plan: j['plan'] as String,
    status: j['subscription_status'] as String,
    billingCycle: j['billing_cycle'] as String,
    currency: j['currency'] as String? ?? 'PKR',
    outstandingAmount: (j['outstanding_amount'] as num?)?.toDouble() ?? 0,
    trialStartsAt: _date(j['trial_starts_at']),
    trialEndsAt: _date(j['trial_ends_at']),
    renewalDate: _date(j['renewal_date']),
    graceEndsAt: _date(j['grace_ends_at']),
  );
}

class BillingInvoice {
  final String id, number, status, currency;
  final double amount;
  final DateTime issuedAt;
  const BillingInvoice({
    required this.id,
    required this.number,
    required this.status,
    required this.currency,
    required this.amount,
    required this.issuedAt,
  });
  factory BillingInvoice.fromJson(Map<String, dynamic> j) => BillingInvoice(
    id: j['id'] as String,
    number: j['invoice_number'] as String,
    status: j['status'] as String,
    currency: j['currency'] as String,
    amount: (j['amount'] as num).toDouble(),
    issuedAt: DateTime.parse(j['issued_at'] as String),
  );
}

class BillingPayment {
  final String id, status, method, reference, currency;
  final double amount;
  final DateTime paidAt;
  const BillingPayment({
    required this.id,
    required this.status,
    required this.method,
    required this.reference,
    required this.currency,
    required this.amount,
    required this.paidAt,
  });
  factory BillingPayment.fromJson(Map<String, dynamic> j) => BillingPayment(
    id: j['id'] as String,
    status: j['status'] as String,
    method: j['method'] as String,
    reference: j['external_reference'] as String,
    currency: j['currency'] as String,
    amount: (j['amount'] as num).toDouble(),
    paidAt: DateTime.parse(j['paid_at'] as String),
  );
}

DateTime? _date(dynamic value) =>
    value == null ? null : DateTime.parse(value as String);
