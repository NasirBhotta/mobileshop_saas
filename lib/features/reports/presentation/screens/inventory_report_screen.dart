import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobileshop_saas/features/reports/presentation/providers/business_report_provider.dart';
import 'package:mobileshop_saas/features/reports/presentation/widgets/reports_back_button.dart';
import '../../../../core/entitlements/entitlement_provider.dart';

import '../../data/models/business_report_models.dart';

class InventoryReportScreen extends ConsumerWidget {
  const InventoryReportScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reportAsync = ref.watch(inventoryAnalyticsReportProvider);
    final range = ref.watch(businessReportDateRangeProvider);
    final allBranches = ref.watch(businessReportAllBranchesProvider);
    final exportState = ref.watch(businessReportExportControllerProvider);
    final exportEnabled =
        ref.watch(reportFeatureEntitlementProvider('reports.export')).value !=
        false;

    return Scaffold(
      appBar: AppBar(
        leading: const ReportsBackButton(),
        title: const Text('Inventory Report'),
        actions: [
          if (exportEnabled)
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
                      ref.invalidate(inventoryAnalyticsReportProvider);
                    },
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final isWide = constraints.maxWidth >= 960;

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
                                            child: _LowStockCard(
                                              items: report.lowStock,
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: _CategoryStockCard(
                                              items: report.categoryStock,
                                            ),
                                          ),
                                        ],
                                      )
                                    else ...[
                                      _LowStockCard(items: report.lowStock),
                                      const SizedBox(height: 12),
                                      _CategoryStockCard(
                                        items: report.categoryStock,
                                      ),
                                    ],
                                    const SizedBox(height: 14),
                                    if (isWide)
                                      Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Expanded(
                                            child: _FastMovingCard(
                                              items: report.fastMoving,
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: _DeadStockCard(
                                              items: report.deadStock,
                                            ),
                                          ),
                                        ],
                                      )
                                    else ...[
                                      _FastMovingCard(items: report.fastMoving),
                                      const SizedBox(height: 12),
                                      _DeadStockCard(items: report.deadStock),
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
        .buildCsv(reportType: BusinessReportType.inventory);

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
              subtitle: const Text('Consolidated stock analytics'),
              contentPadding: EdgeInsets.zero,
              onChanged: (value) {
                ref.read(businessReportAllBranchesProvider.notifier).state =
                    value;
                ref.invalidate(inventoryAnalyticsReportProvider);
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

    ref.invalidate(inventoryAnalyticsReportProvider);
  }
}

class _HeaderCard extends StatelessWidget {
  final InventoryAnalyticsReportModel report;

  const _HeaderCard({required this.report});

  @override
  Widget build(BuildContext context) {
    final summary = report.summary;

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
                  'Stock Valuation',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 6),
                Text(
                  'Rs ${summary.stockValue.toStringAsFixed(0)}',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${summary.totalProducts} products · ${summary.totalStock.toStringAsFixed(0)} stock units',
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
                  avatar: const Icon(Icons.warning_amber_outlined, size: 16),
                  label: Text('Low Stock ${summary.lowStockCount}'),
                ),
                Chip(
                  avatar: const Icon(
                    Icons.remove_shopping_cart_outlined,
                    size: 16,
                  ),
                  label: Text('Out of Stock ${summary.outOfStockCount}'),
                ),
                Chip(
                  avatar: const Icon(Icons.inventory_2_outlined, size: 16),
                  label: Text('Items ${summary.totalProducts}'),
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
  final InventoryAnalyticsReportModel report;

  const _SummaryGrid({required this.report});

  @override
  Widget build(BuildContext context) {
    final summary = report.summary;

    final items = [
      _KpiItem(
        title: 'Products',
        value: summary.totalProducts.toString(),
        icon: Icons.inventory_2_outlined,
      ),
      _KpiItem(
        title: 'Total Stock',
        value: summary.totalStock.toStringAsFixed(0),
        icon: Icons.storage_outlined,
      ),
      _KpiItem(
        title: 'Stock Value',
        value: 'Rs ${summary.stockValue.toStringAsFixed(0)}',
        icon: Icons.account_balance_wallet_outlined,
      ),
      _KpiItem(
        title: 'Low Stock',
        value: summary.lowStockCount.toString(),
        icon: Icons.warning_amber_outlined,
      ),
      _KpiItem(
        title: 'Out of Stock',
        value: summary.outOfStockCount.toString(),
        icon: Icons.remove_circle_outline,
      ),
      _KpiItem(
        title: 'Dead Stock',
        value: report.deadStock.length.toString(),
        icon: Icons.block_outlined,
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

class _LowStockCard extends StatelessWidget {
  final List<InventoryLowStockItem> items;

  const _LowStockCard({required this.items});

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'Low Stock',
      icon: Icons.warning_amber_outlined,
      child:
          items.isEmpty
              ? const _EmptyText('No low stock products')
              : Column(
                children: [
                  const _TableHeader(
                    columns: ['Product', 'Qty', 'Threshold', 'Value'],
                    flexes: [4, 2, 2, 2],
                  ),
                  const Divider(),
                  for (final item in items.take(25))
                    _TableRowLine(
                      values: [
                        item.productName,
                        item.quantity.toStringAsFixed(0),
                        item.reorderThreshold.toStringAsFixed(0),
                        'Rs ${item.stockValue.toStringAsFixed(0)}',
                      ],
                      flexes: const [4, 2, 2, 2],
                    ),
                ],
              ),
    );
  }
}

class _CategoryStockCard extends StatelessWidget {
  final List<InventoryCategoryStockItem> items;

  const _CategoryStockCard({required this.items});

  @override
  Widget build(BuildContext context) {
    final total = items.fold<double>(0, (sum, item) => sum + item.stockValue);

    return _SectionCard(
      title: 'Category Stock Value',
      icon: Icons.category_outlined,
      child:
          items.isEmpty
              ? const _EmptyText('No category stock data')
              : Column(
                children: [
                  for (final item in items.take(20)) ...[
                    _BreakdownRow(
                      label: item.categoryName,
                      amount: item.stockValue,
                      subtitle: 'Qty ${item.stockQty.toStringAsFixed(0)}',
                      total: total,
                    ),
                    const SizedBox(height: 10),
                  ],
                ],
              ),
    );
  }
}

class _FastMovingCard extends StatelessWidget {
  final List<InventoryMovingItem> items;

  const _FastMovingCard({required this.items});

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'Fast Moving Products',
      icon: Icons.trending_up,
      child:
          items.isEmpty
              ? const _EmptyText('No fast moving data')
              : Column(
                children: [
                  const _TableHeader(
                    columns: ['Product', 'Sold', 'Revenue', 'Profit'],
                    flexes: [4, 2, 2, 2],
                  ),
                  const Divider(),
                  for (final item in items.take(25))
                    _TableRowLine(
                      values: [
                        item.productName,
                        item.quantitySold.toStringAsFixed(0),
                        'Rs ${item.revenue.toStringAsFixed(0)}',
                        'Rs ${item.grossProfit.toStringAsFixed(0)}',
                      ],
                      flexes: const [4, 2, 2, 2],
                    ),
                ],
              ),
    );
  }
}

class _DeadStockCard extends StatelessWidget {
  final List<InventoryDeadStockItem> items;

  const _DeadStockCard({required this.items});

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'Dead Stock',
      icon: Icons.block_outlined,
      child:
          items.isEmpty
              ? const _EmptyText('No dead stock found')
              : Column(
                children: [
                  const _TableHeader(
                    columns: ['Product', 'Qty', 'Value'],
                    flexes: [5, 2, 3],
                  ),
                  const Divider(),
                  for (final item in items.take(25))
                    _TableRowLine(
                      values: [
                        item.productName,
                        item.quantity.toStringAsFixed(0),
                        'Rs ${item.stockValue.toStringAsFixed(0)}',
                      ],
                      flexes: const [5, 2, 3],
                    ),
                ],
              ),
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

class _BreakdownRow extends StatelessWidget {
  final String label;
  final String subtitle;
  final double amount;
  final double total;

  const _BreakdownRow({
    required this.label,
    required this.subtitle,
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
        const SizedBox(height: 3),
        Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 5),
        LinearProgressIndicator(
          value: percent.clamp(0.0, 1.0),
          minHeight: 7,
          borderRadius: BorderRadius.circular(99),
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
