import '../../../core/entitlements/entitlement_evaluator.dart';

class ProcurementEntitlementGate {
  final EntitlementEvaluator _evaluator;
  const ProcurementEntitlementGate(this._evaluator);

  Future<void> require(String key) async {
    final specific = await _evaluator.evaluateFeature(key);
    final allowed =
        specific.source == EntitlementValueSource.unavailable
            ? await _evaluator.hasFeature('purchases.procurement')
            : specific.isEnabled;
    if (!allowed) throw EntitlementDeniedException(key);
  }
}
