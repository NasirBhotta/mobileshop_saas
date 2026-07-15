import '../../../core/entitlements/entitlement_evaluator.dart';

class ExpenseEntitlementGate {
  final EntitlementEvaluator _evaluator;
  const ExpenseEntitlementGate(this._evaluator);

  Future<void> require(String key) async {
    if (!await _evaluator.hasFeature(key)) {
      throw EntitlementDeniedException(key);
    }
  }
}
