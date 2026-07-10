import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobileshop_saas/features/reports/presentation/providers/business_report_provider.dart';
import 'package:mobileshop_saas/features/reports/presentation/widgets/reports_back_button.dart';

import '../../data/models/business_report_models.dart';

class ProfitLossReportScreen extends ConsumerWidget {
  const ProfitLossReportScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reportAsync = ref.watch(profitLossReportProvider);
    final range = ref.watch(businessReportDateRangeProvider);
    final allBranches = ref.watch(businessReportAllBranchesProvider);
    final exportState = ref.watch(businessReportExportControllerProvider);

    return Scaffold(
      appBar: AppBar(
        leading: const ReportsBackButton(),
        title: const Text('Profit & Loss'),
        actions: [
          IconButton(
            tooltip: 'Export CSV',
            onPressed:
                exportState.isLoading ? null : () => _exportCsv(context, ref),
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
            _ReportFilters(
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
                      ref.invalidate(profitLossReportProvider);
                    },
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final isWide = constraints.maxWidth >= 920;

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
                                    _SummaryGrid(report: report),
                                    const SizedBox(height: 14),
                                    if (isWide)
                                      Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Expanded(
                                            child: _ProfitStatementCard(
                                              report: report,
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: _ExpenseBreakdownCard(
                                              items: report.expenseBreakdown,
                                            ),
                                          ),
                                        ],
                                      )
                                    else ...[
                                      _ProfitStatementCard(report: report),
                                      const SizedBox(height: 12),
                                      _ExpenseBreakdownCard(
                                        items: report.expenseBreakdown,
                                      ),
                                    ],
                                    const SizedBox(height: 14),
                                    _DailyProfitTrendCard(
                                      items: report.dailyBreakdown,
                                    ),
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
    final csv = await ref
        .read(businessReportExportControllerProvider.notifier)
        .buildCsv(reportType: BusinessReportType.profitLoss);

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

class _ReportFilters extends ConsumerWidget {
  final DateTime from;
  final DateTime to;
  final bool allBranches;

  const _ReportFilters({
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

            final branchToggle = SwitchListTile(
              value: allBranches,
              title: const Text('All Branches'),
              subtitle: const Text('Consolidated profit/loss'),
              contentPadding: EdgeInsets.zero,
              onChanged: (value) {
                ref.read(businessReportAllBranchesProvider.notifier).state =
                    value;
                ref.invalidate(profitLossReportProvider);
              },
            );

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

    ref.invalidate(profitLossReportProvider);
  }
}

class _HeaderCard extends StatelessWidget {
  final ProfitLossReportModel report;

  const _HeaderCard({required this.report});

  @override
  Widget build(BuildContext context) {
    final summary = report.summary;
    final isProfit = summary.netProfit >= 0;

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
                  'Net Profit',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 6),
                Text(
                  'Rs ${summary.netProfit.toStringAsFixed(0)}',
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
                  'Net Margin ${summary.netMarginPercent.toStringAsFixed(1)}%',
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
                  label: Text(
                    'Revenue Rs ${summary.revenue.toStringAsFixed(0)}',
                  ),
                ),
                Chip(
                  avatar: const Icon(Icons.payments_outlined, size: 16),
                  label: Text('COGS Rs ${summary.cogs.toStringAsFixed(0)}'),
                ),
                Chip(
                  avatar: const Icon(Icons.receipt_long_outlined, size: 16),
                  label: Text(
                    'Expenses Rs ${summary.expenses.toStringAsFixed(0)}',
                  ),
                ),
                Chip(
                  avatar: Icon(
                    report.exportAllowed ? Icons.lock_open : Icons.lock_outline,
                    size: 16,
                  ),
                  label: Text(
                    report.exportAllowed
                        ? 'Export enabled'
                        : 'Export Business+',
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

class _SummaryGrid extends StatelessWidget {
  final ProfitLossReportModel report;

  const _SummaryGrid({required this.report});

  @override
  Widget build(BuildContext context) {
    final summary = report.summary;

    final items = [
      _KpiItem(
        title: 'Revenue',
        value: 'Rs ${summary.revenue.toStringAsFixed(0)}',
        icon: Icons.point_of_sale_outlined,
      ),
      _KpiItem(
        title: 'COGS',
        value: 'Rs ${summary.cogs.toStringAsFixed(0)}',
        icon: Icons.inventory_2_outlined,
      ),
      _KpiItem(
        title: 'Gross Profit',
        value: 'Rs ${summary.grossProfit.toStringAsFixed(0)}',
        icon: Icons.trending_up,
      ),
      _KpiItem(
        title: 'Gross Margin',
        value: '${summary.grossMarginPercent.toStringAsFixed(1)}%',
        icon: Icons.percent,
      ),
      _KpiItem(
        title: 'Expenses',
        value: 'Rs ${summary.expenses.toStringAsFixed(0)}',
        icon: Icons.receipt_long_outlined,
      ),
      _KpiItem(
        title: 'Draft Expenses',
        value: 'Rs ${summary.draftExpenses.toStringAsFixed(0)}',
        icon: Icons.pending_actions_outlined,
      ),
      _KpiItem(
        title: 'Net Profit',
        value: 'Rs ${summary.netProfit.toStringAsFixed(0)}',
        icon: Icons.account_balance_wallet_outlined,
      ),
      _KpiItem(
        title: 'Net Margin',
        value: '${summary.netMarginPercent.toStringAsFixed(1)}%',
        icon: Icons.analytics_outlined,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount =
            constraints.maxWidth >= 1000
                ? 4
                : constraints.maxWidth >= 700
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

class _ProfitStatementCard extends StatelessWidget {
  final ProfitLossReportModel report;

  const _ProfitStatementCard({required this.report});

  @override
  Widget build(BuildContext context) {
    final summary = report.summary;

    return _SectionCard(
      title: 'Profit Statement',
      icon: Icons.account_balance_outlined,
      child: Column(
        children: [
          _MoneyRow(label: 'Sales Revenue', value: summary.revenue),
          _MoneyRow(label: 'Cost of Goods Sold', value: summary.cogs),
          const Divider(),
          _MoneyRow(
            label: 'Gross Profit',
            value: summary.grossProfit,
            bold: true,
            highlight: true,
          ),
          _PlainRow(
            label: 'Gross Margin',
            value: '${summary.grossMarginPercent.toStringAsFixed(1)}%',
          ),
          const SizedBox(height: 8),
          _MoneyRow(label: 'Operating Expenses', value: summary.expenses),
          _MoneyRow(label: 'Draft Expenses', value: summary.draftExpenses),
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

class _ExpenseBreakdownCard extends StatelessWidget {
  final List<ReportMoneyBreakdownItem> items;

  const _ExpenseBreakdownCard({required this.items});

  @override
  Widget build(BuildContext context) {
    final total = items.fold<double>(0, (sum, item) => sum + item.amount);

    return _SectionCard(
      title: 'Expense Breakdown',
      icon: Icons.pie_chart_outline,
      child:
          items.isEmpty
              ? const _EmptyText('No expense data found')
              : Column(
                children: [
                  for (final item in items) ...[
                    _BreakdownRow(
                      label: item.label,
                      amount: item.amount,
                      total: total,
                    ),
                    const SizedBox(height: 10),
                  ],
                ],
              ),
    );
  }
}

class _DailyProfitTrendCard extends StatelessWidget {
  final List<ReportDailyProfitItem> items;

  const _DailyProfitTrendCard({required this.items});

  @override
  Widget build(BuildContext context) {
    final maxAmount = items.fold<double>(0, (max, item) {
      final value =
          item.revenue.abs() > item.netProfit.abs()
              ? item.revenue.abs()
              : item.netProfit.abs();

      return value > max ? value : max;
    });

    return _SectionCard(
      title: 'Daily Profit Trend',
      icon: Icons.bar_chart,
      child:
          items.isEmpty
              ? const _EmptyText('No daily profit data found')
              : Column(
                children: [
                  for (final item in items) ...[
                    _DailyTrendRow(item: item, maxAmount: maxAmount),
                    const SizedBox(height: 12),
                  ],
                ],
              ),
    );
  }
}

class _DailyTrendRow extends StatelessWidget {
  final ReportDailyProfitItem item;
  final double maxAmount;

  const _DailyTrendRow({required this.item, required this.maxAmount});

  @override
  Widget build(BuildContext context) {
    final revenuePercent = maxAmount <= 0 ? 0.0 : item.revenue / maxAmount;
    final profitPercent =
        maxAmount <= 0 ? 0.0 : item.netProfit.abs() / maxAmount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            SizedBox(
              width: 90,
              child: Text(
                _dateText(item.date),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            Expanded(
              child: Text(
                'Revenue Rs ${item.revenue.toStringAsFixed(0)} · Net Rs ${item.netProfit.toStringAsFixed(0)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        const SizedBox(height: 5),
        LinearProgressIndicator(
          value: revenuePercent.clamp(0.0, 1.0),
          minHeight: 8,
          borderRadius: BorderRadius.circular(99),
        ),
        const SizedBox(height: 4),
        LinearProgressIndicator(
          value: profitPercent.clamp(0.0, 1.0),
          minHeight: 6,
          borderRadius: BorderRadius.circular(99),
        ),
      ],
    );
  }
}

class _BreakdownRow extends StatelessWidget {
  final String label;
  final double amount;
  final double total;

  const _BreakdownRow({
    required this.label,
    required this.amount,
    required this.total,
  });

  @override
  Widget build(BuildContext context) {
    final percent = total <= 0 ? 0.0 : amount / total;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            Text(
              'Rs ${amount.toStringAsFixed(0)}',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
          ],
        ),
        const SizedBox(height: 5),
        LinearProgressIndicator(
          value: percent.clamp(0.0, 1.0),
          minHeight: 7,
          borderRadius: BorderRadius.circular(99),
        ),
        const SizedBox(height: 3),
        Text(
          '${(percent * 100).toStringAsFixed(1)}%',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
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

  const _MoneyRow({
    required this.label,
    required this.value,
    this.bold = false,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    final color =
        highlight
            ? value >= 0
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.error
            : null;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
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
      padding: const EdgeInsets.symmetric(vertical: 6),
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
