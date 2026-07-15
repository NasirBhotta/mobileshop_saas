import '../../../core/entitlements/entitlement_evaluator.dart';

class InventoryEntitlementGate {
  final EntitlementEvaluator _evaluator;
  const InventoryEntitlementGate(this._evaluator);

  Future<void> require(String featureKey) async {
    final specific = await _evaluator.evaluateFeature(featureKey);
    final allowed =
        specific.source == EntitlementValueSource.unavailable
            ? await _evaluator.hasFeature('inventory.access')
            : specific.isEnabled;
    if (!allowed) {
      throw EntitlementDeniedException(featureKey);
    }
  }
}
