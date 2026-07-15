import '../../../core/entitlements/entitlement_evaluator.dart';

class PosEntitlementGate {
  final EntitlementEvaluator _evaluator;
  const PosEntitlementGate(this._evaluator);
  Future<void> require(String key) async {
    if (!await _evaluator.hasFeature(key)) {
      throw EntitlementDeniedException(key);
    }
  }
}
