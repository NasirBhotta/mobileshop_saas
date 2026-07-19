import '../../../core/entitlements/entitlement_evaluator.dart';
import '../../../core/entitlements/entitlement_provider.dart';

class PosEntitlementGate {
  final EntitlementEvaluator _evaluator;
  const PosEntitlementGate(this._evaluator);
  Future<void> require(String key) async {
    final allowed = await hasFeatureWithCompatibility(_evaluator, key);
    if (!allowed) {
      throw EntitlementDeniedException(key);
    }
  }
}
