import 'package:mobileshop_saas/core/local/local_database.dart';

class LedgerCashSummary {
  final double cashInShop;
  final double totalAvailableMoney;
  final double cashIn;
  final double cashOut;
  final Map<String, double> inflowBreakdown;
  final Map<String, double> outflowBreakdown;

  const LedgerCashSummary({
    required this.cashInShop,
    required this.totalAvailableMoney,
    required this.cashIn,
    required this.cashOut,
    this.inflowBreakdown = const {},
    this.outflowBreakdown = const {},
  });

  double get netCashFlow => cashIn - cashOut;

  static Future<LedgerCashSummary> load({
    required String tenantId,
    required String? branchId,
    required DateTime dateFrom,
    required DateTime dateTo,
  }) async {
    final accountRows = await LocalDatabase.select(
      '''
      SELECT account_type, current_balance, is_default
      FROM accounts
      WHERE tenant_id = ?
        ${branchId == null ? '' : 'AND branch_id = ?'}
        AND is_active = 1
      ''',
      [tenantId, if (branchId != null) branchId],
    );
    final cashAccounts =
        accountRows.where((row) => row['account_type'] == 'cash').toList();
    final defaultCash = cashAccounts.where(
      (row) => (row['is_default'] as num).toInt() == 1,
    );
    final drawerRows =
        defaultCash.length == 1 ? defaultCash.toList() : cashAccounts;
    final cashInShop = drawerRows.fold<double>(
      0,
      (sum, row) => sum + (row['current_balance'] as num).toDouble(),
    );
    final available = accountRows.fold<double>(
      0,
      (sum, row) => sum + (row['current_balance'] as num).toDouble(),
    );

    final movementRows = await LocalDatabase.select(
      '''
      SELECT direction,
             COALESCE(NULLIF(reference_type, ''), transaction_type) AS label,
             COALESCE(SUM(amount), 0) AS amount
      FROM account_transactions
      WHERE tenant_id = ?
        ${branchId == null ? '' : 'AND branch_id = ?'}
        AND transaction_type NOT IN ('transfer_in', 'transfer_out')
        AND substr(transaction_at, 1, 10) BETWEEN ? AND ?
      GROUP BY direction, label
      ''',
      [
        tenantId,
        if (branchId != null) branchId,
        _dateOnly(dateFrom),
        _dateOnly(dateTo),
      ],
    );
    final inflows = <String, double>{};
    final outflows = <String, double>{};
    for (final row in movementRows) {
      final target = row['direction'] == 'out' ? outflows : inflows;
      target[row['label'] as String] = (row['amount'] as num).toDouble();
    }
    return LedgerCashSummary(
      cashInShop: cashInShop,
      totalAvailableMoney: available,
      cashIn: inflows.values.fold(0, (sum, value) => sum + value),
      cashOut: outflows.values.fold(0, (sum, value) => sum + value),
      inflowBreakdown: inflows,
      outflowBreakdown: outflows,
    );
  }

  static String _dateOnly(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
}
