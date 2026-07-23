import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobileshop_saas/features/reports/presentation/providers/business_report_provider.dart';
import 'package:mobileshop_saas/features/reports/presentation/widgets/reports_back_button.dart';
import '../../../../core/entitlements/entitlement_provider.dart';

import '../../data/models/business_report_models.dart';

void invalidateBusinessReports(WidgetRef ref) {
  ref.invalidate(businessDashboardReportProvider);
  ref.invalidate(profitLossReportProvider);
  ref.invalidate(inventoryAnalyticsReportProvider);
  ref.invalidate(customerCreditReportProvider);
  ref.invalidate(repairAnalyticsReportProvider);
  ref.invalidate(cashFlowReportProvider);
}

class BusinessDashboardReportScreen extends ConsumerWidget {
  const BusinessDashboardReportScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashboardAsync = ref.watch(businessDashboardReportProvider);
    final range = ref.watch(businessReportDateRangeProvider);
    final allBranches = ref.watch(businessReportAllBranchesProvider);
    final exportState = ref.watch(businessReportExportControllerProvider);
    final exportEnabled =
        ref.watch(reportFeatureEntitlementProvider('reports.export')).value !=
        false;
    final syncState = ref.watch(businessReportSyncControllerProvider);

    return Scaffold(
      appBar: AppBar(
        leading: const ReportsBackButton(),
        title: const Text('Business Analytics'),
        actions: [
          if (exportEnabled)
            IconButton(
              tooltip: 'Sync',
              onPressed:
                  syncState.isLoading
                      ? null
                      : () async {
                        await ref
                            .read(businessReportSyncControllerProvider.notifier)
                            .sync();

                        if (!context.mounted) return;

                        final error =
                            ref
                                .read(businessReportSyncControllerProvider)
                                .asError;

                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              error == null
                                  ? 'Business reports synced'
                                  : error.error.toString(),
                            ),
                          ),
                        );
                      },
              icon:
                  syncState.isLoading
                      ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                      : const Icon(Icons.sync),
            ),
          IconButton(
            tooltip: 'Export Dashboard CSV',
            onPressed:
                exportState.isLoading
                    ? null
                    : () =>
                        _exportCsv(context, ref, BusinessReportType.dashboard),
            icon:
                exportState.isLoading
                    ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                    : const Icon(Icons.download),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            _BusinessReportFilters(
              from: range.from,
              to: range.to,
              allBranches: allBranches,
            ),
            const Divider(height: 1),
            Expanded(
              child: dashboardAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) => _ErrorView(error: error),
                data: (report) {
                  return RefreshIndicator(
                    onRefresh: () async {
                      await ref
                          .read(businessReportSyncControllerProvider.notifier)
                          .sync();
                      await ref.read(businessDashboardReportProvider.future);
                    },
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final isWide = constraints.maxWidth >= 980;

                        return ListView(
                          padding: const EdgeInsets.all(16),
                          children: [
                            Center(
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 1180,
                                ),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    _HeaderCard(report: report),
                                    const SizedBox(height: 14),
                                    _MainKpiGrid(report: report),
                                    const SizedBox(height: 14),
                                    if (isWide)
                                      Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Expanded(
                                            child: _ProfitLossPanel(
                                              report: report.profitLoss,
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: _CashFlowPanel(
                                              report: report.cashFlow,
                                            ),
                                          ),
                                        ],
                                      )
                                    else ...[
                                      _ProfitLossPanel(
                                        report: report.profitLoss,
                                      ),
                                      const SizedBox(height: 12),
                                      _CashFlowPanel(report: report.cashFlow),
                                    ],
                                    const SizedBox(height: 14),
                                    if (isWide)
                                      Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Expanded(
                                            child: _InventoryPanel(
                                              report: report.inventory,
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: _CustomerPanel(
                                              report: report.customers,
                                            ),
                                          ),
                                        ],
                                      )
                                    else ...[
                                      _InventoryPanel(report: report.inventory),
                                      const SizedBox(height: 12),
                                      _CustomerPanel(report: report.customers),
                                    ],
                                    const SizedBox(height: 14),
                                    _RepairPanel(report: report.repairs),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _exportCsv(
    BuildContext context,
    WidgetRef ref,
    BusinessReportType reportType,
  ) async {
    final csv = await ref
        .read(businessReportExportControllerProvider.notifier)
        .buildCsv(reportType: reportType);

    if (!context.mounted) return;

    final error = ref.read(businessReportExportControllerProvider).asError;

    if (error != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.error.toString())));
      return;
    }

    if (csv == null || csv.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('CSV export is empty')));
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (_) {
        return AlertDialog(
          title: const Text('CSV Export Generated'),
          content: SizedBox(
            width: 720,
            child: SingleChildScrollView(
              child: SelectableText(
                csv,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }
}

class _BusinessReportFilters extends ConsumerWidget {
  final DateTime from;
  final DateTime to;
  final bool allBranches;

  const _BusinessReportFilters({
    required this.from,
    required this.to,
    required this.allBranches,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 760;

            final dateButton = _DateRangeButton(
              from: from,
              to: to,
              onTap: () => _pickDateRange(context, ref),
            );

            // Temporarily hidden until consolidated report validation is done.
            // final branchToggle = SwitchListTile(
            //   value: allBranches,
            //   title: const Text('All Branches'),
            //   subtitle: const Text('Consolidated owner view'),
            //   contentPadding: EdgeInsets.zero,
            //   onChanged: (value) {
            //     ref.read(businessReportAllBranchesProvider.notifier).state =
            //         value;
            //     invalidateBusinessReports(ref);
            //   },
            // );
            const branchToggle = SizedBox.shrink();

            if (isWide) {
              return Row(
                children: [
                  Expanded(child: dateButton),
                  const SizedBox(width: 16),
                  SizedBox(width: 280, child: branchToggle),
                ],
              );
            }

            return Column(
              children: [dateButton, const SizedBox(height: 8), branchToggle],
            );
          },
        ),
      ),
    );
  }

  Future<void> _pickDateRange(BuildContext context, WidgetRef ref) async {
    final current = ref.read(businessReportDateRangeProvider);

    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: DateTimeRange(start: current.from, end: current.to),
    );

    if (picked == null) return;

    ref
        .read(businessReportDateRangeProvider.notifier)
        .state = BusinessReportDateRange(
      from: DateTime(picked.start.year, picked.start.month, picked.start.day),
      to: DateTime(picked.end.year, picked.end.month, picked.end.day),
    );

    invalidateBusinessReports(ref);
  }
}

class _HeaderCard extends StatelessWidget {
  final BusinessDashboardReportModel report;

  const _HeaderCard({required this.report});

  @override
  Widget build(BuildContext context) {
    final pnl = report.profitLoss.summary;
    final isProfit = pnl.netProfit >= 0;

    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 760;

            final left = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Owner Business Overview',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 6),
                Text(
                  'Rs ${pnl.netProfit.toStringAsFixed(0)}',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    color:
                        isProfit
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.error,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Net Profit · ${pnl.netMarginPercent.toStringAsFixed(1)}% margin',
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  '${_dateText(report.dateFrom)} - ${_dateText(report.dateTo)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            );

            final right = Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(
                  avatar: const Icon(Icons.point_of_sale_outlined, size: 16),
                  label: Text('Sales Rs ${pnl.revenue.toStringAsFixed(0)}'),
                ),
                Chip(
                  avatar: const Icon(Icons.receipt_long_outlined, size: 16),
                  label: Text('Expenses Rs ${pnl.expenses.toStringAsFixed(0)}'),
                ),
                Chip(
                  avatar: const Icon(Icons.inventory_2_outlined, size: 16),
                  label: Text(
                    'Stock Rs ${report.inventory.summary.stockValue.toStringAsFixed(0)}',
                  ),
                ),
              ],
            );

            if (isWide) {
              return Row(
                children: [
                  Expanded(child: left),
                  const SizedBox(width: 16),
                  Expanded(child: right),
                ],
              );
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [left, const SizedBox(height: 14), right],
            );
          },
        ),
      ),
    );
  }
}

class _MainKpiGrid extends StatelessWidget {
  final BusinessDashboardReportModel report;

  const _MainKpiGrid({required this.report});

  @override
  Widget build(BuildContext context) {
    final pnl = report.profitLoss.summary;
    final inventory = report.inventory.summary;
    final customers = report.customers.summary;
    final repairs = report.repairs.summary;
    final cash = report.cashFlow.summary;

    final items = [
      _KpiItem(
        title: 'Revenue',
        value: 'Rs ${pnl.revenue.toStringAsFixed(0)}',
        icon: Icons.point_of_sale_outlined,
      ),
      _KpiItem(
        title: 'Gross Profit',
        value: 'Rs ${pnl.grossProfit.toStringAsFixed(0)}',
        icon: Icons.trending_up,
      ),
      _KpiItem(
        title: 'Net Profit',
        value: 'Rs ${pnl.netProfit.toStringAsFixed(0)}',
        icon: Icons.account_balance_wallet_outlined,
      ),
      _KpiItem(
        title: 'Net Cash',
        value: 'Rs ${cash.netCash.toStringAsFixed(0)}',
        icon: Icons.payments_outlined,
      ),
      _KpiItem(
        title: 'Stock Value',
        value: 'Rs ${inventory.stockValue.toStringAsFixed(0)}',
        icon: Icons.inventory_2_outlined,
      ),
      _KpiItem(
        title: 'Low Stock',
        value: inventory.lowStockCount.toString(),
        icon: Icons.warning_amber_outlined,
      ),
      _KpiItem(
        title: 'Outstanding Credit',
        value: 'Rs ${customers.outstandingBalance.toStringAsFixed(0)}',
        icon: Icons.credit_score_outlined,
      ),
      _KpiItem(
        title: 'Open Repairs',
        value: repairs.openRepairs.toString(),
        icon: Icons.handyman_outlined,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;

        final crossAxisCount =
            width >= 1000
                ? 4
                : width >= 700
                ? 2
                : 1;

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: items.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            mainAxisExtent: 112,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          itemBuilder: (_, index) {
            return _KpiCard(item: items[index]);
          },
        );
      },
    );
  }
}

class _KpiItem {
  final String title;
  final String value;
  final IconData icon;

  const _KpiItem({
    required this.title,
    required this.value,
    required this.icon,
  });
}

class _KpiCard extends StatelessWidget {
  final _KpiItem item;

  const _KpiCard({required this.item});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            CircleAvatar(child: Icon(item.icon)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    item.value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfitLossPanel extends StatelessWidget {
  final ProfitLossReportModel report;

  const _ProfitLossPanel({required this.report});

  @override
  Widget build(BuildContext context) {
    final summary = report.summary;

    return _SectionCard(
      title: 'Profit & Loss',
      icon: Icons.account_balance_outlined,
      child: Column(
        children: [
          _MoneyRow(label: 'Revenue', value: summary.revenue),
          _MoneyRow(label: 'COGS', value: summary.cogs, negative: true),
          const Divider(),
          _MoneyRow(
            label: 'Gross Profit',
            value: summary.grossProfit,
            bold: true,
          ),
          _MoneyRow(label: 'Expenses', value: summary.expenses, negative: true),
          const Divider(),
          _MoneyRow(
            label: 'Net Profit',
            value: summary.netProfit,
            bold: true,
            highlight: true,
          ),
          _PlainRow(
            label: 'Net Margin',
            value: '${summary.netMarginPercent.toStringAsFixed(1)}%',
          ),
        ],
      ),
    );
  }
}

class _CashFlowPanel extends StatelessWidget {
  final CashFlowReportModel report;

  const _CashFlowPanel({required this.report});

  @override
  Widget build(BuildContext context) {
    final summary = report.summary;

    return _SectionCard(
      title: 'Cash Flow',
      icon: Icons.payments_outlined,
      child: Column(
        children: [
          _MoneyRow(label: 'Cash In', value: summary.cashIn),
          _MoneyRow(label: 'Cash Out', value: summary.cashOut, negative: true),
          const Divider(),
          _MoneyRow(
            label: 'Net Cash',
            value: summary.netCash,
            bold: true,
            highlight: true,
          ),
          const SizedBox(height: 12),
          _BreakdownList(
            title: 'Sales Payments',
            items: report.salesPaymentBreakdown,
          ),
          const SizedBox(height: 12),
          _BreakdownList(
            title: 'Expense Payments',
            items: report.expensePaymentBreakdown,
          ),
        ],
      ),
    );
  }
}

class _InventoryPanel extends StatelessWidget {
  final InventoryAnalyticsReportModel report;

  const _InventoryPanel({required this.report});

  @override
  Widget build(BuildContext context) {
    final summary = report.summary;

    return _SectionCard(
      title: 'Inventory',
      icon: Icons.inventory_2_outlined,
      child: Column(
        children: [
          _PlainRow(
            label: 'Total Products',
            value: summary.totalProducts.toString(),
          ),
          _PlainRow(
            label: 'Total Stock',
            value: summary.totalStock.toStringAsFixed(0),
          ),
          _MoneyRow(label: 'Stock Value', value: summary.stockValue),
          _PlainRow(
            label: 'Low Stock',
            value: summary.lowStockCount.toString(),
          ),
          _PlainRow(
            label: 'Out of Stock',
            value: summary.outOfStockCount.toString(),
          ),
          const SizedBox(height: 12),
          _SimpleProductList(
            title: 'Low Stock Products',
            items:
                report.lowStock
                    .take(8)
                    .map(
                      (item) =>
                          '${item.productName} · Qty ${item.quantity.toStringAsFixed(0)}',
                    )
                    .toList(),
          ),
        ],
      ),
    );
  }
}

class _CustomerPanel extends StatelessWidget {
  final CustomerCreditReportModel report;

  const _CustomerPanel({required this.report});

  @override
  Widget build(BuildContext context) {
    final summary = report.summary;

    return _SectionCard(
      title: 'Customers & Credit',
      icon: Icons.people_outline,
      child: Column(
        children: [
          _PlainRow(
            label: 'Total Customers',
            value: summary.totalCustomers.toString(),
          ),
          _PlainRow(
            label: 'Credit Customers',
            value: summary.creditCustomers.toString(),
          ),
          _MoneyRow(
            label: 'Outstanding Balance',
            value: summary.outstandingBalance,
            highlight: true,
          ),
          const SizedBox(height: 12),
          _SimpleProductList(
            title: 'Top Credit Customers',
            items:
                report.creditCustomers
                    .take(8)
                    .map(
                      (item) =>
                          '${item.customerName} · Rs ${item.outstandingBalance.toStringAsFixed(0)}',
                    )
                    .toList(),
          ),
        ],
      ),
    );
  }
}

class _RepairPanel extends StatelessWidget {
  final RepairAnalyticsReportModel report;

  const _RepairPanel({required this.report});

  @override
  Widget build(BuildContext context) {
    final summary = report.summary;

    return _SectionCard(
      title: 'Repairs',
      icon: Icons.handyman_outlined,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 760;

          final summaryBlock = Column(
            children: [
              _PlainRow(
                label: 'Total Repairs',
                value: summary.totalRepairs.toString(),
              ),
              _PlainRow(
                label: 'Open Repairs',
                value: summary.openRepairs.toString(),
              ),
              _PlainRow(
                label: 'Completed Repairs',
                value: summary.completedRepairs.toString(),
              ),
              _MoneyRow(label: 'Repair Revenue', value: summary.repairRevenue),
            ],
          );

          final statusBlock = _SimpleProductList(
            title: 'Status Breakdown',
            items:
                report.statusBreakdown
                    .map(
                      (item) =>
                          '${item.status} · ${item.count} · Rs ${item.revenue.toStringAsFixed(0)}',
                    )
                    .toList(),
          );

          if (isWide) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: summaryBlock),
                const SizedBox(width: 16),
                Expanded(child: statusBlock),
              ],
            );
          }

          return Column(
            children: [summaryBlock, const SizedBox(height: 12), statusBlock],
          );
        },
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;

  const _SectionCard({
    required this.title,
    required this.icon,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icon),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
  }
}

class _MoneyRow extends StatelessWidget {
  final String label;
  final double value;
  final bool bold;
  final bool highlight;
  final bool negative;

  const _MoneyRow({
    required this.label,
    required this.value,
    this.bold = false,
    this.highlight = false,
    this.negative = false,
  });

  @override
  Widget build(BuildContext context) {
    final color =
        highlight
            ? value >= 0
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.error
            : negative
            ? Theme.of(context).colorScheme.error
            : null;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
              ),
            ),
          ),
          Text(
            'Rs ${value.toStringAsFixed(0)}',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontWeight: bold ? FontWeight.w900 : FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _PlainRow extends StatelessWidget {
  final String label;
  final String value;

  const _PlainRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _BreakdownList extends StatelessWidget {
  final String title;
  final List<ReportMoneyBreakdownItem> items;

  const _BreakdownList({required this.title, required this.items});

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return _SimpleProductList(title: title, items: const ['No data']);
    }

    return _SimpleProductList(
      title: title,
      items:
          items
              .take(6)
              .map(
                (item) =>
                    '${item.label} · Rs ${item.amount.toStringAsFixed(0)}',
              )
              .toList(),
    );
  }
}

class _SimpleProductList extends StatelessWidget {
  final String title;
  final List<String> items;

  const _SimpleProductList({required this.title, required this.items});

  @override
  Widget build(BuildContext context) {
    final displayItems = items.isEmpty ? const ['No data'] : items;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        for (final item in displayItems)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              item,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
      ],
    );
  }
}

class _DateRangeButton extends StatelessWidget {
  final DateTime from;
  final DateTime to;
  final VoidCallback onTap;

  const _DateRangeButton({
    required this.from,
    required this.to,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: InputDecorator(
        decoration: const InputDecoration(
          labelText: 'Date Range',
          border: OutlineInputBorder(),
          isDense: true,
          suffixIcon: Icon(Icons.date_range),
        ),
        child: Text('${_dateText(from)} - ${_dateText(to)}'),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final Object error;

  const _ErrorView({required this.error});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            error.toString(),
            textAlign: TextAlign.center,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
      ),
    );
  }
}

String _dateText(DateTime date) {
  final day = date.day.toString().padLeft(2, '0');
  final month = date.month.toString().padLeft(2, '0');
  final year = date.year.toString();

  return '$day-$month-$year';
}
