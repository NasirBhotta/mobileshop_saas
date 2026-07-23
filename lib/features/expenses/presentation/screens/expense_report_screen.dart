import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobileshop_saas/features/expenses/presentation/providers/expense_provider.dart';

import '../../data/models/expense_models.dart';

class ExpenseReportScreen extends ConsumerWidget {
  const ExpenseReportScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reportAsync = ref.watch(expenseReportProvider);
    final range = ref.watch(expenseDateRangeProvider);
    final historyLimit = ref.watch(expenseHistoryLimitProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Expense Report')),
      body: SafeArea(
        child: Column(
          children: [
            _ReportFilters(from: range.from, to: range.to),
            const Divider(height: 1),
            Expanded(
              child: reportAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) => _ReportErrorView(error: error),
                data: (report) {
                  return RefreshIndicator(
                    onRefresh: () async {
                      await ref
                          .read(expenseSyncControllerProvider.notifier)
                          .sync();
                      await ref.read(expenseReportProvider.future);
                    },
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final isWide = constraints.maxWidth >= 900;

                        return ListView(
                          padding: const EdgeInsets.all(16),
                          children: [
                            Center(
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 1100,
                                ),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    _ReportHeader(report: report),
                                    const SizedBox(height: 16),
                                    if (isWide)
                                      Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Expanded(
                                            child: _ProfitSummaryCard(
                                              report: report,
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: _ExpenseSummaryCard(
                                              report: report,
                                              historyLimit: historyLimit,
                                            ),
                                          ),
                                        ],
                                      )
                                    else ...[
                                      _ProfitSummaryCard(report: report),
                                      const SizedBox(height: 12),
                                      _ExpenseSummaryCard(
                                        report: report,
                                        historyLimit: historyLimit,
                                      ),
                                    ],
                                    const SizedBox(height: 16),
                                    if (isWide)
                                      Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Expanded(
                                            child: _BreakdownCard(
                                              title: 'Expenses by Category',
                                              items: report.byCategory,
                                              emptyMessage:
                                                  'No category expenses found',
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: _BreakdownCard(
                                              title: 'Expenses by Payment Mode',
                                              items: report.byPaymentMode,
                                              emptyMessage:
                                                  'No payment mode data found',
                                            ),
                                          ),
                                        ],
                                      )
                                    else ...[
                                      _BreakdownCard(
                                        title: 'Expenses by Category',
                                        items: report.byCategory,
                                        emptyMessage:
                                            'No category expenses found',
                                      ),
                                      const SizedBox(height: 12),
                                      _BreakdownCard(
                                        title: 'Expenses by Payment Mode',
                                        items: report.byPaymentMode,
                                        emptyMessage:
                                            'No payment mode data found',
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
}

class _ReportFilters extends ConsumerWidget {
  final DateTime from;
  final DateTime to;

  const _ReportFilters({required this.from, required this.to});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categoriesAsync = ref.watch(expenseCategoriesProvider);
    final selectedCategoryId = ref.watch(selectedExpenseCategoryProvider);

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

            final categoryDropdown = categoriesAsync.when(
              loading: () => const LinearProgressIndicator(),
              error: (_, _) => const SizedBox.shrink(),
              data: (categories) {
                return DropdownButtonFormField<String>(
                  initialValue: selectedCategoryId ?? '__all__',
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Category',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: '__all__',
                      child: Text('All Categories'),
                    ),
                    for (final category in categories)
                      DropdownMenuItem(
                        value: category.id,
                        child: Text(category.name),
                      ),
                  ],
                  onChanged: (value) {
                    ref.read(selectedExpenseCategoryProvider.notifier).state =
                        value == '__all__' ? null : value;

                    ref.invalidate(expenseReportProvider);
                    ref.invalidate(expensesProvider);
                  },
                );
              },
            );

            if (isWide) {
              return Row(
                children: [
                  Expanded(child: dateButton),
                  const SizedBox(width: 12),
                  Expanded(child: categoryDropdown),
                ],
              );
            }

            return Column(
              children: [
                dateButton,
                const SizedBox(height: 10),
                categoryDropdown,
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _pickDateRange(BuildContext context, WidgetRef ref) async {
    final current = ref.read(expenseDateRangeProvider);

    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: DateTimeRange(start: current.from, end: current.to),
    );

    if (picked == null) return;

    ref.read(expenseDateRangeProvider.notifier).state = ExpenseDateRange(
      from: DateTime(picked.start.year, picked.start.month, picked.start.day),
      to: DateTime(picked.end.year, picked.end.month, picked.end.day),
    );

    ref.invalidate(expenseReportProvider);
    ref.invalidate(expensesProvider);
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
          labelText: 'Report Date Range',
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
  final ExpenseProfitReportModel report;

  const _ReportHeader({required this.report});

  @override
  Widget build(BuildContext context) {
    final isProfit = report.netProfit >= 0;

    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 720;

            final left = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Net Profit',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 6),
                Text(
                  'Rs ${report.netProfit.toStringAsFixed(0)}',
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
                  avatar: const Icon(
                    Icons.workspace_premium_outlined,
                    size: 16,
                  ),
                  label: Text('Plan: ${report.plan.toUpperCase()}'),
                ),
                Chip(
                  avatar: const Icon(Icons.receipt_long_outlined, size: 16),
                  label: Text(
                    'Expenses: Rs ${report.totalExpenses.toStringAsFixed(0)}',
                  ),
                ),
                Chip(
                  avatar: const Icon(Icons.point_of_sale_outlined, size: 16),
                  label: Text(
                    'Sales: Rs ${report.salesRevenue.toStringAsFixed(0)}',
                  ),
                ),
              ],
            );

            if (isWide) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(child: left),
                  const SizedBox(width: 14),
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

class _ProfitSummaryCard extends StatelessWidget {
  final ExpenseProfitReportModel report;

  const _ProfitSummaryCard({required this.report});

  @override
  Widget build(BuildContext context) {
    return _ReportCard(
      title: 'Profit Summary',
      icon: Icons.trending_up,
      children: [
        _MoneyRow(label: 'Sales Revenue', value: report.salesRevenue),
        _MoneyRow(label: 'COGS', value: report.cogs, negativeStyle: true),
        const Divider(),
        _MoneyRow(label: 'Gross Profit', value: report.grossProfit, bold: true),
        _MoneyRow(
          label: 'Expenses',
          value: report.totalExpenses,
          negativeStyle: true,
        ),
        const Divider(),
        _MoneyRow(
          label: 'Net Profit',
          value: report.netProfit,
          bold: true,
          highlight: true,
        ),
      ],
    );
  }
}

class _ExpenseSummaryCard extends StatelessWidget {
  final ExpenseProfitReportModel report;
  final AsyncValue<num?> historyLimit;

  const _ExpenseSummaryCard({required this.report, required this.historyLimit});

  @override
  Widget build(BuildContext context) {
    return _ReportCard(
      title: 'Expense Summary',
      icon: Icons.receipt_long_outlined,
      children: [
        _MoneyRow(
          label: 'Confirmed Expenses',
          value: report.totalExpenses,
          bold: true,
        ),
        _MoneyRow(label: 'Draft Expenses', value: report.draftExpenses),
        const Divider(),
        _PlainInfoRow(
          label: 'Report Range',
          value: '${_dateText(report.dateFrom)} - ${_dateText(report.dateTo)}',
        ),
        _PlainInfoRow(
          label: 'Plan Limit',
          value: historyLimit.when(
            data: _historyLimitText,
            loading: () => 'Loading...',
            error: (_, _) => 'Unavailable',
          ),
        ),
      ],
    );
  }
}

class _BreakdownCard extends StatelessWidget {
  final String title;
  final List<ExpenseReportBreakdownItem> items;
  final String emptyMessage;

  const _BreakdownCard({
    required this.title,
    required this.items,
    required this.emptyMessage,
  });

  @override
  Widget build(BuildContext context) {
    final total = items.fold<double>(0, (sum, item) => sum + item.total);

    return _ReportCard(
      title: title,
      icon: Icons.pie_chart_outline,
      children: [
        if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: Center(
              child: Text(
                emptyMessage,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          )
        else
          for (final item in items) ...[
            _BreakdownRow(item: item, grandTotal: total),
            const SizedBox(height: 10),
          ],
      ],
    );
  }
}

class _BreakdownRow extends StatelessWidget {
  final ExpenseReportBreakdownItem item;
  final double grandTotal;

  const _BreakdownRow({required this.item, required this.grandTotal});

  @override
  Widget build(BuildContext context) {
    final percent = grandTotal <= 0 ? 0.0 : item.total / grandTotal;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                item.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              'Rs ${item.total.toStringAsFixed(0)}',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
          ],
        ),
        const SizedBox(height: 5),
        LinearProgressIndicator(
          value: percent.clamp(0.0, 1.0),
          minHeight: 6,
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

class _ReportCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;

  const _ReportCard({
    required this.title,
    required this.icon,
    required this.children,
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
            ...children,
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
  final bool negativeStyle;

  const _MoneyRow({
    required this.label,
    required this.value,
    this.bold = false,
    this.highlight = false,
    this.negativeStyle = false,
  });

  @override
  Widget build(BuildContext context) {
    final color =
        highlight
            ? value >= 0
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.error
            : negativeStyle
            ? Theme.of(context).colorScheme.error
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

class _PlainInfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _PlainInfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
          ),
          Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _ReportErrorView extends StatelessWidget {
  final Object error;

  const _ReportErrorView({required this.error});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
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

String _historyLimitText(num? days) {
  if (days == 30) {
    return 'Last 30 days';
  }
  if (days == 365) {
    return 'Up to 1 year';
  }
  return days == null ? 'Unlimited' : 'Last ${days.toInt()} days';
}

String _dateText(DateTime date) {
  final day = date.day.toString().padLeft(2, '0');
  final month = date.month.toString().padLeft(2, '0');
  final year = date.year.toString();

  return '$day-$month-$year';
}
