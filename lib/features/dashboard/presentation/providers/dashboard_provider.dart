import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/local/local_database.dart';
import '../../../../core/tenant_access/tenant_access_provider.dart';
import '../../../inventory/presentation/providers/inventory_provider.dart';
import '../../../mobile_services/data/repositories/mobile_services_repository.dart';
import '../../../mobile_services/data/models/mobile_service_models.dart';
import '../../../mobile_services/presentation/providers/mobile_services_provider.dart';
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
import '../../../../core/accounting/ledger_cash_summary.dart';
import '../../../accounts/presentation/providers/accounts_provider.dart';

final dashboardStatsProvider = FutureProvider<DashboardStats>((ref) async {
  final tenantAccess = await ref.watch(tenantAccessProvider.future);
  if (tenantAccess != TenantAccessState.active) {
    throw StateError('Tenant access is not active.');
  }
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
    if (mobileServicesEnabled)
      ref.watch(mobileServiceTransactionsProvider(1000).future)
    else
      Future.value(const <MobileServiceTransactionModel>[]),
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
    (sum, sale) => sum + sale.total,
  );
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
  final dayStart = DateTime(today.year, today.month, today.day);
  final ledgerCash = await LedgerCashSummary.load(
    tenantId: tenantId,
    branchId: branchId,
    dateFrom: dayStart,
    dateTo: dayStart,
  );
  final totalProfit = await BusinessReportLocalStore.loadGrossProfit(
    tenantId: tenantId,
    branchId: branchId,
    dateFrom: DateTime(today.year, today.month, today.day),
    dateTo: DateTime(today.year, today.month, today.day),
  );
  final mobileServiceSummary =
      mobileServicesEnabled
          ? await _loadMobileServiceDashboardSummary(branchId, today)
          : const MobileServiceProfitSummary(todayProfit: 0, totalProfit: 0);
  final totalCreditSales = completedSales.fold<double>(
    0,
    (sum, sale) => sum + sale.creditAmount,
  );
  final creditCustomers =
      customers
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
    todaySalesTotal: todaySalesTotal,
    totalSalesTotal: totalSalesTotal + mobileServiceSummary.totalCashReceived,
    totalProfit: totalProfit + mobileServiceSummary.todayProfit,
    cashInShop: ledgerCash.cashInShop,
    totalAvailableMoney: ledgerCash.totalAvailableMoney,
    cashInToday: ledgerCash.cashIn,
    cashOutToday: ledgerCash.cashOut,
    netCashFlowToday: ledgerCash.netCashFlow,
    mobileServicesEnabled: mobileServicesEnabled,
    mobileServiceTodayCashPaid: mobileServiceSummary.todayCashPaid,
    mobileServiceTodayNetCash:
        mobileServiceSummary.todayCashReceived -
        mobileServiceSummary.todayCashPaid,
    mobileServiceTodayWalletIn: mobileServiceSummary.todayWalletIn,
    mobileServiceTodayWalletOut: mobileServiceSummary.todayWalletOut,
    totalOutstanding: totalOutstanding,
    totalCreditSales: totalCreditSales,
    creditCustomers: creditCustomers.take(5).toList(),
    recentSales: sales.take(5).toList(),
    priorityRepairs: priorityRepairs,
  );
});

Future<MobileServiceProfitSummary> _loadMobileServiceDashboardSummary(
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
    return summary;
  } catch (error) {
    debugPrint('Mobile Services dashboard profit unavailable: $error');
    return const MobileServiceProfitSummary(todayProfit: 0, totalProfit: 0);
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
  final double cashInShop;
  final double totalAvailableMoney;
  final double cashInToday;
  final double cashOutToday;
  final double netCashFlowToday;
  final bool mobileServicesEnabled;
  final double mobileServiceTodayCashPaid;
  final double mobileServiceTodayNetCash;
  final double mobileServiceTodayWalletIn;
  final double mobileServiceTodayWalletOut;
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
    required this.cashInShop,
    required this.totalAvailableMoney,
    required this.cashInToday,
    required this.cashOutToday,
    required this.netCashFlowToday,
    this.mobileServicesEnabled = false,
    this.mobileServiceTodayCashPaid = 0,
    this.mobileServiceTodayNetCash = 0,
    this.mobileServiceTodayWalletIn = 0,
    this.mobileServiceTodayWalletOut = 0,
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

final dashboardRefreshProvider = Provider<Future<void> Function()>((ref) {
  return () => refreshDashboardData(ref);
});

final _dashboardAccountRefreshCoordinatorProvider =
    Provider<_DashboardAccountRefreshCoordinator>((ref) {
      return _DashboardAccountRefreshCoordinator();
    });

class _DashboardAccountRefreshCoordinator {
  Future<void>? _inFlight;

  Future<void> run(Future<void> Function() refresh) {
    final active = _inFlight;
    if (active != null) return active;

    late final Future<void> operation;
    operation = refresh().whenComplete(() {
      if (identical(_inFlight, operation)) _inFlight = null;
    });
    _inFlight = operation;
    return operation;
  }
}

class _DashboardAccountLifecycleObserver extends WidgetsBindingObserver {
  final VoidCallback onResume;

  _DashboardAccountLifecycleObserver({required this.onResume});

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) onResume();
  }
}

final dashboardAccountLifecycleRefreshProvider = Provider<void>((ref) {
  Future<void>? inFlight;
  DateTime? lastStartedAt;

  Future<void> refresh() {
    final active = inFlight;
    if (active != null) return active;
    final now = DateTime.now();
    if (lastStartedAt != null &&
        now.difference(lastStartedAt!) < const Duration(seconds: 5)) {
      return Future<void>.value();
    }
    lastStartedAt = now;

    late final Future<void> operation;
    operation = _refreshDashboardAccounts(ref).whenComplete(() {
      if (identical(inFlight, operation)) inFlight = null;
    });
    inFlight = operation;
    return operation;
  }

  void scheduleRefresh() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      refresh();
    });
  }

  final observer = _DashboardAccountLifecycleObserver(
    onResume: scheduleRefresh,
  );
  WidgetsBinding.instance.addObserver(observer);
  scheduleRefresh();
  ref.onDispose(() => WidgetsBinding.instance.removeObserver(observer));
});

Future<void> _refreshDashboardAccounts(Ref ref) async {
  try {
    if (Supabase.instance.client.auth.currentUser == null) return;
  } catch (_) {
    // Widget previews/tests and an unusually early first frame can precede
    // Supabase initialization. A later dashboard entry/resume retries safely.
    return;
  }
  final posRepository = ref.read(posRepositoryProvider);
  final accountsRepository = ref.read(accountsRepositoryProvider);
  final coordinator = ref.read(_dashboardAccountRefreshCoordinatorProvider);

  await coordinator
      .run(() async {
        // POS owns sale/return/settlement mutations that affect account balances.
        // Complete those before accepting a newer remote account snapshot.
        await _refreshDashboardSource(
          'lifecycle POS mutation sync',
          posRepository.syncOfflineMutations,
        );
        await _refreshDashboardSource(
          'lifecycle account mutation sync',
          accountsRepository.syncOfflineMutations,
        );
        await Future.wait([
          _refreshDashboardSource(
            'lifecycle accounts',
            () => accountsRepository.refreshCurrentAccountsCache(
              timeout: const Duration(seconds: 10),
            ),
          ),
          _refreshDashboardSource(
            'lifecycle account transactions',
            () => accountsRepository.refreshCurrentTransactionsCache(
              timeout: const Duration(seconds: 10),
            ),
          ),
        ]);
      })
      .whenComplete(() {
        ref
          ..invalidate(accountsProvider)
          ..invalidate(accountTransactionsProvider);
      });
}

Future<void> refreshDashboardData(Ref ref) async {
  final inventoryRepository = ref.read(inventoryRepositoryProvider);
  final posRepository = ref.read(posRepositoryProvider);
  final repairRepository = ref.read(repairRepositoryProvider);
  final mobileServicesRepository = ref.read(mobileServicesRepositoryProvider);
  final accountsRepository = ref.read(accountsRepositoryProvider);
  final accountCoordinator = ref.read(
    _dashboardAccountRefreshCoordinatorProvider,
  );
  final branchId = await ref.read(selectedBranchIdProvider.future);
  final userId = Supabase.instance.client.auth.currentUser?.id;

  // Existing repository sync methods hon to pehle unhein await karo.
  await Future.wait([
    _refreshDashboardSource(
      'inventory mutation sync',
      inventoryRepository.syncOfflineMutations,
    ),
    _refreshDashboardSource(
      'POS mutation sync',
      posRepository.syncOfflineMutations,
    ),
    _refreshDashboardSource(
      'repair mutation sync',
      repairRepository.syncOfflineMutations,
    ),
    _refreshDashboardSource(
      'account mutation sync',
      accountsRepository.syncOfflineMutations,
    ),
    if (userId != null)
      _refreshDashboardSource(
        'mobile services mutation sync',
        () => mobileServicesRepository.syncOfflineMutations(userId),
      ),
  ]);

  // Server data fetch karke local cache update hone ka wait karo.
  await Future.wait([
    _refreshDashboardSource(
      'inventory products',
      inventoryRepository.refreshCurrentProductsCache,
    ),
    _refreshDashboardSource(
      'sales',
      () => posRepository.fetchSales(limit: 1000),
    ),
    _refreshDashboardSource('customers', posRepository.fetchCustomers),
    _refreshDashboardSource(
      'customer settlements',
      posRepository.fetchCustomerSettlements,
    ),
    _refreshDashboardSource(
      'approved returns',
      () => posRepository.fetchApprovedReturns(limit: 1000),
    ),
    _refreshDashboardSource(
      'repair tickets',
      () => repairRepository.refreshCurrentRepairTicketsCache(
        timeout: const Duration(seconds: 10),
      ),
    ),
    _refreshDashboardSource(
      'mobile services transactions',
      () => mobileServicesRepository.fetchTransactions(branchId, limit: 1000),
      timeout: const Duration(seconds: 5),
    ),
    accountCoordinator.run(() async {
      await Future.wait([
        _refreshDashboardSource(
          'accounts',
          () => accountsRepository.refreshCurrentAccountsCache(
            timeout: const Duration(seconds: 10),
          ),
        ),
        _refreshDashboardSource(
          'account transactions',
          () => accountsRepository.refreshCurrentTransactionsCache(
            timeout: const Duration(seconds: 10),
          ),
        ),
      ]);
    }),
  ]);

  // Cached providers ko dobara calculate karwao.
  ref
    ..invalidate(allProductsProvider)
    ..invalidate(allSalesProvider)
    ..invalidate(allCustomersProvider)
    ..invalidate(allCustomerSettlementsProvider)
    ..invalidate(allApprovedReturnsProvider)
    ..invalidate(allRepairTicketsProvider)
    ..invalidate(accountsProvider)
    ..invalidate(accountTransactionsProvider)
    ..invalidate(dashboardStatsProvider);

  // RefreshIndicator tab tak loading dikhaye jab tak dashboard ready na ho.
  await ref.read(dashboardStatsProvider.future);
}

Future<void> _refreshDashboardSource(
  String source,
  Future<Object?> Function() refresh, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  try {
    await refresh().timeout(timeout);
  } catch (error) {
    debugPrint(
      'Dashboard refresh skipped source "$source": '
      '${error.runtimeType}: $error',
    );
  }
}
