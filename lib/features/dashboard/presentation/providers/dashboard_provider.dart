import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../inventory/presentation/providers/inventory_provider.dart';

final dashboardStatsProvider = FutureProvider<DashboardStats>((ref) async {
  final products = await ref.watch(allProductsProvider.future);

  final totalStock = products.fold<int>(
    0,
    (sum, product) => sum + product.stock,
  );
  final lowStock = products.where((product) => product.stock <= 5).length;

  return DashboardStats(totalStock: totalStock, lowStock: lowStock);
});

class DashboardStats {
  final int totalStock;
  final int lowStock;

  const DashboardStats({required this.totalStock, required this.lowStock});
}
