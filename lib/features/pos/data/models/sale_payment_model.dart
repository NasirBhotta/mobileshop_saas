// Payment methods enum
enum PaymentMethod { cash, easypaisa, jazzcash, card, credit }

extension PaymentMethodX on PaymentMethod {
  String get code {
    switch (this) {
      case PaymentMethod.cash:
        return 'cash';
      case PaymentMethod.easypaisa:
        return 'easypaisa';
      case PaymentMethod.jazzcash:
        return 'jazzcash';
      case PaymentMethod.card:
        return 'card';
      case PaymentMethod.credit:
        return 'credit';
    }
  }

  String get label {
    switch (this) {
      case PaymentMethod.cash:
        return 'Cash';
      case PaymentMethod.easypaisa:
        return 'EasyPaisa';
      case PaymentMethod.jazzcash:
        return 'JazzCash';
      case PaymentMethod.card:
        return 'Card';
      case PaymentMethod.credit:
        return 'Khata';
    }
  }

  // Icon ke liye
  String get iconAsset {
    switch (this) {
      case PaymentMethod.cash:
        return 'cash';
      case PaymentMethod.easypaisa:
        return 'easypaisa';
      case PaymentMethod.jazzcash:
        return 'jazzcash';
      case PaymentMethod.card:
        return 'card';
      case PaymentMethod.credit:
        return 'credit';
    }
  }

  static PaymentMethod fromCode(String code) {
    switch (code) {
      case 'easypaisa':
        return PaymentMethod.easypaisa;
      case 'jazzcash':
        return PaymentMethod.jazzcash;
      case 'card':
        return PaymentMethod.card;
      case 'credit':
        return PaymentMethod.credit;
      default:
        return PaymentMethod.cash;
    }
  }
}

class SalePaymentModel {
  final String? id;
  final String? saleId;
  final PaymentMethod method;
  final double amount;

  const SalePaymentModel({
    this.id,
    this.saleId,
    required this.method,
    required this.amount,
  });

  factory SalePaymentModel.fromMap(Map<String, dynamic> map) {
    return SalePaymentModel(
      id: map['id'] as String?,
      saleId: map['sale_id'] as String?,
      method: PaymentMethodX.fromCode(map['method'] as String),
      amount: (map['amount'] as num).toDouble(),
    );
  }

  Map<String, dynamic> toMap() => {'method': method.code, 'amount': amount};

  SalePaymentModel copyWith({double? amount}) {
    return SalePaymentModel(
      id: id,
      saleId: saleId,
      method: method,
      amount: amount ?? this.amount,
    );
  }
}
