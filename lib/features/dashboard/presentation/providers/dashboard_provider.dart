import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/local/local_database.dart';
import '../../../onboarding/data/repositories/setup_flow_repository.dart';
import '../../../pos/data/models/cart_item_model.dart';
import '../../../pos/data/models/customer_dashboard_model.dart';
import '../../../pos/data/models/customer_model.dart';
import '../../../pos/data/models/sale_model.dart';
import '../../../pos/data/models/sale_payment_model.dart';
import '../../../pos/data/models/sale_return_model.dart';
import '../../../pos/presentation/providers/pos_provider.dart';
import '../../../repairs/presentation/providers/repair_provider.dart';
import '../../../repairs/data/models/repair_ticket_model.dart';
import '../../../../core/extensions/repair_ticket_ext.dart';
import '../../../../core/entitlements/entitlement_provider.dart';

final dashboardStatsProvider = FutureProvider<DashboardStats>((ref) async {
  final branchId = await ref.watch(selectedBranchIdProvider.future);
  final enabledFeatures = await Future.wait<bool>([
    ref.watch(featureEntitlementProvider('pos.returns').future),
    ref.watch(featureEntitlementProvider('repairs.tickets').future),
  ]);
  final returnsEnabled = enabledFeatures[0];
  final repairsEnabled = enabledFeatures[1];

  final dashboardData = await Future.wait<Object>([
    ref.watch(allSalesProvider.future),
    ref.watch(allCustomersProvider.future),
    ref.watch(allCustomerSettlementsProvider.future),
    if (returnsEnabled)
      ref.watch(allApprovedReturnsProvider.future)
    else
      Future.value(const <SaleReturnModel>[]),
    if (repairsEnabled)
      ref.watch(allRepairTicketsProvider.future)
    else
      Future.value(const <RepairTicketModel>[]),
  ]);
  final sales = dashboardData[0] as List<SaleModel>;
  final customers = dashboardData[1] as List<CustomerModel>;
  final settlements = dashboardData[2] as List<CustomerSettlementModel>;
  final returns = dashboardData[3] as List<SaleReturnModel>;
  final repairTickets = dashboardData[4] as List<RepairTicketModel>;

  final completedSales =
      sales.where((sale) => sale.status == SaleStatus.completed).toList();
  final inventorySummary = await _loadDashboardInventorySummary(branchId);
  final costByProductId = await _loadDashboardProductCosts(
    branchId: branchId,
    sales: completedSales,
    returns: returns,
  );
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
    final revenueAt = ticket.deliveredAt ?? ticket.completedAt;
    final isToday =
        revenueAt != null &&
        revenueAt.year == today.year &&
        revenueAt.month == today.month &&
        revenueAt.day == today.day;
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
  final priorityRepairs = selectPriorityRepairTickets(repairTickets);
  final returnTotal = returns.fold<double>(
    0,
    (sum, saleReturn) =>
        saleReturn.refundMethod == RefundMethod.cash
            ? sum + saleReturn.refundAmount
            : sum,
  );
  final saleById = {
    for (final sale in completedSales)
      if (sale.id != null) sale.id!: sale,
  };
  final returnProfit = returns.fold<double>(0, (sum, saleReturn) {
    if (saleReturn.refundMethod != RefundMethod.cash) return sum;
    final itemsProfit = saleReturn.items.fold<double>(0, (itemSum, item) {
      return itemSum +
          _returnedItemProfit(
            item,
            saleById[saleReturn.originalSaleId],
            costByProductId,
          );
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
    totalStock: inventorySummary.totalStock,
    lowStock: inventorySummary.lowStock,
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
    priorityRepairs: priorityRepairs,
  );
});

List<RepairTicketModel> selectPriorityRepairTickets(
  Iterable<RepairTicketModel> tickets, {
  int limit = 5,
}) {
  final actionable =
      tickets.where((ticket) {
        return ticket.status != RepairTicketStatus.delivered &&
            ticket.status != RepairTicketStatus.cancelled;
      }).toList();

  actionable.sort((a, b) {
    final aReady = a.status == RepairTicketStatus.completed;
    final bReady = b.status == RepairTicketStatus.completed;
    if (aReady != bReady) return aReady ? -1 : 1;

    if (aReady && bReady) {
      return _compareNullableDates(
        a.completedAt ?? a.updatedAt ?? a.createdAt,
        b.completedAt ?? b.updatedAt ?? b.createdAt,
      );
    }

    final dueComparison = _compareNullableDates(
      a.estimatedCompletionAt,
      b.estimatedCompletionAt,
    );
    if (dueComparison != 0) return dueComparison;
    return _compareNullableDates(a.createdAt, b.createdAt);
  });

  return actionable.take(limit).toList(growable: false);
}

int _compareNullableDates(DateTime? a, DateTime? b) {
  if (a == null && b == null) return 0;
  if (a == null) return 1;
  if (b == null) return -1;
  return a.compareTo(b);
}

Future<_DashboardInventorySummary> _loadDashboardInventorySummary(
  String branchId,
) async {
  final rows = await LocalDatabase.select(
    '''
    SELECT
      COALESCE(SUM(COALESCE(i.quantity, 0)), 0) AS total_stock,
      COALESCE(SUM(
        CASE
          WHEN COALESCE(i.quantity, 0) > 0
           AND COALESCE(i.quantity, 0) <= COALESCE(
             NULLIF(i.reorder_threshold, 0),
             NULLIF(p.reorder_threshold, 0),
             NULLIF(c.default_reorder_threshold, 0),
             5
           )
          THEN 1
          ELSE 0
        END
      ), 0) AS low_stock
    FROM products p
    LEFT JOIN inventory i
      ON i.product_id = p.id
     AND i.branch_id = p.branch_id
    LEFT JOIN categories c ON c.id = p.category_id
    WHERE p.branch_id = ?
      AND COALESCE(p.is_active, 1) = 1
    ''',
    [branchId],
  );

  final row = rows.isEmpty ? const <String, Object?>{} : rows.first;
  return _DashboardInventorySummary(
    totalStock: _intValue(row['total_stock']),
    lowStock: _intValue(row['low_stock']),
  );
}

Future<Map<String, double>> _loadDashboardProductCosts({
  required String branchId,
  required List<SaleModel> sales,
  required List<SaleReturnModel> returns,
}) async {
  final productIds = <String>{
    for (final sale in sales)
      for (final item in sale.items) item.productId,
    for (final saleReturn in returns)
      for (final item in saleReturn.items) item.productId,
  };
  if (productIds.isEmpty) return const <String, double>{};

  final placeholders = List.filled(productIds.length, '?').join(',');
  final rows = await LocalDatabase.select(
    '''
    SELECT id, cost_price
    FROM products
    WHERE branch_id = ?
      AND id IN ($placeholders)
    ''',
    [branchId, ...productIds],
  );

  return {
    for (final row in rows)
      row['id'] as String: ((row['cost_price'] as num?)?.toDouble() ?? 0),
  };
}

int _intValue(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

class _DashboardInventorySummary {
  final int totalStock;
  final int lowStock;

  const _DashboardInventorySummary({
    required this.totalStock,
    required this.lowStock,
  });
}

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
  final cost = item.unitCost ?? costByProductId[item.productId];
  if (cost == null) return 0;
  return (revenuePerUnit - cost) * item.quantity;
}

double _returnedItemProfit(
  SaleReturnItemModel item,
  SaleModel? originalSale,
  Map<String, double> costByProductId,
) {
  final originalItem = originalSale?.items.where(
    (saleItem) => saleItem.productId == item.productId,
  );
  final matchedOriginalItem =
      originalItem == null || originalItem.isEmpty ? null : originalItem.first;
  final cost = matchedOriginalItem?.unitCost ?? costByProductId[item.productId];
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
  final List<RepairTicketModel> priorityRepairs;

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
    required this.priorityRepairs,
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
