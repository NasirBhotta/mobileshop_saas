import '../../../core/entitlements/entitlement_evaluator.dart';

class ReportEntitlementGate {
  final EntitlementEvaluator _evaluator;
  const ReportEntitlementGate(this._evaluator);

  Future<bool> allows(String key) async {
    final specific = await _evaluator.evaluateFeature(key);
    if (specific.source != EntitlementValueSource.unavailable) {
      return specific.isEnabled;
    }
    return switch (key) {
      'reports.sales' ||
      'reports.business' => _evaluator.hasFeature('reports.access'),
      'reports.scheduled' => _evaluator.hasFeature('reports.scheduling'),
      _ => false,
    };
  }

  Future<void> require(String key) async {
    if (!await allows(key)) throw EntitlementDeniedException(key);
  }
}
