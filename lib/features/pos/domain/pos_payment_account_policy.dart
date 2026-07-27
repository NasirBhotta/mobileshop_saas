import '../../accounts/data/models/account_models.dart';
import '../data/models/sale_payment_model.dart';

class PosPaymentAccountPolicy {
  const PosPaymentAccountPolicy._();

  static bool requiresAccount(PaymentMethod method) =>
      method != PaymentMethod.credit;

  static bool isCompatible(PaymentMethod method, AccountModel account) {
    if (!account.isActive) return false;
    switch (method) {
      case PaymentMethod.cash:
        return account.type == AccountType.cash;
      case PaymentMethod.easypaisa:
      case PaymentMethod.jazzcash:
        return account.type == AccountType.mobileWallet;
      case PaymentMethod.card:
        return account.type == AccountType.card ||
            account.type == AccountType.bank;
      case PaymentMethod.credit:
        return false;
    }
  }

  static List<AccountModel> compatibleAccounts(
    PaymentMethod method,
    Iterable<AccountModel> accounts,
  ) => accounts.where((account) => isCompatible(method, account)).toList();

  static AccountModel? suggestedAccount(
    PaymentMethod method,
    Iterable<AccountModel> accounts,
  ) {
    final compatible = compatibleAccounts(method, accounts);
    if (compatible.isEmpty) return null;
    final defaults = compatible.where((account) => account.isDefault).toList();
    if (defaults.length == 1) return defaults.single;
    return compatible.length == 1 ? compatible.single : null;
  }
}
