class MetricPoint {
  final String name;
  final int count;
  const MetricPoint(this.name, this.count);
  factory MetricPoint.fromJson(Map<String, dynamic> j) => MetricPoint(
    (j['name'] ?? j['month']) as String,
    (j['count'] as num).toInt(),
  );
}

class PlatformAnalytics {
  final int total, active, suspended, unpaidInvoices, trials, renewals;
  final double revenue, unpaidAmount;
  final String currency;
  final List<MetricPoint> growth, plans, features, addons;
  const PlatformAnalytics({
    required this.total,
    required this.active,
    required this.suspended,
    required this.unpaidInvoices,
    required this.trials,
    required this.renewals,
    required this.revenue,
    required this.unpaidAmount,
    required this.currency,
    required this.growth,
    required this.plans,
    required this.features,
    required this.addons,
  });
  factory PlatformAnalytics.fromJson(Map<String, dynamic> j) =>
      PlatformAnalytics(
        total: (j['total_tenants'] as num).toInt(),
        active: (j['active_tenants'] as num).toInt(),
        suspended: (j['suspended_tenants'] as num).toInt(),
        unpaidInvoices: (j['unpaid_invoice_count'] as num).toInt(),
        trials: (j['active_trials'] as num).toInt(),
        renewals: (j['upcoming_renewals'] as num).toInt(),
        revenue: (j['monthly_revenue'] as num).toDouble(),
        unpaidAmount: (j['unpaid_invoice_amount'] as num).toDouble(),
        currency: j['currency'] as String,
        growth: _points(j['tenant_growth']),
        plans: _points(j['plan_distribution']),
        features: _points(j['feature_usage']),
        addons: _points(j['addon_usage']),
      );
}

List<MetricPoint> _points(dynamic value) =>
    (value as List)
        .map((e) => MetricPoint.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();

class PlatformSettings {
  final int trialDays, graceDays;
  final String cycle, currency;
  final String? email, phone, message;
  final bool maintenance;
  const PlatformSettings({
    required this.trialDays,
    required this.graceDays,
    required this.cycle,
    required this.currency,
    required this.maintenance,
    this.email,
    this.phone,
    this.message,
  });
  factory PlatformSettings.fromJson(Map<String, dynamic> j) => PlatformSettings(
    trialDays: (j['trial_duration_days'] as num).toInt(),
    graceDays: (j['grace_period_days'] as num).toInt(),
    cycle: j['default_billing_cycle'] as String,
    currency: j['default_currency'] as String,
    maintenance: j['maintenance_mode'] as bool,
    email: j['support_email'] as String?,
    phone: j['support_phone'] as String?,
    message: j['maintenance_message'] as String?,
  );
}
