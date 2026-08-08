enum SupplierAnalyticsPeriod {
  sevenDays(7, '7 days'),
  thirtyDays(30, '30 days'),
  ninetyDays(90, '90 days'),
  allTime(null, 'All time');

  const SupplierAnalyticsPeriod(this.days, this.label);
  final int? days;
  final String label;

  DateTime? get dateFrom =>
      days == null ? null : DateTime.now().subtract(Duration(days: days!));
}

enum SupplierProfitFilter {
  all('all', 'All products'),
  profit('profit', 'Profit'),
  loss('loss', 'Loss'),
  unsold('unsold', 'Unsold');

  const SupplierProfitFilter(this.value, this.label);
  final String value;
  final String label;
}

enum SupplierAnalyticsSort {
  revenue('revenue_desc', 'Revenue'),
  units('units_desc', 'Units sold'),
  highestProfit('profit_desc', 'Highest profit'),
  highestLoss('profit_asc', 'Highest loss'),
  name('name_asc', 'Product name');

  const SupplierAnalyticsSort(this.value, this.label);
  final String value;
  final String label;
}

int _integer(dynamic value) => (value as num?)?.toInt() ?? 0;
double _decimal(dynamic value) => (value as num?)?.toDouble() ?? 0;

class SupplierSalesSummary {
  const SupplierSalesSummary({
    required this.linkedProductCount,
    required this.sharedProductCount,
    required this.salesCount,
    required this.unitsSold,
    required this.revenue,
    required this.costOfSales,
    required this.grossProfit,
    required this.profitMargin,
  });

  final int linkedProductCount;
  final int sharedProductCount;
  final int salesCount;
  final int unitsSold;
  final double revenue;
  final double costOfSales;
  final double grossProfit;
  final double profitMargin;

  factory SupplierSalesSummary.fromMap(Map<String, dynamic> map) =>
      SupplierSalesSummary(
        linkedProductCount: _integer(map['linked_product_count']),
        sharedProductCount: _integer(map['shared_product_count']),
        salesCount: _integer(map['sales_count']),
        unitsSold: _integer(map['units_sold']),
        revenue: _decimal(map['sales_revenue']),
        costOfSales: _decimal(map['cost_of_sales']),
        grossProfit: _decimal(map['gross_profit']),
        profitMargin: _decimal(map['profit_margin']),
      );
}

class SupplierProductSalesRow {
  const SupplierProductSalesRow({
    required this.productId,
    required this.name,
    this.sku,
    required this.stock,
    required this.unitsSold,
    required this.revenue,
    required this.costOfSales,
    required this.grossProfit,
    required this.profitMargin,
    required this.isShared,
  });

  final String productId;
  final String name;
  final String? sku;
  final int stock;
  final int unitsSold;
  final double revenue;
  final double costOfSales;
  final double grossProfit;
  final double profitMargin;
  final bool isShared;

  factory SupplierProductSalesRow.fromMap(Map<String, dynamic> map) =>
      SupplierProductSalesRow(
        productId: map['product_id'] as String,
        name: map['product_name'] as String? ?? 'Unnamed product',
        sku: map['sku'] as String?,
        stock: _integer(map['stock']),
        unitsSold: _integer(map['units_sold']),
        revenue: _decimal(map['sales_revenue']),
        costOfSales: _decimal(map['cost_of_sales']),
        grossProfit: _decimal(map['gross_profit']),
        profitMargin: _decimal(map['profit_margin']),
        isShared: map['is_shared'] as bool? ?? false,
      );
}

class SupplierProductSalesPage {
  const SupplierProductSalesPage({required this.items, required this.total});
  final List<SupplierProductSalesRow> items;
  final int total;
}
