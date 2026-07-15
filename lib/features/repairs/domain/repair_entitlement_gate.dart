import '../../../core/entitlements/entitlement_evaluator.dart';

class RepairEntitlementGate {
  final EntitlementEvaluator _evaluator;
  const RepairEntitlementGate(this._evaluator);
  Future<void> require(String key) async {
    if (!await _evaluator.hasFeature(key)) {
      throw EntitlementDeniedException(key);
    }
  }
}
