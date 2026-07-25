enum MobileServiceCategory {
  moneyTransfer;

  String get code => 'money_transfer';

  static MobileServiceCategory fromCode(String code) {
    switch (code) {
      case 'money_transfer':
        return MobileServiceCategory.moneyTransfer;
      default:
        throw ArgumentError.value(code, 'code', 'Unsupported service category');
    }
  }
}

enum MobileServiceProviderCode {
  easypaisa,
  jazzcash;

  String get code => name;

  String get label {
    switch (this) {
      case MobileServiceProviderCode.easypaisa:
        return 'Easypaisa';
      case MobileServiceProviderCode.jazzcash:
        return 'JazzCash';
    }
  }

  static MobileServiceProviderCode fromCode(String code) {
    switch (code) {
      case 'easypaisa':
        return MobileServiceProviderCode.easypaisa;
      case 'jazzcash':
        return MobileServiceProviderCode.jazzcash;
      default:
        throw ArgumentError.value(code, 'code', 'Unsupported provider');
    }
  }
}

enum MobileServiceOperation {
  send,
  receive;

  String get code => name;

  String get label {
    switch (this) {
      case MobileServiceOperation.send:
        return 'Send Money';
      case MobileServiceOperation.receive:
        return 'Receive Money';
    }
  }

  static MobileServiceOperation fromCode(String code) {
    switch (code) {
      case 'send':
        return MobileServiceOperation.send;
      case 'receive':
        return MobileServiceOperation.receive;
      default:
        throw ArgumentError.value(code, 'code', 'Unsupported operation');
    }
  }
}

enum ServiceChargeCalculationMethod {
  fullSlab,
  proportional,
  fixed,
  manual;

  String get code {
    switch (this) {
      case ServiceChargeCalculationMethod.fullSlab:
        return 'full_slab';
      case ServiceChargeCalculationMethod.proportional:
        return 'proportional';
      case ServiceChargeCalculationMethod.fixed:
        return 'fixed';
      case ServiceChargeCalculationMethod.manual:
        return 'manual';
    }
  }

  static ServiceChargeCalculationMethod fromCode(String code) {
    switch (code) {
      case 'full_slab':
        return ServiceChargeCalculationMethod.fullSlab;
      case 'proportional':
        return ServiceChargeCalculationMethod.proportional;
      case 'fixed':
        return ServiceChargeCalculationMethod.fixed;
      case 'manual':
        return ServiceChargeCalculationMethod.manual;
      default:
        throw ArgumentError.value(code, 'code', 'Unsupported charge method');
    }
  }
}

enum MoneyDirection {
  moneyIn,
  moneyOut;

  String get code {
    switch (this) {
      case MoneyDirection.moneyIn:
        return 'in';
      case MoneyDirection.moneyOut:
        return 'out';
    }
  }
}

class ServiceChargeRule {
  final ServiceChargeCalculationMethod method;
  final double rateAmount;
  final double? perAmount;
  final double? minimumFee;
  final double? maximumFee;

  const ServiceChargeRule({
    required this.method,
    required this.rateAmount,
    this.perAmount,
    this.minimumFee,
    this.maximumFee,
  });
}

class MobileServiceTransactionPreview {
  final MobileServiceOperation operation;
  final double serviceAmount;
  final double calculatedFee;
  final double chargedFee;
  final double customerCashAmount;
  final double profitAmount;
  final MoneyDirection cashDirection;
  final MoneyDirection providerWalletDirection;

  const MobileServiceTransactionPreview({
    required this.operation,
    required this.serviceAmount,
    required this.calculatedFee,
    required this.chargedFee,
    required this.customerCashAmount,
    required this.profitAmount,
    required this.cashDirection,
    required this.providerWalletDirection,
  });
}
