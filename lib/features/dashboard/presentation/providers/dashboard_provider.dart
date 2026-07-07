import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../inventory/presentation/providers/inventory_provider.dart';
import '../../../onboarding/data/repositories/setup_flow_repository.dart';
import '../../../pos/data/models/sale_model.dart';
import '../../../pos/presentation/providers/pos_provider.dart';
import '../../../repairs/presentation/providers/repair_provider.dart';
import '../../../../core/extensions/repair_ticket_ext.dart';

final dashboardStatsProvider = FutureProvider<DashboardStats>((ref) async {
  final branchId = await ref.watch(selectedBranchIdProvider.future);
  final products = await ref.watch(allProductsProvider.future);
  final sales = await ref.watch(salesHistoryProvider.future);
  final returns = await ref.watch(approvedReturnsProvider.future);
  final repairTickets = await ref.watch(allRepairTicketsProvider.future);

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
  final todayRefundTotal = returns.fold<double>(0, (sum, saleReturn) {
    final createdAt = saleReturn.createdAt;
    final isToday =
        createdAt.year == today.year &&
        createdAt.month == today.month &&
        createdAt.day == today.day;
    return isToday ? sum + saleReturn.refundAmount : sum;
  });
  final todayRepairTotal = repairTickets.fold<double>(0, (sum, ticket) {
    final completedAt = ticket.completedAt;
    final isToday =
        completedAt != null &&
        completedAt.year == today.year &&
        completedAt.month == today.month &&
        completedAt.day == today.day;
    final isRevenueStatus =
        ticket.status == RepairTicketStatus.completed ||
        ticket.status == RepairTicketStatus.delivered;

    return isToday && isRevenueStatus ? sum + (ticket.totalCost ?? 0) : sum;
  });
  final activeRepairCount =
      repairTickets.where((ticket) {
        return ticket.status != RepairTicketStatus.completed &&
            ticket.status != RepairTicketStatus.delivered &&
            ticket.status != RepairTicketStatus.cancelled;
      }).length;

  return DashboardStats(
    branchId: branchId,
    totalStock: totalStock,
    lowStock: lowStock,
    activeRepairCount: activeRepairCount,
    todaySalesTotal: todaySalesTotal + todayRepairTotal - todayRefundTotal,
    recentSales: sales.take(5).toList(),
  );
});

class DashboardStats {
  final String branchId;
  final int totalStock;
  final int lowStock;
  final int activeRepairCount;
  final double todaySalesTotal;
  final List<SaleModel> recentSales;

  const DashboardStats({
    required this.branchId,
    required this.totalStock,
    required this.lowStock,
    required this.activeRepairCount,
    required this.todaySalesTotal,
    required this.recentSales,
  });
}
