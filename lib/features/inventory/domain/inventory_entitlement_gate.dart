import '../../../core/entitlements/entitlement_evaluator.dart';

class InventoryEntitlementGate {
  final EntitlementEvaluator _evaluator;
  const InventoryEntitlementGate(this._evaluator);

  Future<void> require(String featureKey) async {
    if (!await _evaluator.hasFeature(featureKey)) {
      throw EntitlementDeniedException(featureKey);
    }
  }
}
