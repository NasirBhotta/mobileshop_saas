import '../../accounts/data/models/account_models.dart';
import '../data/models/expense_models.dart';

class ExpenseAccountPolicy {
  const ExpenseAccountPolicy._();

  static bool isCompatible(ExpensePaymentMode mode, AccountModel account) {
    if (!account.isActive) return false;
    switch (mode) {
      case ExpensePaymentMode.cash:
        return account.type == AccountType.cash;
      case ExpensePaymentMode.easypaisa:
      case ExpensePaymentMode.jazzcash:
        return account.type == AccountType.mobileWallet;
      case ExpensePaymentMode.card:
        return account.type == AccountType.card ||
            account.type == AccountType.bank;
      case ExpensePaymentMode.bankTransfer:
      case ExpensePaymentMode.cheque:
        return account.type == AccountType.bank;
      case ExpensePaymentMode.other:
        return true;
    }
  }

  static List<AccountModel> compatible(
    ExpensePaymentMode mode,
    Iterable<AccountModel> accounts,
  ) => accounts.where((account) => isCompatible(mode, account)).toList();

  static AccountModel? suggested(
    ExpensePaymentMode mode,
    Iterable<AccountModel> accounts,
  ) {
    final compatibleAccounts = compatible(mode, accounts);
    final defaults =
        compatibleAccounts.where((account) => account.isDefault).toList();
    if (defaults.length == 1) return defaults.single;
    return compatibleAccounts.length == 1 ? compatibleAccounts.single : null;
  }
}
