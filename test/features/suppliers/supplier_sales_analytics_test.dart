import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobileshop_saas/features/suppliers/data/models/supplier_sales_analytics_models.dart';

void main() {
  test('analytics models parse server numeric values safely', () {
    final summary = SupplierSalesSummary.fromMap({
      'linked_product_count': 12,
      'shared_product_count': 2,
      'sales_count': 8,
      'units_sold': 15,
      'sales_revenue': 3000,
      'cost_of_sales': 1900,
      'gross_profit': 1100,
      'profit_margin': 36.666,
    });

    expect(summary.linkedProductCount, 12);
    expect(summary.sharedProductCount, 2);
    expect(summary.grossProfit, 1100);
    expect(SupplierAnalyticsPeriod.thirtyDays.days, 30);
  });

  test('SQL analytics is read-only, paged, return-aware and branch-safe', () {
    final sql =
        File(
          'supabase/migrations/20260808000200_supplier_sales_analytics.sql',
        ).readAsStringSync().toLowerCase();

    expect(sql, contains('security invoker'));
    expect(sql, contains('current_user_can_access_branch'));
    expect(sql, contains("s.status = 'completed'"));
    expect(sql, contains("sr.status = 'approved'"));
    expect(sql, contains('returned_quantity'));
    expect(sql, contains('supplier_count = 1'));
    expect(
      sql,
      contains('limit least(greatest(coalesce(p_limit, 50), 1), 100)'),
    );
    expect(sql, contains('offset greatest(coalesce(p_offset, 0), 0)'));
    expect(sql, isNot(contains('insert into')));
    expect(sql, isNot(contains('update public.')));
    expect(sql, isNot(contains('delete from')));
  });

  test('screen exposes scalable controls and no dialog product tab', () {
    final screen =
        File(
          'lib/features/suppliers/presentation/screens/supplier_sales_analytics_screen.dart',
        ).readAsStringSync();
    final dialog =
        File(
          'lib/features/suppliers/presentation/widgets/supplier_history_dialog.dart',
        ).readAsStringSync();
    final liveDialog = dialog.substring(
      0,
      dialog.indexOf('class _SupplierProductsAnalytics'),
    );

    expect(screen, contains('Search product, SKU or barcode'));
    expect(screen, contains('static const _pageSize = 50'));
    expect(screen, contains('approved returns deducted'));
    expect(screen, contains('Shared • excluded'));
    expect(liveDialog, isNot(contains("Tab(text: 'Products & Sales')")));
  });
}
