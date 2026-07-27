import 'package:flutter_test/flutter_test.dart';
import 'package:mobileshop_saas/features/dashboard/domain/dashboard_financial_contract.dart';

void main() {
  group('dashboard financial metric definitions', () {
    test('every public dashboard metric has one canonical definition', () {
      expect(
        DashboardFinancialContract.definitions.keys.toSet(),
        DashboardMetricKey.values.toSet(),
      );
    });

    test('balances and period activity are explicitly separated', () {
      final definitions = DashboardFinancialContract.definitions;

      expect(
        definitions[DashboardMetricKey.cashInShop]!.basis,
        DashboardMetricBasis.currentBalance,
      );
      expect(
        definitions[DashboardMetricKey.customerOutstanding]!.basis,
        DashboardMetricBasis.currentBalance,
      );
      expect(
        definitions[DashboardMetricKey.cashInToday]!.basis,
        DashboardMetricBasis.todayActivity,
      );
      expect(
        definitions[DashboardMetricKey.netProfitToday]!.basis,
        DashboardMetricBasis.todayActivity,
      );
    });
  });

  group('available money', () {
    test('includes only active accounts configured for consolidation', () {
      const accounts = [
        DashboardAccountBalance(balance: 12000),
        DashboardAccountBalance(balance: 2000),
        DashboardAccountBalance(balance: 5000, includeInAvailableMoney: false),
        DashboardAccountBalance(balance: 7000, isActive: false),
      ];

      expect(DashboardFinancialContract.availableMoney(accounts), 14000);
    });
  });

  group('cash flow', () {
    test('own-account transfers do not change consolidated cash flow', () {
      const movements = [
        DashboardMoneyMovement(
          kind: DashboardMoneyMovementKind.ownAccountTransfer,
          amount: 2000,
        ),
        DashboardMoneyMovement(
          kind: DashboardMoneyMovementKind.ownAccountTransfer,
          amount: 2000,
        ),
      ];

      expect(DashboardFinancialContract.cashIn(movements), 0);
      expect(DashboardFinancialContract.cashOut(movements), 0);
      expect(DashboardFinancialContract.netCashFlow(movements), 0);
    });

    test('external inflows and outflows produce net cash flow', () {
      const movements = [
        DashboardMoneyMovement(
          kind: DashboardMoneyMovementKind.externalIn,
          amount: 5000,
        ),
        DashboardMoneyMovement(
          kind: DashboardMoneyMovementKind.externalIn,
          amount: 1000,
        ),
        DashboardMoneyMovement(
          kind: DashboardMoneyMovementKind.externalOut,
          amount: 1500,
        ),
      ];

      expect(DashboardFinancialContract.cashIn(movements), 6000);
      expect(DashboardFinancialContract.cashOut(movements), 1500);
      expect(DashboardFinancialContract.netCashFlow(movements), 4500);
    });

    test('reversed movements do not affect the summary', () {
      const movements = [
        DashboardMoneyMovement(
          kind: DashboardMoneyMovementKind.externalIn,
          amount: 5000,
          isReversed: true,
        ),
        DashboardMoneyMovement(
          kind: DashboardMoneyMovementKind.externalOut,
          amount: 1000,
          isReversed: true,
        ),
      ];

      expect(DashboardFinancialContract.netCashFlow(movements), 0);
    });
  });

  group('profit', () {
    test('gross profit excludes operating expenses', () {
      final grossProfit = DashboardFinancialContract.grossProfit(
        revenue: 10000,
        directCost: 7000,
      );

      expect(grossProfit, 3000);
    });

    test('net profit subtracts confirmed expenses from gross profit', () {
      final netProfit = DashboardFinancialContract.netProfit(
        grossProfit: 3000,
        confirmedExpenses: 800,
      );

      expect(netProfit, 2200);
    });
  });
}
