import '../../../core/entitlements/entitlement_evaluator.dart';

class PosEntitlementGate {
  final EntitlementEvaluator _evaluator;
  const PosEntitlementGate(this._evaluator);
  Future<void> require(String key) async {
    final specific = await _evaluator.evaluateFeature(key);
    final allowed =
        specific.source == EntitlementValueSource.unavailable
            ? await _evaluator.hasFeature('pos.access')
            : specific.isEnabled;
    if (!allowed) {
      throw EntitlementDeniedException(key);
    }
  }
}
