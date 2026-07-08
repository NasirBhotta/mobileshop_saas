import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../inventory/presentation/providers/inventory_provider.dart';
import '../../../onboarding/data/repositories/setup_flow_repository.dart';
import '../../../pos/data/models/cart_item_model.dart';
import '../../../pos/data/models/customer_dashboard_model.dart';
import '../../../pos/data/models/customer_model.dart';
import '../../../pos/data/models/sale_model.dart';
import '../../../pos/data/models/sale_payment_model.dart';
import '../../../pos/data/models/sale_return_model.dart';
import '../../../pos/presentation/providers/pos_provider.dart';
import '../../../repairs/presentation/providers/repair_provider.dart';
import '../../../../core/extensions/repair_ticket_ext.dart';

final dashboardStatsProvider = FutureProvider<DashboardStats>((ref) async {
  final branchId = await ref.watch(selectedBranchIdProvider.future);
  final products = await ref.watch(allProductsProvider.future);
  final sales = await ref.watch(allSalesProvider.future);
  final returns = await ref.watch(allApprovedReturnsProvider.future);
  final customers = await ref.watch(allCustomersProvider.future);
  final settlements = await ref.watch(allCustomerSettlementsProvider.future);
  final repairTickets = await ref.watch(allRepairTicketsProvider.future);

  final costByProductId = {
    for (final product in products) product.id: product.costPrice,
  };
  final totalStock = products.fold<int>(
    0,
    (sum, product) => sum + product.stock,
  );
  final lowStock = products.where((product) => product.isLowStock).length;
  final completedSales =
      sales.where((sale) => sale.status == SaleStatus.completed).toList();
  final today = DateTime.now();
  final todaySales =
      completedSales.where((sale) {
        final createdAt = sale.createdAt;
        if (createdAt == null) return false;
        return createdAt.year == today.year &&
            createdAt.month == today.month &&
            createdAt.day == today.day;
      }).toList();
  final todaySalesTotal = todaySales.fold<double>(
    0,
    (sum, sale) => sum + sale.nonCreditAmount,
  );
  final todaySettlementsTotal = settlements.fold<double>(0, (sum, settlement) {
    final createdAt = settlement.createdAt;
    final isToday =
        createdAt.year == today.year &&
        createdAt.month == today.month &&
        createdAt.day == today.day;
    return isToday ? sum + settlement.amount : sum;
  });
  final todayRefundTotal = returns.fold<double>(0, (sum, saleReturn) {
    final createdAt = saleReturn.createdAt;
    final isToday =
        createdAt.year == today.year &&
        createdAt.month == today.month &&
        createdAt.day == today.day;
    return isToday && saleReturn.refundMethod == RefundMethod.cash
        ? sum + saleReturn.refundAmount
        : sum;
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
  final totalRepairRevenue = repairTickets.fold<double>(0, (sum, ticket) {
    final isRevenueStatus =
        ticket.status == RepairTicketStatus.completed ||
        ticket.status == RepairTicketStatus.delivered;
    return isRevenueStatus ? sum + (ticket.totalCost ?? 0) : sum;
  });
  final activeRepairCount =
      repairTickets.where((ticket) {
        return ticket.status != RepairTicketStatus.completed &&
            ticket.status != RepairTicketStatus.delivered &&
            ticket.status != RepairTicketStatus.cancelled;
      }).length;
  final returnTotal = returns.fold<double>(
    0,
    (sum, saleReturn) =>
        saleReturn.refundMethod == RefundMethod.cash
            ? sum + saleReturn.refundAmount
            : sum,
  );
  final returnProfit = returns.fold<double>(0, (sum, saleReturn) {
    if (saleReturn.refundMethod != RefundMethod.cash) return sum;
    final itemsProfit = saleReturn.items.fold<double>(0, (itemSum, item) {
      return itemSum + _returnedItemProfit(item, costByProductId);
    });
    return sum + itemsProfit;
  });
  final settlementTotal = settlements.fold<double>(
    0,
    (sum, settlement) => sum + settlement.amount,
  );
  final totalSalesTotal =
      completedSales.fold<double>(
        0,
        (sum, sale) => sum + sale.nonCreditAmount,
      ) +
      settlementTotal +
      totalRepairRevenue -
      returnTotal;
  final totalProfit =
      completedSales.fold<double>(
        0,
        (sum, sale) => sum + _realizedCheckoutProfit(sale, costByProductId),
      ) +
      _realizedSettlementProfit(
        sales: completedSales,
        settlements: settlements,
        costByProductId: costByProductId,
      ) +
      totalRepairRevenue -
      returnProfit;
  final totalCreditSales = completedSales.fold<double>(
    0,
    (sum, sale) => sum + sale.creditAmount,
  );
  final computedOutstandingByCustomer = <String, double>{};
  for (final sale in completedSales) {
    final customerId = sale.customerId;
    if (customerId == null) continue;
    final creditAmount = sale.creditAmount;
    if (creditAmount <= 0) continue;
    computedOutstandingByCustomer.update(
      customerId,
      (amount) => amount + creditAmount,
      ifAbsent: () => creditAmount,
    );
  }
  for (final settlement in settlements) {
    computedOutstandingByCustomer.update(
      settlement.customerId,
      (amount) => amount - settlement.amount,
      ifAbsent: () => -settlement.amount,
    );
  }
  final creditCustomers =
      customers
          .map((customer) {
            final customerId = customer.id;
            if (customerId == null) return customer;
            final computed =
                (computedOutstandingByCustomer[customerId] ?? 0)
                    .clamp(0, double.infinity)
                    .toDouble();
            final effectiveOutstanding =
                computed > customer.outstandingBalance
                    ? computed
                    : customer.outstandingBalance;
            return customer.copyWith(outstandingBalance: effectiveOutstanding);
          })
          .where((customer) => customer.outstandingBalance > 0.01)
          .map(DashboardCreditCustomer.fromCustomer)
          .toList()
        ..sort((a, b) => b.outstandingBalance.compareTo(a.outstandingBalance));
  final totalOutstanding = creditCustomers.fold<double>(
    0,
    (sum, customer) => sum + customer.outstandingBalance,
  );

  return DashboardStats(
    branchId: branchId,
    totalStock: totalStock,
    lowStock: lowStock,
    activeRepairCount: activeRepairCount,
    todaySalesTotal:
        todaySalesTotal +
        todaySettlementsTotal +
        todayRepairTotal -
        todayRefundTotal,
    totalSalesTotal: totalSalesTotal,
    totalProfit: totalProfit,
    totalOutstanding: totalOutstanding,
    totalCreditSales: totalCreditSales,
    creditCustomers: creditCustomers.take(5).toList(),
    recentSales: sales.take(5).toList(),
  );
});

double _saleProfit(SaleModel sale, Map<String, double> costByProductId) {
  return sale.items.fold<double>(0, (sum, item) {
    return sum + _saleItemProfit(item, costByProductId);
  });
}

double _saleItemProfit(
  CartItemModel item,
  Map<String, double> costByProductId,
) {
  final revenuePerUnit = item.unitPrice - item.discountAmount;
  final cost = costByProductId[item.productId];
  if (cost == null) return 0;
  return (revenuePerUnit - cost) * item.quantity;
}

double _returnedItemProfit(
  SaleReturnItemModel item,
  Map<String, double> costByProductId,
) {
  final cost = costByProductId[item.productId];
  if (cost == null) return 0;
  return item.refundAmount - (cost * item.quantity);
}

double _realizedCheckoutProfit(
  SaleModel sale,
  Map<String, double> costByProductId,
) {
  if (sale.total <= 0) return 0;
  final realizedRatio = (sale.nonCreditAmount / sale.total).clamp(0.0, 1.0);
  return _saleProfit(sale, costByProductId) * realizedRatio;
}

double _realizedSettlementProfit({
  required List<SaleModel> sales,
  required List<CustomerSettlementModel> settlements,
  required Map<String, double> costByProductId,
}) {
  final settlementByCustomer = <String, double>{};
  for (final settlement in settlements) {
    settlementByCustomer.update(
      settlement.customerId,
      (amount) => amount + settlement.amount,
      ifAbsent: () => settlement.amount,
    );
  }

  final salesByCustomer = <String, List<SaleModel>>{};
  for (final sale in sales) {
    final customerId = sale.customerId;
    if (customerId == null || sale.creditAmount <= 0) continue;
    salesByCustomer.putIfAbsent(customerId, () => []).add(sale);
  }

  var realizedProfit = 0.0;
  for (final entry in salesByCustomer.entries) {
    var remainingSettlement = settlementByCustomer[entry.key] ?? 0;
    if (remainingSettlement <= 0) continue;

    final customerSales =
        entry.value..sort((a, b) {
          final aDate = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          final bDate = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          return aDate.compareTo(bDate);
        });

    for (final sale in customerSales) {
      if (remainingSettlement <= 0) break;
      if (sale.total <= 0 || sale.creditAmount <= 0) continue;

      final realizedAmount =
          remainingSettlement > sale.creditAmount
              ? sale.creditAmount
              : remainingSettlement;
      final saleProfit = _saleProfit(sale, costByProductId);
      final creditProfit = saleProfit * (sale.creditAmount / sale.total);
      realizedProfit += creditProfit * (realizedAmount / sale.creditAmount);
      remainingSettlement -= realizedAmount;
    }
  }

  return realizedProfit;
}

extension _SaleCreditAmount on SaleModel {
  double get creditAmount {
    return payments
        .where((payment) => payment.method == PaymentMethod.credit)
        .fold<double>(0, (sum, payment) => sum + payment.amount);
  }

  double get nonCreditAmount {
    return payments
        .where((payment) => payment.method != PaymentMethod.credit)
        .fold<double>(0, (sum, payment) => sum + payment.amount);
  }
}

class DashboardStats {
  final String branchId;
  final int totalStock;
  final int lowStock;
  final int activeRepairCount;
  final double todaySalesTotal;
  final double totalSalesTotal;
  final double totalProfit;
  final double totalOutstanding;
  final double totalCreditSales;
  final List<DashboardCreditCustomer> creditCustomers;
  final List<SaleModel> recentSales;

  const DashboardStats({
    required this.branchId,
    required this.totalStock,
    required this.lowStock,
    required this.activeRepairCount,
    required this.todaySalesTotal,
    required this.totalSalesTotal,
    required this.totalProfit,
    required this.totalOutstanding,
    required this.totalCreditSales,
    required this.creditCustomers,
    required this.recentSales,
  });
}

class DashboardCreditCustomer {
  final String? id;
  final String fullName;
  final String? phone;
  final double outstandingBalance;
  final double? creditLimit;

  const DashboardCreditCustomer({
    this.id,
    required this.fullName,
    this.phone,
    required this.outstandingBalance,
    this.creditLimit,
  });

  factory DashboardCreditCustomer.fromCustomer(CustomerModel customer) {
    return DashboardCreditCustomer(
      id: customer.id,
      fullName: customer.fullName,
      phone: customer.phone,
      outstandingBalance: customer.outstandingBalance,
      creditLimit: customer.creditLimit,
    );
  }
}
