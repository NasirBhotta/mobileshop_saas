import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/local/local_database.dart';
import '../../../../core/tenant_access/tenant_access_provider.dart';
import '../../../inventory/presentation/providers/inventory_provider.dart';
import '../../../mobile_services/data/repositories/mobile_services_repository.dart';
import '../../../onboarding/data/repositories/setup_flow_repository.dart';
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
import '../../../reports/data/local/business_report_local_store.dart';

final dashboardRealtimeRefreshProvider = FutureProvider.autoDispose<void>((
  ref,
) async {
  final tenantAccess = await ref.watch(tenantAccessProvider.future);
  if (tenantAccess != TenantAccessState.active) return;

  final branchId = await ref.watch(selectedBranchIdProvider.future);
  final client = Supabase.instance.client;
  final channel = client.channel('dashboard-data-$branchId');
  final inventoryRepository = ref.read(inventoryRepositoryProvider);
  final posRepository = ref.read(posRepositoryProvider);
  final repairRepository = ref.read(repairRepositoryProvider);
  Timer? debounce;
  var disposed = false;

  Future<void> safelyRefresh(Future<Object?> refresh) async {
    try {
      await refresh;
    } catch (_) {}
  }

  Future<void> refreshCaches() {
    return Future.wait([
      safelyRefresh(inventoryRepository.refreshCurrentProductsCache()),
      safelyRefresh(posRepository.fetchSales(limit: 1000)),
      safelyRefresh(posRepository.fetchCustomers()),
      safelyRefresh(posRepository.fetchCustomerSettlements()),
      safelyRefresh(posRepository.fetchApprovedReturns(limit: 1000)),
      safelyRefresh(repairRepository.refreshCurrentRepairTicketsCache()),
    ]);
  }

  void refreshDashboard(PostgresChangePayload _) {
    debounce?.cancel();
    debounce = Timer(const Duration(milliseconds: 400), () async {
      await refreshCaches();
      if (disposed) return;

      ref
        ..invalidate(allProductsProvider)
        ..invalidate(allSalesProvider)
        ..invalidate(allCustomersProvider)
        ..invalidate(allCustomerSettlementsProvider)
        ..invalidate(allApprovedReturnsProvider)
        ..invalidate(allRepairTicketsProvider);
    });
  }

  for (final table in const [
    'products',
    'inventory',
    'sales',
    'customers',
    'customer_settlements',
    'mobile_service_transactions',
  ]) {
    channel.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: table,
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'branch_id',
        value: branchId,
      ),
      callback: refreshDashboard,
    );
  }

  channel.subscribe((status, error) {
    if (error != null) {
      debugPrint('Dashboard realtime error: $error');
    }
  });

  ref.onDispose(() {
    disposed = true;
    debounce?.cancel();
    client.removeChannel(channel);
  });

  await refreshCaches();
});

final dashboardStatsProvider = FutureProvider<DashboardStats>((ref) async {
  await ref.watch(dashboardRealtimeRefreshProvider.future);
  final branchId = await ref.watch(selectedBranchIdProvider.future);
  ref.watch(allProductsProvider);
  final enabledFeatures = await Future.wait<bool>([
    ref.watch(featureEntitlementProvider('pos.returns').future),
    ref.watch(featureEntitlementProvider('repairs.tickets').future),
    ref.watch(featureEntitlementProvider('mobile_services.access').future),
  ]);
  final returnsEnabled = enabledFeatures[0];
  final repairsEnabled = enabledFeatures[1];
  final mobileServicesEnabled = enabledFeatures[2];

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
  final tenantId = await _loadDashboardTenantId(branchId);
  final totalProfit = await BusinessReportLocalStore.loadGrossProfit(
    tenantId: tenantId,
    branchId: branchId,
    dateFrom: DateTime(today.year, today.month, today.day),
    dateTo: DateTime(today.year, today.month, today.day),
  );
  final mobileServiceTodayProfit =
      mobileServicesEnabled
          ? await _loadMobileServiceTodayProfit(branchId, today)
          : 0.0;
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
    totalProfit: totalProfit + mobileServiceTodayProfit,
    totalOutstanding: totalOutstanding,
    totalCreditSales: totalCreditSales,
    creditCustomers: creditCustomers.take(5).toList(),
    recentSales: sales.take(5).toList(),
    priorityRepairs: priorityRepairs,
  );
});

Future<double> _loadMobileServiceTodayProfit(
  String branchId,
  DateTime today,
) async {
  final dayStart = DateTime(today.year, today.month, today.day);
  final dayEnd = dayStart.add(const Duration(days: 1));
  try {
    final summary = await MobileServicesRepository().fetchProfitSummary(
      branchId: branchId,
      dayStart: dayStart,
      dayEnd: dayEnd,
    );
    return summary.todayProfit;
  } catch (error) {
    debugPrint('Mobile Services dashboard profit unavailable: $error');
    return 0;
  }
}

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

Future<String> _loadDashboardTenantId(String branchId) async {
  final rows = await LocalDatabase.select(
    'SELECT tenant_id FROM branches WHERE id = ? LIMIT 1',
    [branchId],
  );
  final tenantId = rows.firstOrNull?['tenant_id'] as String?;
  if (tenantId == null || tenantId.isEmpty) {
    throw StateError('Selected branch tenant is not available locally.');
  }
  return tenantId;
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

Future<void> refreshDashboardData(WidgetRef ref) async {
  final inventoryRepository = ref.read(inventoryRepositoryProvider);
  final posRepository = ref.read(posRepositoryProvider);
  final repairRepository = ref.read(repairRepositoryProvider);

  Future<void> safelyRefresh(Future<Object?> refresh) async {
    try {
      await refresh;
    } catch (error) {
      debugPrint('Dashboard manual refresh skipped one source: $error');
    }
  }

  // Existing repository sync methods hon to pehle unhein await karo.
  await Future.wait([
    inventoryRepository.syncOfflineMutations(),
    posRepository.syncOfflineMutations(),
    repairRepository.syncOfflineMutations(),
  ]);

  // Server data fetch karke local cache update hone ka wait karo.
  await Future.wait([
    safelyRefresh(inventoryRepository.refreshCurrentProductsCache()),
    safelyRefresh(posRepository.fetchSales(limit: 1000)),
    safelyRefresh(posRepository.fetchCustomers()),
    safelyRefresh(posRepository.fetchCustomerSettlements()),
    safelyRefresh(posRepository.fetchApprovedReturns(limit: 1000)),
    safelyRefresh(
      repairRepository.refreshCurrentRepairTicketsCache(
        timeout: const Duration(seconds: 10),
      ),
    ),
  ]);

  // Cached providers ko dobara calculate karwao.
  ref
    ..invalidate(allProductsProvider)
    ..invalidate(allSalesProvider)
    ..invalidate(allCustomersProvider)
    ..invalidate(allCustomerSettlementsProvider)
    ..invalidate(allApprovedReturnsProvider)
    ..invalidate(allRepairTicketsProvider)
    ..invalidate(dashboardStatsProvider);

  // RefreshIndicator tab tak loading dikhaye jab tak dashboard ready na ho.
  await ref.read(dashboardStatsProvider.future);
}
