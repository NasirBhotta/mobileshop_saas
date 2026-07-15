import '../../../core/entitlements/entitlement_evaluator.dart';

class AccountEntitlementGate {
  final EntitlementEvaluator _evaluator;
  const AccountEntitlementGate(this._evaluator);

  Future<void> require(String key) async {
    if (!await _evaluator.hasFeature(key)) {
      throw EntitlementDeniedException(key);
    }
  }
}
