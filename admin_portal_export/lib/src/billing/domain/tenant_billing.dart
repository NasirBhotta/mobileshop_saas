class BillingSummary {
  final String subscriptionId, plan, status, billingCycle, currency;
  final DateTime? trialStartsAt,
      trialEndsAt,
      renewalDate,
      graceEndsAt,
      expiresAt,
      cancellationRequestedAt;
  final bool cancelAtPeriodEnd;
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
    this.expiresAt,
    this.cancellationRequestedAt,
    this.cancelAtPeriodEnd = false,
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
    expiresAt: _date(j['expires_at']),
    cancellationRequestedAt: _date(j['cancellation_requested_at']),
    cancelAtPeriodEnd: j['cancel_at_period_end'] as bool? ?? false,
  );
}

class BillingInvoice {
  final String id, number, status, currency;
  final double amount;
  final DateTime issuedAt;
  final String? planName, billingCycle;
  const BillingInvoice({
    required this.id,
    required this.number,
    required this.status,
    required this.currency,
    required this.amount,
    required this.issuedAt,
    this.planName,
    this.billingCycle,
  });
  factory BillingInvoice.fromJson(Map<String, dynamic> j) => BillingInvoice(
    id: j['id'] as String,
    number: j['invoice_number'] as String,
    status: j['status'] as String,
    currency: j['currency'] as String,
    amount: (j['amount'] as num).toDouble(),
    issuedAt: DateTime.parse(j['issued_at'] as String),
    planName: j['plan_name_snapshot'] as String?,
    billingCycle: j['billing_cycle'] as String?,
  );
}

class BillingPlan {
  final String id, name;
  final double? monthlyPrice;

  const BillingPlan({required this.id, required this.name, this.monthlyPrice});

  factory BillingPlan.fromJson(Map<String, dynamic> json) => BillingPlan(
    id: json['id'] as String,
    name: json['name'] as String,
    monthlyPrice: (json['monthly_price'] as num?)?.toDouble(),
  );
}

class BillingPayment {
  final String id, status, method, reference, currency;
  final double amount;
  final DateTime paidAt;
  final String? invoiceId;
  const BillingPayment({
    required this.id,
    required this.status,
    required this.method,
    required this.reference,
    required this.currency,
    required this.amount,
    required this.paidAt,
    this.invoiceId,
  });
  factory BillingPayment.fromJson(Map<String, dynamic> j) => BillingPayment(
    id: j['id'] as String,
    status: j['status'] as String,
    method: j['method'] as String,
    reference: j['external_reference'] as String,
    currency: j['currency'] as String,
    amount: (j['amount'] as num).toDouble(),
    paidAt: DateTime.parse(j['paid_at'] as String),
    invoiceId: j['invoice_id'] as String?,
  );
}

DateTime? _date(dynamic value) =>
    value == null ? null : DateTime.parse(value as String);
