import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../inventory/presentation/providers/inventory_provider.dart';
import '../../../pos/data/models/sale_model.dart';
import '../../../pos/presentation/providers/pos_provider.dart';

final dashboardStatsProvider = FutureProvider<DashboardStats>((ref) async {
  final products = await ref.watch(allProductsProvider.future);
  final sales = await ref.watch(salesHistoryProvider.future);

  final totalStock = products.fold<int>(
    0,
    (sum, product) => sum + product.stock,
  );
  final lowStock = products.where((product) => product.stock <= 5).length;
  final today = DateTime.now();
  final todaySales =
      sales.where((sale) {
        final createdAt = sale.createdAt;
        if (createdAt == null || sale.status != SaleStatus.completed) {
          return false;
        }
        return createdAt.year == today.year &&
            createdAt.month == today.month &&
            createdAt.day == today.day;
      }).toList();
  final todaySalesTotal = todaySales.fold<double>(
    0,
    (sum, sale) => sum + sale.total,
  );

  return DashboardStats(
    totalStock: totalStock,
    lowStock: lowStock,
    todaySalesTotal: todaySalesTotal,
    recentSales: sales.take(5).toList(),
  );
});

class DashboardStats {
  final int totalStock;
  final int lowStock;
  final double todaySalesTotal;
  final List<SaleModel> recentSales;

  const DashboardStats({
    required this.totalStock,
    required this.lowStock,
    required this.todaySalesTotal,
    required this.recentSales,
  });
}
