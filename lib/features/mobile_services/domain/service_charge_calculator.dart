import 'mobile_service_types.dart';

class ServiceChargeCalculator {
  const ServiceChargeCalculator._();

  static double calculateFee({
    required double amount,
    required ServiceChargeRule rule,
  }) {
    _requirePositiveFinite(amount, 'amount');
    _requireNonNegativeFinite(rule.rateAmount, 'rateAmount');
    _validateOptionalFee(rule.minimumFee, 'minimumFee');
    _validateOptionalFee(rule.maximumFee, 'maximumFee');

    if (rule.minimumFee != null &&
        rule.maximumFee != null &&
        rule.maximumFee! < rule.minimumFee!) {
      throw ArgumentError('maximumFee cannot be less than minimumFee.');
    }

    double fee;
    switch (rule.method) {
      case ServiceChargeCalculationMethod.fullSlab:
        final perAmount = _requirePerAmount(rule.perAmount);
        fee = (amount / perAmount).ceil() * rule.rateAmount;
      case ServiceChargeCalculationMethod.proportional:
        final perAmount = _requirePerAmount(rule.perAmount);
        fee = (amount / perAmount) * rule.rateAmount;
      case ServiceChargeCalculationMethod.fixed:
        fee = rule.rateAmount;
      case ServiceChargeCalculationMethod.manual:
        fee = 0;
    }

    if (rule.minimumFee != null && fee < rule.minimumFee!) {
      fee = rule.minimumFee!;
    }
    if (rule.maximumFee != null && fee > rule.maximumFee!) {
      fee = rule.maximumFee!;
    }

    return _money(fee);
  }

  static MobileServiceTransactionPreview buildPreview({
    required MobileServiceOperation operation,
    required double serviceAmount,
    required ServiceChargeRule rule,
    double? chargedFeeOverride,
  }) {
    final calculatedFee = calculateFee(amount: serviceAmount, rule: rule);

    if (rule.method == ServiceChargeCalculationMethod.manual &&
        chargedFeeOverride == null) {
      throw ArgumentError('A fee is required when the rule is manual.');
    }

    final chargedFee = chargedFeeOverride ?? calculatedFee;
    _requireNonNegativeFinite(chargedFee, 'chargedFee');

    switch (operation) {
      case MobileServiceOperation.send:
        return MobileServiceTransactionPreview(
          operation: operation,
          serviceAmount: _money(serviceAmount),
          calculatedFee: calculatedFee,
          chargedFee: _money(chargedFee),
          customerCashAmount: _money(serviceAmount + chargedFee),
          profitAmount: _money(chargedFee),
          cashDirection: MoneyDirection.moneyIn,
          providerWalletDirection: MoneyDirection.moneyOut,
        );
      case MobileServiceOperation.receive:
        if (chargedFee >= serviceAmount) {
          throw ArgumentError(
            'Receive fee must be less than the received amount.',
          );
        }
        return MobileServiceTransactionPreview(
          operation: operation,
          serviceAmount: _money(serviceAmount),
          calculatedFee: calculatedFee,
          chargedFee: _money(chargedFee),
          customerCashAmount: _money(serviceAmount - chargedFee),
          profitAmount: _money(chargedFee),
          cashDirection: MoneyDirection.moneyOut,
          providerWalletDirection: MoneyDirection.moneyIn,
        );
    }
  }

  static double _requirePerAmount(double? value) {
    if (value == null) {
      throw ArgumentError('perAmount is required for this calculation.');
    }
    _requirePositiveFinite(value, 'perAmount');
    return value;
  }

  static void _validateOptionalFee(double? value, String name) {
    if (value != null) _requireNonNegativeFinite(value, name);
  }

  static void _requirePositiveFinite(double value, String name) {
    if (!value.isFinite || value <= 0) {
      throw ArgumentError.value(value, name, 'Must be greater than zero');
    }
  }

  static void _requireNonNegativeFinite(double value, String name) {
    if (!value.isFinite || value < 0) {
      throw ArgumentError.value(value, name, 'Cannot be negative');
    }
  }

  static double _money(double value) => (value * 100).round() / 100;
}
