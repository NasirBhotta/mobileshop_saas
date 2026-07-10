import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobileshop_saas/features/reports/presentation/providers/business_report_provider.dart';
import 'package:mobileshop_saas/features/reports/presentation/widgets/reports_back_button.dart';

import '../../data/models/business_report_models.dart';

class CashFlowReportScreen extends ConsumerWidget {
  const CashFlowReportScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reportAsync = ref.watch(cashFlowReportProvider);
    final range = ref.watch(businessReportDateRangeProvider);
    final allBranches = ref.watch(businessReportAllBranchesProvider);
    final exportState = ref.watch(businessReportExportControllerProvider);

    return Scaffold(
      appBar: AppBar(
        leading: const ReportsBackButton(),
        title: const Text('Cash Flow Report'),
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
                      ref.invalidate(cashFlowReportProvider);
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
                                            child: _PaymentBreakdownCard(
                                              title: 'Cash In by Payment Mode',
                                              icon: Icons.call_received,
                                              items:
                                                  report.salesPaymentBreakdown,
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: _PaymentBreakdownCard(
                                              title: 'Cash Out by Payment Mode',
                                              icon: Icons.call_made,
                                              items:
                                                  report
                                                      .expensePaymentBreakdown,
                                            ),
                                          ),
                                        ],
                                      )
                                    else ...[
                                      _PaymentBreakdownCard(
                                        title: 'Cash In by Payment Mode',
                                        icon: Icons.call_received,
                                        items: report.salesPaymentBreakdown,
                                      ),
                                      const SizedBox(height: 12),
                                      _PaymentBreakdownCard(
                                        title: 'Cash Out by Payment Mode',
                                        icon: Icons.call_made,
                                        items: report.expensePaymentBreakdown,
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
    final csv = await ref
        .read(businessReportExportControllerProvider.notifier)
        .buildCsv(reportType: BusinessReportType.cashFlow);

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
              subtitle: const Text('Consolidated cash flow'),
              contentPadding: EdgeInsets.zero,
              onChanged: (value) {
                ref.read(businessReportAllBranchesProvider.notifier).state =
                    value;
                ref.invalidate(cashFlowReportProvider);
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

    ref.invalidate(cashFlowReportProvider);
  }
}

class _HeaderCard extends StatelessWidget {
  final CashFlowReportModel report;

  const _HeaderCard({required this.report});

  @override
  Widget build(BuildContext context) {
    final summary = report.summary;
    final isPositive = summary.netCash >= 0;

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
                  'Net Cash Flow',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 6),
                Text(
                  'Rs ${summary.netCash.toStringAsFixed(0)}',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    color:
                        isPositive
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.error,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Cash In Rs ${summary.cashIn.toStringAsFixed(0)} · Cash Out Rs ${summary.cashOut.toStringAsFixed(0)}',
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
                  avatar: const Icon(Icons.call_received, size: 16),
                  label: Text('In Rs ${summary.cashIn.toStringAsFixed(0)}'),
                ),
                Chip(
                  avatar: const Icon(Icons.call_made, size: 16),
                  label: Text('Out Rs ${summary.cashOut.toStringAsFixed(0)}'),
                ),
                Chip(
                  avatar: Icon(
                    isPositive ? Icons.trending_up : Icons.trending_down,
                    size: 16,
                  ),
                  label: Text(isPositive ? 'Positive' : 'Negative'),
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
  final CashFlowReportModel report;

  const _SummaryGrid({required this.report});

  @override
  Widget build(BuildContext context) {
    final summary = report.summary;

    final items = [
      _KpiItem(
        title: 'Cash In',
        value: 'Rs ${summary.cashIn.toStringAsFixed(0)}',
        icon: Icons.call_received,
      ),
      _KpiItem(
        title: 'Cash Out',
        value: 'Rs ${summary.cashOut.toStringAsFixed(0)}',
        icon: Icons.call_made,
      ),
      _KpiItem(
        title: 'Net Cash',
        value: 'Rs ${summary.netCash.toStringAsFixed(0)}',
        icon: Icons.account_balance_wallet_outlined,
      ),
      _KpiItem(
        title: 'Sales Modes',
        value: report.salesPaymentBreakdown.length.toString(),
        icon: Icons.payment_outlined,
      ),
      _KpiItem(
        title: 'Expense Modes',
        value: report.expensePaymentBreakdown.length.toString(),
        icon: Icons.receipt_long_outlined,
      ),
      _KpiItem(
        title: 'Status',
        value: summary.netCash >= 0 ? 'Positive' : 'Negative',
        icon: summary.netCash >= 0 ? Icons.trending_up : Icons.trending_down,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount =
            constraints.maxWidth >= 1000
                ? 3
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

class _PaymentBreakdownCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<ReportMoneyBreakdownItem> items;

  const _PaymentBreakdownCard({
    required this.title,
    required this.icon,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    final total = items.fold<double>(0, (sum, item) => sum + item.amount);

    return _SectionCard(
      title: title,
      icon: icon,
      child:
          items.isEmpty
              ? const _EmptyText('No payment data found')
              : Column(
                children: [
                  for (final item in items.take(25)) ...[
                    _BreakdownRow(
                      label: item.label,
                      amount: item.amount,
                      total: total,
                    ),
                    const SizedBox(height: 12),
                  ],
                ],
              ),
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
