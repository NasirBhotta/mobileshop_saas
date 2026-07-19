import '../../../core/entitlements/entitlement_evaluator.dart';
import '../../../core/entitlements/entitlement_provider.dart';

class InventoryEntitlementGate {
  final EntitlementEvaluator _evaluator;
  const InventoryEntitlementGate(this._evaluator);

  Future<void> require(String featureKey) async {
    final allowed = await hasFeatureWithCompatibility(_evaluator, featureKey);
    if (!allowed) {
      throw EntitlementDeniedException(featureKey);
    }
  }
}
