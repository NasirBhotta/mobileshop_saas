import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobileshop_saas/core/constants/app_colors.dart';
import 'package:mobileshop_saas/features/suppliers/data/models/procurement_models.dart';
import 'package:mobileshop_saas/features/suppliers/data/models/supplier_sales_analytics_models.dart';
import 'package:mobileshop_saas/features/suppliers/presentation/providers/supplier_sales_analytics_provider.dart';

class SupplierSalesAnalyticsScreen extends ConsumerStatefulWidget {
  const SupplierSalesAnalyticsScreen({super.key, required this.supplier});
  final SupplierModel supplier;

  @override
  ConsumerState<SupplierSalesAnalyticsScreen> createState() =>
      _SupplierSalesAnalyticsScreenState();
}

class _SupplierSalesAnalyticsScreenState
    extends ConsumerState<SupplierSalesAnalyticsScreen> {
  static const _pageSize = 50;
  final _searchController = TextEditingController();
  Timer? _debounce;
  SupplierAnalyticsPeriod _period = SupplierAnalyticsPeriod.thirtyDays;
  SupplierProfitFilter _filter = SupplierProfitFilter.all;
  SupplierAnalyticsSort _sort = SupplierAnalyticsSort.revenue;
  String _search = '';
  int _offset = 0;

  SupplierSummaryRequest get _summaryRequest => (
    supplier: widget.supplier,
    period: _period,
  );
  SupplierProductPageRequest get _pageRequest => (
    supplier: widget.supplier,
    period: _period,
    search: _search,
    filter: _filter,
    sort: _sort,
    limit: _pageSize,
    offset: _offset,
  );

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearch(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      setState(() {
        _search = value.trim();
        _offset = 0;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final summary = ref.watch(supplierSalesSummaryProvider(_summaryRequest));
    final page = ref.watch(supplierProductSalesPageProvider(_pageRequest));
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.supplier.name),
            const Text(
              'Sales analytics',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w400),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: () {
              ref.invalidate(supplierSalesSummaryProvider(_summaryRequest));
              ref.invalidate(supplierProductSalesPageProvider(_pageRequest));
            },
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(supplierSalesSummaryProvider(_summaryRequest));
          ref.invalidate(supplierProductSalesPageProvider(_pageRequest));
          await ref.read(supplierSalesSummaryProvider(_summaryRequest).future);
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            _PeriodSelector(
              value: _period,
              onChanged:
                  (value) => setState(() {
                    _period = value;
                    _offset = 0;
                  }),
            ),
            const SizedBox(height: 16),
            summary.when(
              loading: () => const _LoadingBox(height: 145),
              error:
                  (error, _) => _ErrorBox(
                    message: 'Summary load nahi ho saki.',
                    onRetry:
                        () => ref.invalidate(
                          supplierSalesSummaryProvider(_summaryRequest),
                        ),
                  ),
              data: (data) => _SummarySection(data: data),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _searchController,
              onChanged: _onSearch,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search_rounded),
                hintText: 'Search product, SKU or barcode',
                filled: true,
                fillColor: AppColors.surface,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 10,
              children: [
                _Dropdown<SupplierProfitFilter>(
                  label: 'Show',
                  value: _filter,
                  values: SupplierProfitFilter.values,
                  text: (value) => value.label,
                  onChanged:
                      (value) => setState(() {
                        _filter = value;
                        _offset = 0;
                      }),
                ),
                _Dropdown<SupplierAnalyticsSort>(
                  label: 'Sort by',
                  value: _sort,
                  values: SupplierAnalyticsSort.values,
                  text: (value) => value.label,
                  onChanged:
                      (value) => setState(() {
                        _sort = value;
                        _offset = 0;
                      }),
                ),
              ],
            ),
            const SizedBox(height: 16),
            page.when(
              loading: () => const _LoadingBox(height: 260),
              error:
                  (error, _) => _ErrorBox(
                    message: 'Products analytics load nahi ho saki.',
                    onRetry:
                        () => ref.invalidate(
                          supplierProductSalesPageProvider(_pageRequest),
                        ),
                  ),
              data:
                  (data) => _ProductsSection(
                    page: data,
                    offset: _offset,
                    pageSize: _pageSize,
                    onPrevious:
                        _offset == 0
                            ? null
                            : () => setState(() {
                              _offset = (_offset - _pageSize).clamp(
                                0,
                                data.total,
                              );
                            }),
                    onNext:
                        _offset + data.items.length >= data.total
                            ? null
                            : () => setState(() => _offset += _pageSize),
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PeriodSelector extends StatelessWidget {
  const _PeriodSelector({required this.value, required this.onChanged});
  final SupplierAnalyticsPeriod value;
  final ValueChanged<SupplierAnalyticsPeriod> onChanged;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children:
        SupplierAnalyticsPeriod.values
            .map(
              (period) => ChoiceChip(
                label: Text(period.label),
                selected: period == value,
                onSelected: (_) => onChanged(period),
              ),
            )
            .toList(),
  );
}

class _SummarySection extends StatelessWidget {
  const _SummarySection({required this.data});
  final SupplierSalesSummary data;

  @override
  Widget build(BuildContext context) {
    final metrics = [
      (
        'Linked products',
        '${data.linkedProductCount}',
        Icons.inventory_2_outlined,
      ),
      ('Units sold', '${data.unitsSold}', Icons.shopping_bag_outlined),
      ('Revenue', _money(data.revenue), Icons.trending_up_rounded),
      ('Sale cost', _money(data.costOfSales), Icons.payments_outlined),
      ('Gross profit', _money(data.grossProfit), Icons.show_chart_rounded),
      (
        'Margin',
        '${data.profitMargin.toStringAsFixed(1)}%',
        Icons.percent_rounded,
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final columns =
                constraints.maxWidth >= 900
                    ? 3
                    : constraints.maxWidth >= 520
                    ? 2
                    : 1;
            final width = (constraints.maxWidth - (columns - 1) * 12) / columns;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children:
                  metrics
                      .map(
                        (item) => SizedBox(
                          width: width,
                          child: _MetricCard(
                            label: item.$1,
                            value: item.$2,
                            icon: item.$3,
                            negative:
                                item.$1 == 'Gross profit' &&
                                data.grossProfit < 0,
                          ),
                        ),
                      )
                      .toList(),
            );
          },
        ),
        if (data.sharedProductCount > 0) ...[
          const SizedBox(height: 12),
          _Notice(
            text:
                '${data.sharedProductCount} shared product(s) ki sales totals mein include nahi ki gayin, kyun ke unka supplier safely determine nahi hota.',
          ),
        ],
        const SizedBox(height: 8),
        Text(
          '${data.salesCount} completed sales • approved returns deducted',
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
        ),
      ],
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.value,
    required this.icon,
    this.negative = false,
  });
  final String label;
  final String value;
  final IconData icon;
  final bool negative;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: AppColors.border),
    ),
    child: Row(
      children: [
        Icon(icon, color: negative ? AppColors.error : AppColors.primary),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                value,
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  color: negative ? AppColors.error : AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _Notice extends StatelessWidget {
  const _Notice({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: AppColors.secondaryLight.withValues(alpha: .25),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(
          Icons.info_outline_rounded,
          size: 20,
          color: AppColors.secondaryDark,
        ),
        const SizedBox(width: 9),
        Expanded(child: Text(text)),
      ],
    ),
  );
}

class _ProductsSection extends StatelessWidget {
  const _ProductsSection({
    required this.page,
    required this.offset,
    required this.pageSize,
    required this.onPrevious,
    required this.onNext,
  });
  final SupplierProductSalesPage page;
  final int offset;
  final int pageSize;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    if (page.items.isEmpty) return const _EmptyBox();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Product performance',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 10),
        ...page.items.map(
          (item) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _ProductCard(item: item),
          ),
        ),
        Row(
          children: [
            OutlinedButton.icon(
              onPressed: onPrevious,
              icon: const Icon(Icons.chevron_left),
              label: const Text('Previous'),
            ),
            Expanded(
              child: Text(
                '${offset + 1}–${offset + page.items.length} of ${page.total}',
                textAlign: TextAlign.center,
              ),
            ),
            OutlinedButton.icon(
              onPressed: onNext,
              icon: const Icon(Icons.chevron_right),
              label: const Text('Next'),
            ),
          ],
        ),
      ],
    );
  }
}

class _ProductCard extends StatelessWidget {
  const _ProductCard({required this.item});
  final SupplierProductSalesRow item;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: AppColors.border),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    item.sku?.isNotEmpty == true ? item.sku! : 'No SKU',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            if (item.isShared)
              const Chip(label: Text('Shared • excluded'))
            else
              Chip(label: Text('Stock ${item.stock}')),
          ],
        ),
        const Divider(height: 20),
        Wrap(
          spacing: 24,
          runSpacing: 10,
          children: [
            _Value(label: 'Sold', value: '${item.unitsSold} units'),
            _Value(label: 'Revenue', value: _money(item.revenue)),
            _Value(label: 'Sale cost', value: _money(item.costOfSales)),
            _Value(
              label: item.grossProfit < 0 ? 'Loss' : 'Gross profit',
              value: _money(item.grossProfit),
              negative: item.grossProfit < 0,
            ),
            _Value(
              label: 'Margin',
              value: '${item.profitMargin.toStringAsFixed(1)}%',
            ),
          ],
        ),
      ],
    ),
  );
}

class _Value extends StatelessWidget {
  const _Value({
    required this.label,
    required this.value,
    this.negative = false,
  });
  final String label;
  final String value;
  final bool negative;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
      ),
      Text(
        value,
        style: TextStyle(
          fontWeight: FontWeight.w700,
          color: negative ? AppColors.error : AppColors.textPrimary,
        ),
      ),
    ],
  );
}

class _Dropdown<T> extends StatelessWidget {
  const _Dropdown({
    required this.label,
    required this.value,
    required this.values,
    required this.text,
    required this.onChanged,
  });
  final String label;
  final T value;
  final List<T> values;
  final String Function(T) text;
  final ValueChanged<T> onChanged;
  @override
  Widget build(BuildContext context) => DropdownButton<T>(
    value: value,
    underline: const SizedBox.shrink(),
    borderRadius: BorderRadius.circular(12),
    items:
        values
            .map(
              (item) => DropdownMenuItem(
                value: item,
                child: Text('$label: ${text(item)}'),
              ),
            )
            .toList(),
    onChanged: (item) {
      if (item != null) onChanged(item);
    },
  );
}

class _LoadingBox extends StatelessWidget {
  const _LoadingBox({required this.height});
  final double height;
  @override
  Widget build(BuildContext context) => SizedBox(
    height: height,
    child: const Center(child: CircularProgressIndicator()),
  );
}

class _ErrorBox extends StatelessWidget {
  const _ErrorBox({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      children: [
        Text(message),
        TextButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh),
          label: const Text('Retry'),
        ),
      ],
    ),
  );
}

class _EmptyBox extends StatelessWidget {
  const _EmptyBox();
  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(vertical: 48),
    child: Column(
      children: [
        Icon(Icons.query_stats_rounded, size: 42, color: AppColors.textHint),
        SizedBox(height: 10),
        Text('No matching supplier products'),
      ],
    ),
  );
}

String _money(num value) => 'Rs ${value.toStringAsFixed(0)}';
