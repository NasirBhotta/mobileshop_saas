import 'package:flutter_test/flutter_test.dart';
import 'package:mobileshop_saas/features/mobile_services/domain/mobile_service_types.dart';
import 'package:mobileshop_saas/features/mobile_services/domain/service_charge_calculator.dart';

void main() {
  group('ServiceChargeCalculator.calculateFee', () {
    test('full slab charges the full rate for a partial slab', () {
      const rule = ServiceChargeRule(
        method: ServiceChargeCalculationMethod.fullSlab,
        rateAmount: 20,
        perAmount: 1000,
      );

      expect(ServiceChargeCalculator.calculateFee(amount: 500, rule: rule), 20);
      expect(
        ServiceChargeCalculator.calculateFee(amount: 1000, rule: rule),
        20,
      );
      expect(
        ServiceChargeCalculator.calculateFee(amount: 1001, rule: rule),
        40,
      );
    });

    test('proportional method charges according to the entered amount', () {
      const rule = ServiceChargeRule(
        method: ServiceChargeCalculationMethod.proportional,
        rateAmount: 20,
        perAmount: 1000,
      );

      expect(ServiceChargeCalculator.calculateFee(amount: 500, rule: rule), 10);
      expect(
        ServiceChargeCalculator.calculateFee(amount: 1250, rule: rule),
        25,
      );
    });

    test('fixed method ignores the service amount', () {
      const rule = ServiceChargeRule(
        method: ServiceChargeCalculationMethod.fixed,
        rateAmount: 30,
      );

      expect(ServiceChargeCalculator.calculateFee(amount: 100, rule: rule), 30);
      expect(
        ServiceChargeCalculator.calculateFee(amount: 5000, rule: rule),
        30,
      );
    });

    test('minimum and maximum limits are applied', () {
      const minimumRule = ServiceChargeRule(
        method: ServiceChargeCalculationMethod.proportional,
        rateAmount: 20,
        perAmount: 1000,
        minimumFee: 15,
      );
      const maximumRule = ServiceChargeRule(
        method: ServiceChargeCalculationMethod.fullSlab,
        rateAmount: 20,
        perAmount: 1000,
        maximumFee: 50,
      );

      expect(
        ServiceChargeCalculator.calculateFee(amount: 500, rule: minimumRule),
        15,
      );
      expect(
        ServiceChargeCalculator.calculateFee(amount: 5000, rule: maximumRule),
        50,
      );
    });

    test('invalid amounts and invalid rules are rejected', () {
      const missingPerAmount = ServiceChargeRule(
        method: ServiceChargeCalculationMethod.fullSlab,
        rateAmount: 20,
      );
      const invalidLimits = ServiceChargeRule(
        method: ServiceChargeCalculationMethod.fixed,
        rateAmount: 20,
        minimumFee: 30,
        maximumFee: 10,
      );

      expect(
        () => ServiceChargeCalculator.calculateFee(
          amount: 0,
          rule: missingPerAmount,
        ),
        throwsArgumentError,
      );
      expect(
        () => ServiceChargeCalculator.calculateFee(
          amount: 1000,
          rule: missingPerAmount,
        ),
        throwsArgumentError,
      );
      expect(
        () => ServiceChargeCalculator.calculateFee(
          amount: 1000,
          rule: invalidLimits,
        ),
        throwsArgumentError,
      );
    });
  });

  group('ServiceChargeCalculator.buildPreview', () {
    const fullSlabRule = ServiceChargeRule(
      method: ServiceChargeCalculationMethod.fullSlab,
      rateAmount: 20,
      perAmount: 1000,
    );

    test('send adds the fee to customer cash', () {
      final preview = ServiceChargeCalculator.buildPreview(
        operation: MobileServiceOperation.send,
        serviceAmount: 800,
        rule: fullSlabRule,
      );

      expect(preview.calculatedFee, 20);
      expect(preview.chargedFee, 20);
      expect(preview.customerCashAmount, 820);
      expect(preview.profitAmount, 20);
      expect(preview.cashDirection, MoneyDirection.moneyIn);
      expect(preview.providerWalletDirection, MoneyDirection.moneyOut);
    });

    test('receive subtracts the fee from customer cash', () {
      final preview = ServiceChargeCalculator.buildPreview(
        operation: MobileServiceOperation.receive,
        serviceAmount: 800,
        rule: fullSlabRule,
      );

      expect(preview.calculatedFee, 20);
      expect(preview.chargedFee, 20);
      expect(preview.customerCashAmount, 780);
      expect(preview.profitAmount, 20);
      expect(preview.cashDirection, MoneyDirection.moneyOut);
      expect(preview.providerWalletDirection, MoneyDirection.moneyIn);
    });

    test('user can override a calculated fee', () {
      final preview = ServiceChargeCalculator.buildPreview(
        operation: MobileServiceOperation.send,
        serviceAmount: 800,
        rule: fullSlabRule,
        chargedFeeOverride: 15,
      );

      expect(preview.calculatedFee, 20);
      expect(preview.chargedFee, 15);
      expect(preview.customerCashAmount, 815);
      expect(preview.profitAmount, 15);
    });

    test('manual method requires a user-entered fee', () {
      const manualRule = ServiceChargeRule(
        method: ServiceChargeCalculationMethod.manual,
        rateAmount: 0,
      );

      expect(
        () => ServiceChargeCalculator.buildPreview(
          operation: MobileServiceOperation.send,
          serviceAmount: 800,
          rule: manualRule,
        ),
        throwsArgumentError,
      );

      final preview = ServiceChargeCalculator.buildPreview(
        operation: MobileServiceOperation.send,
        serviceAmount: 800,
        rule: manualRule,
        chargedFeeOverride: 25,
      );
      expect(preview.calculatedFee, 0);
      expect(preview.chargedFee, 25);
      expect(preview.customerCashAmount, 825);
    });

    test('receive rejects a fee greater than the received amount', () {
      expect(
        () => ServiceChargeCalculator.buildPreview(
          operation: MobileServiceOperation.receive,
          serviceAmount: 20,
          rule: fullSlabRule,
          chargedFeeOverride: 25,
        ),
        throwsArgumentError,
      );
    });
  });
}
