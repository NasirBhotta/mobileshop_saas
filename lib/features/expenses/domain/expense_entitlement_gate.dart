import '../../../core/entitlements/entitlement_evaluator.dart';
import '../../../core/entitlements/entitlement_provider.dart';

class ExpenseEntitlementGate {
  final EntitlementEvaluator _evaluator;
  const ExpenseEntitlementGate(this._evaluator);

  Future<void> require(String key) async {
    if (!await hasFeatureWithCompatibility(_evaluator, key)) {
      throw EntitlementDeniedException(key);
    }
  }
}
