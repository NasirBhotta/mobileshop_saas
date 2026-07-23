import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobileshop_saas/features/reports/presentation/providers/sales_report_provider.dart';
import 'package:mobileshop_saas/features/reports/presentation/widgets/reports_back_button.dart';
import '../../../../core/entitlements/entitlement_provider.dart';

import '../../data/models/sales_report_models.dart';

class SalesReportScreen extends ConsumerWidget {
  const SalesReportScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reportAsync = ref.watch(salesAnalyticsReportProvider);
    final range = ref.watch(salesReportDateRangeProvider);
    final allBranches = ref.watch(salesReportAllBranchesProvider);
    final exportState = ref.watch(salesReportExportControllerProvider);
    final syncState = ref.watch(salesReportSyncControllerProvider);
    final scheduledEnabled =
        ref
            .watch(reportFeatureEntitlementProvider('reports.scheduled'))
            .value !=
        false;
    final exportEnabled =
        ref.watch(reportFeatureEntitlementProvider('reports.export')).value !=
        false;

    return Scaffold(
      appBar: AppBar(
        leading: const ReportsBackButton(),
        title: const Text('Sales Analytics'),
        actions: [
          IconButton(
            tooltip: 'Sync',
            onPressed:
                syncState.isLoading
                    ? null
                    : () async {
                      await ref
                          .read(salesReportSyncControllerProvider.notifier)
                          .sync();

                      if (!context.mounted) return;

                      final error =
                          ref.read(salesReportSyncControllerProvider).asError;

                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            error == null
                                ? 'Sales reports synced'
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
          if (scheduledEnabled)
            IconButton(
              tooltip: 'Scheduled Reports',
              onPressed: () {
                context.go('/reports/sales/schedules');
              },
              icon: const Icon(Icons.schedule_send_outlined),
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            _SalesReportFilters(
              from: range.from,
              to: range.to,
              allBranches: allBranches,
            ),
            const Divider(height: 1),
            Expanded(
              child: reportAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) => _ErrorView(error: error),
                data: (report) {
                  return RefreshIndicator(
                    onRefresh: () async {
                      await ref
                          .read(salesReportSyncControllerProvider.notifier)
                          .sync();
                      await ref.read(salesAnalyticsReportProvider.future);
                    },
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final isWide = constraints.maxWidth >= 950;

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
                                    _ReportHeader(
                                      report: report,
                                      exportLoading: exportState.isLoading,
                                      onExportCsv:
                                          exportEnabled
                                              ? () => _exportCsv(context, ref)
                                              : null,
                                    ),
                                    const SizedBox(height: 14),
                                    _SummaryGrid(report: report),
                                    const SizedBox(height: 14),
                                    _DailyChartCard(
                                      items: report.dailyBreakdown,
                                    ),
                                    const SizedBox(height: 14),
                                    if (isWide)
                                      Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Expanded(
                                            flex: 3,
                                            child: _ProductProfitabilityCard(
                                              items: report.productBreakdown,
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            flex: 2,
                                            child: _CategoryMarginCard(
                                              items: report.categoryBreakdown,
                                            ),
                                          ),
                                        ],
                                      )
                                    else ...[
                                      _ProductProfitabilityCard(
                                        items: report.productBreakdown,
                                      ),
                                      const SizedBox(height: 12),
                                      _CategoryMarginCard(
                                        items: report.categoryBreakdown,
                                      ),
                                    ],
                                    const SizedBox(height: 14),
                                    if (isWide)
                                      Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Expanded(
                                            child: _CustomerBreakdownCard(
                                              items: report.customerBreakdown,
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: _BranchBreakdownCard(
                                              items: report.branchBreakdown,
                                            ),
                                          ),
                                        ],
                                      )
                                    else ...[
                                      _CustomerBreakdownCard(
                                        items: report.customerBreakdown,
                                      ),
                                      const SizedBox(height: 12),
                                      _BranchBreakdownCard(
                                        items: report.branchBreakdown,
                                      ),
                                    ],
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

  Future<void> _exportCsv(BuildContext context, WidgetRef ref) async {
    final csv =
        await ref
            .read(salesReportExportControllerProvider.notifier)
            .buildCsvExport();

    if (!context.mounted) return;

    final error = ref.read(salesReportExportControllerProvider).asError;

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

class _SalesReportFilters extends ConsumerWidget {
  final DateTime from;
  final DateTime to;
  final bool allBranches;

  const _SalesReportFilters({
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
            //   subtitle: const Text('Show consolidated branch report'),
            //   contentPadding: EdgeInsets.zero,
            //   onChanged: (value) {
            //     ref.read(salesReportAllBranchesProvider.notifier).state = value;
            //     ref.invalidate(salesAnalyticsReportProvider);
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
    final current = ref.read(salesReportDateRangeProvider);

    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: DateTimeRange(start: current.from, end: current.to),
    );

    if (picked == null) return;

    ref
        .read(salesReportDateRangeProvider.notifier)
        .state = SalesReportDateRange(
      from: DateTime(picked.start.year, picked.start.month, picked.start.day),
      to: DateTime(picked.end.year, picked.end.month, picked.end.day),
    );

    ref.invalidate(salesAnalyticsReportProvider);
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

class _ReportHeader extends StatelessWidget {
  final SalesAnalyticsReportModel report;
  final bool exportLoading;
  final VoidCallback? onExportCsv;

  const _ReportHeader({
    required this.report,
    required this.exportLoading,
    required this.onExportCsv,
  });

  @override
  Widget build(BuildContext context) {
    final margin = report.summary.grossMarginPercent;
    final profitable = report.summary.grossProfit >= 0;

    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 780;

            final titleBlock = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Sales Performance',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 6),
                Text(
                  'Rs ${report.summary.revenue.toStringAsFixed(0)}',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Gross Profit: Rs ${report.summary.grossProfit.toStringAsFixed(0)} · Margin ${margin.toStringAsFixed(1)}%',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color:
                        profitable
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.error,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${_dateText(report.dateFrom)} - ${_dateText(report.dateTo)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            );

            final actions = Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.end,
              children: [
                Chip(
                  avatar: const Icon(
                    Icons.workspace_premium_outlined,
                    size: 16,
                  ),
                  label: Text('Plan: ${report.plan.toUpperCase()}'),
                ),
                if (onExportCsv != null)
                  FilledButton.icon(
                    onPressed: exportLoading ? null : onExportCsv,
                    icon:
                        exportLoading
                            ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                            : const Icon(Icons.download),
                    label: const Text('CSV'),
                  ),
              ],
            );

            if (isWide) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(child: titleBlock),
                  const SizedBox(width: 16),
                  Expanded(child: actions),
                ],
              );
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [titleBlock, const SizedBox(height: 14), actions],
            );
          },
        ),
      ),
    );
  }
}

class _SummaryGrid extends StatelessWidget {
  final SalesAnalyticsReportModel report;

  const _SummaryGrid({required this.report});

  @override
  Widget build(BuildContext context) {
    final items = [
      _SummaryItem(
        title: 'Orders',
        value: report.summary.totalOrders.toString(),
        icon: Icons.shopping_bag_outlined,
      ),
      _SummaryItem(
        title: 'Units Sold',
        value: report.summary.totalUnits.toString(),
        icon: Icons.inventory_2_outlined,
      ),
      _SummaryItem(
        title: 'Revenue',
        value: 'Rs ${report.summary.revenue.toStringAsFixed(0)}',
        icon: Icons.point_of_sale_outlined,
      ),
      _SummaryItem(
        title: 'COGS',
        value: 'Rs ${report.summary.cogs.toStringAsFixed(0)}',
        icon: Icons.payments_outlined,
      ),
      _SummaryItem(
        title: 'Gross Profit',
        value: 'Rs ${report.summary.grossProfit.toStringAsFixed(0)}',
        icon: Icons.trending_up,
      ),
      _SummaryItem(
        title: 'Gross Margin',
        value: '${report.summary.grossMarginPercent.toStringAsFixed(1)}%',
        icon: Icons.percent,
      ),
      _SummaryItem(
        title: 'Returns',
        value: 'Rs ${report.summary.returnsAmount.toStringAsFixed(0)}',
        icon: Icons.assignment_return_outlined,
      ),
      _SummaryItem(
        title: 'Returned Units',
        value: report.summary.returnedUnits.toString(),
        icon: Icons.keyboard_return_outlined,
      ),
      _SummaryItem(
        title: 'Net Sales',
        value: 'Rs ${report.summary.netRevenue.toStringAsFixed(0)}',
        icon: Icons.receipt_long_outlined,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final crossAxisCount =
            width >= 1000
                ? 3
                : width >= 680
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
          itemBuilder: (_, index) => _SummaryCard(item: items[index]),
        );
      },
    );
  }
}

class _SummaryItem {
  final String title;
  final String value;
  final IconData icon;

  const _SummaryItem({
    required this.title,
    required this.value,
    required this.icon,
  });
}

class _SummaryCard extends StatelessWidget {
  final _SummaryItem item;

  const _SummaryCard({required this.item});

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

class _DailyChartCard extends StatelessWidget {
  final List<SalesDailyBreakdownItem> items;

  const _DailyChartCard({required this.items});

  @override
  Widget build(BuildContext context) {
    final maxRevenue = items.fold<double>(
      0,
      (max, item) => item.revenue > max ? item.revenue : max,
    );

    return _ReportCard(
      title: 'Daily Sales Trend',
      icon: Icons.bar_chart,
      child:
          items.isEmpty
              ? const _EmptyText('No daily sales data found')
              : Column(
                children:
                    items.map((item) {
                      final percent =
                          maxRevenue <= 0 ? 0.0 : item.revenue / maxRevenue;

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 86,
                              child: Text(
                                _dateText(item.date),
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                            Expanded(
                              child: LinearProgressIndicator(
                                value: percent.clamp(0.0, 1.0),
                                minHeight: 10,
                                borderRadius: BorderRadius.circular(99),
                              ),
                            ),
                            const SizedBox(width: 10),
                            SizedBox(
                              width: 110,
                              child: Text(
                                'Rs ${item.revenue.toStringAsFixed(0)}',
                                textAlign: TextAlign.end,
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
              ),
    );
  }
}

class _ProductProfitabilityCard extends StatelessWidget {
  final List<SalesProductBreakdownItem> items;

  const _ProductProfitabilityCard({required this.items});

  @override
  Widget build(BuildContext context) {
    return _ReportCard(
      title: 'Product Profitability',
      icon: Icons.inventory_2_outlined,
      child:
          items.isEmpty
              ? const _EmptyText('No product sales found')
              : Column(
                children: [
                  const _TableHeader(
                    columns: ['Product', 'Qty', 'Revenue', 'Profit', 'Margin'],
                    flexes: [4, 1, 2, 2, 2],
                  ),
                  const Divider(),
                  for (final item in items.take(20))
                    _TableRowLine(
                      values: [
                        item.productName,
                        item.quantity.toString(),
                        'Rs ${item.revenue.toStringAsFixed(0)}',
                        'Rs ${item.grossProfit.toStringAsFixed(0)}',
                        '${item.marginPercent.toStringAsFixed(1)}%',
                      ],
                      flexes: const [4, 1, 2, 2, 2],
                    ),
                ],
              ),
    );
  }
}

class _CategoryMarginCard extends StatelessWidget {
  final List<SalesCategoryBreakdownItem> items;

  const _CategoryMarginCard({required this.items});

  @override
  Widget build(BuildContext context) {
    return _ReportCard(
      title: 'Category Margins',
      icon: Icons.category_outlined,
      child:
          items.isEmpty
              ? const _EmptyText('No category data found')
              : Column(
                children: [
                  const _TableHeader(
                    columns: ['Category', 'Revenue', 'Profit', 'Margin'],
                    flexes: [4, 2, 2, 2],
                  ),
                  const Divider(),
                  for (final item in items.take(15))
                    _TableRowLine(
                      values: [
                        item.categoryName,
                        'Rs ${item.revenue.toStringAsFixed(0)}',
                        'Rs ${item.grossProfit.toStringAsFixed(0)}',
                        '${item.marginPercent.toStringAsFixed(1)}%',
                      ],
                      flexes: const [4, 2, 2, 2],
                    ),
                ],
              ),
    );
  }
}

class _CustomerBreakdownCard extends StatelessWidget {
  final List<SalesCustomerBreakdownItem> items;

  const _CustomerBreakdownCard({required this.items});

  @override
  Widget build(BuildContext context) {
    return _ReportCard(
      title: 'Customer Sales',
      icon: Icons.people_outline,
      child:
          items.isEmpty
              ? const _EmptyText('No customer data found')
              : Column(
                children: [
                  const _TableHeader(
                    columns: ['Customer', 'Orders', 'Revenue'],
                    flexes: [4, 2, 2],
                  ),
                  const Divider(),
                  for (final item in items.take(15))
                    _TableRowLine(
                      values: [
                        item.customerName,
                        item.orders.toString(),
                        'Rs ${item.revenue.toStringAsFixed(0)}',
                      ],
                      flexes: const [4, 2, 2],
                    ),
                ],
              ),
    );
  }
}

class _BranchBreakdownCard extends StatelessWidget {
  final List<SalesBranchBreakdownItem> items;

  const _BranchBreakdownCard({required this.items});

  @override
  Widget build(BuildContext context) {
    return _ReportCard(
      title: 'Branch Breakdown',
      icon: Icons.storefront_outlined,
      child:
          items.isEmpty
              ? const _EmptyText('No branch data found')
              : Column(
                children: [
                  const _TableHeader(
                    columns: ['Branch', 'Orders', 'Revenue', 'Margin'],
                    flexes: [4, 2, 2, 2],
                  ),
                  const Divider(),
                  for (final item in items.take(15))
                    _TableRowLine(
                      values: [
                        item.branchName,
                        item.orders.toString(),
                        'Rs ${item.revenue.toStringAsFixed(0)}',
                        '${item.marginPercent.toStringAsFixed(1)}%',
                      ],
                      flexes: const [4, 2, 2, 2],
                    ),
                ],
              ),
    );
  }
}

class _ReportCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;

  const _ReportCard({
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

class _TableHeader extends StatelessWidget {
  final List<String> columns;
  final List<int> flexes;

  const _TableHeader({required this.columns, required this.flexes});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(columns.length, (index) {
        return Expanded(
          flex: flexes[index],
          child: Text(
            columns[index],
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: index == 0 ? TextAlign.start : TextAlign.end,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w900),
          ),
        );
      }),
    );
  }
}

class _TableRowLine extends StatelessWidget {
  final List<String> values;
  final List<int> flexes;

  const _TableRowLine({required this.values, required this.flexes});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: List.generate(values.length, (index) {
          return Expanded(
            flex: flexes[index],
            child: Text(
              values[index],
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: index == 0 ? TextAlign.start : TextAlign.end,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          );
        }),
      ),
    );
  }
}

class _EmptyText extends StatelessWidget {
  final String text;

  const _EmptyText(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 22),
      child: Center(child: Text(text)),
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
