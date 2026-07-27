/// Canonical accounting definitions shared by the dashboard and reports.
///
/// This contract deliberately separates balances (a point in time), cash flow
/// (movement during a period), and profit (economic performance). Data-source
/// adapters should classify source records before passing them to this model.
enum DashboardMetricKey {
  cashInShop,
  totalAvailableMoney,
  cashInToday,
  cashOutToday,
  netCashFlowToday,
  salesToday,
  grossProfitToday,
  netProfitToday,
  customerOutstanding,
}

enum DashboardMetricBasis { currentBalance, todayActivity }

class DashboardMetricDefinition {
  final DashboardMetricKey key;
  final String label;
  final String meaning;
  final DashboardMetricBasis basis;
  final String formula;

  const DashboardMetricDefinition({
    required this.key,
    required this.label,
    required this.meaning,
    required this.basis,
    required this.formula,
  });
}

abstract final class DashboardFinancialContract {
  static const definitions = <DashboardMetricKey, DashboardMetricDefinition>{
    DashboardMetricKey.cashInShop: DashboardMetricDefinition(
      key: DashboardMetricKey.cashInShop,
      label: 'Cash in Shop',
      meaning: 'Current balance of the branch primary physical-cash account.',
      basis: DashboardMetricBasis.currentBalance,
      formula: 'primary drawer account current balance',
    ),
    DashboardMetricKey.totalAvailableMoney: DashboardMetricDefinition(
      key: DashboardMetricKey.totalAvailableMoney,
      label: 'Total Available Money',
      meaning:
          'Current balances of active accounts configured as available money.',
      basis: DashboardMetricBasis.currentBalance,
      formula: 'sum of included active account balances',
    ),
    DashboardMetricKey.cashInToday: DashboardMetricDefinition(
      key: DashboardMetricKey.cashInToday,
      label: 'Cash In Today',
      meaning:
          'External money received today; own-account transfers are excluded.',
      basis: DashboardMetricBasis.todayActivity,
      formula: 'sum of external inflows',
    ),
    DashboardMetricKey.cashOutToday: DashboardMetricDefinition(
      key: DashboardMetricKey.cashOutToday,
      label: 'Cash Out Today',
      meaning: 'External money paid today; own-account transfers are excluded.',
      basis: DashboardMetricBasis.todayActivity,
      formula: 'sum of external outflows',
    ),
    DashboardMetricKey.netCashFlowToday: DashboardMetricDefinition(
      key: DashboardMetricKey.netCashFlowToday,
      label: 'Net Cash Flow Today',
      meaning: 'Net external movement across included monetary accounts today.',
      basis: DashboardMetricBasis.todayActivity,
      formula: 'cash in today - cash out today',
    ),
    DashboardMetricKey.salesToday: DashboardMetricDefinition(
      key: DashboardMetricKey.salesToday,
      label: 'Sales Today',
      meaning:
          'Completed sales today across cash and non-cash payment methods, '
          'including credit.',
      basis: DashboardMetricBasis.todayActivity,
      formula: 'sum of completed sale revenue',
    ),
    DashboardMetricKey.grossProfitToday: DashboardMetricDefinition(
      key: DashboardMetricKey.grossProfitToday,
      label: 'Gross Profit Today',
      meaning:
          'Revenue earned today less its direct cost of goods or services.',
      basis: DashboardMetricBasis.todayActivity,
      formula: 'revenue - direct cost',
    ),
    DashboardMetricKey.netProfitToday: DashboardMetricDefinition(
      key: DashboardMetricKey.netProfitToday,
      label: 'Net Profit Today',
      meaning: 'Gross profit today less confirmed operating expenses.',
      basis: DashboardMetricBasis.todayActivity,
      formula: 'gross profit - confirmed expenses',
    ),
    DashboardMetricKey.customerOutstanding: DashboardMetricDefinition(
      key: DashboardMetricKey.customerOutstanding,
      label: 'Customer Udhar',
      meaning: 'Current customer receivables that remain unpaid.',
      basis: DashboardMetricBasis.currentBalance,
      formula: 'credit issued - credit collected - credit reversed',
    ),
  };

  static double availableMoney(Iterable<DashboardAccountBalance> accounts) {
    return accounts
        .where((account) => account.isActive && account.includeInAvailableMoney)
        .fold(0, (total, account) => total + account.balance);
  }

  static double cashIn(Iterable<DashboardMoneyMovement> movements) {
    return movements
        .where(
          (movement) =>
              movement.kind == DashboardMoneyMovementKind.externalIn &&
              !movement.isReversed,
        )
        .fold(0, (total, movement) => total + movement.amount);
  }

  static double cashOut(Iterable<DashboardMoneyMovement> movements) {
    return movements
        .where(
          (movement) =>
              movement.kind == DashboardMoneyMovementKind.externalOut &&
              !movement.isReversed,
        )
        .fold(0, (total, movement) => total + movement.amount);
  }

  static double netCashFlow(Iterable<DashboardMoneyMovement> movements) {
    return cashIn(movements) - cashOut(movements);
  }

  static double grossProfit({
    required double revenue,
    required double directCost,
  }) {
    return revenue - directCost;
  }

  static double netProfit({
    required double grossProfit,
    required double confirmedExpenses,
  }) {
    return grossProfit - confirmedExpenses;
  }
}

class DashboardAccountBalance {
  final double balance;
  final bool isActive;
  final bool includeInAvailableMoney;

  const DashboardAccountBalance({
    required this.balance,
    this.isActive = true,
    this.includeInAvailableMoney = true,
  });
}

enum DashboardMoneyMovementKind { externalIn, externalOut, ownAccountTransfer }

class DashboardMoneyMovement {
  final DashboardMoneyMovementKind kind;
  final double amount;
  final bool isReversed;

  const DashboardMoneyMovement({
    required this.kind,
    required this.amount,
    this.isReversed = false,
  }) : assert(amount >= 0, 'Movement amount cannot be negative.');
}
