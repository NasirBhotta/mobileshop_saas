import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_colors.dart';
import '../../data/models/sale_model.dart';
import '../../data/services/receipt_service.dart';
import '../../../../core/entitlements/entitlement_provider.dart';
import '../providers/pos_provider.dart';

class ReceiptReprintScreen extends ConsumerStatefulWidget {
  const ReceiptReprintScreen({super.key});

  @override
  ConsumerState<ReceiptReprintScreen> createState() =>
      _ReceiptReprintScreenState();
}

class _ReceiptReprintScreenState extends ConsumerState<ReceiptReprintScreen> {
  static const _pageSize = 10;

  final _invoiceController = TextEditingController();
  SaleModel? _sale;
  bool _isSearching = false;
  int _page = 0;

  @override
  void dispose() {
    _invoiceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final footer = ref
        .watch(receiptFooterProvider)
        .maybeWhen(data: (value) => value, orElse: () => null);
    final sales = ref.watch(salesHistoryProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Reprint Receipt'),
        backgroundColor: AppColors.surface,
        elevation: 0,
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(salesHistoryProvider),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildSearchBar(),
            const SizedBox(height: 16),
            if (_sale != null) _ReceiptPreview(sale: _sale!, footer: footer),
            if (_sale != null) const SizedBox(height: 20),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Recent Receipts',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => ref.invalidate(salesHistoryProvider),
                  icon: const Icon(Icons.refresh_rounded),
                  tooltip: 'Refresh',
                ),
              ],
            ),
            const SizedBox(height: 8),
            sales.when(
              loading:
                  () => const Padding(
                    padding: EdgeInsets.symmetric(vertical: 40),
                    child: Center(child: CircularProgressIndicator()),
                  ),
              error:
                  (error, _) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 40),
                    child: Text(
                      error.toString(),
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppColors.error),
                    ),
                  ),
              data: _buildRecentReceipts,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _invoiceController,
            decoration: const InputDecoration(
              labelText: 'Invoice ID',
              hintText: 'Paste full or starting invoice ID',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.receipt_long_rounded),
            ),
            onSubmitted: (_) => _search(),
          ),
        ),
        const SizedBox(width: 10),
        FilledButton.icon(
          onPressed: _isSearching ? null : _search,
          icon:
              _isSearching
                  ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                  : const Icon(Icons.search_rounded),
          label: const Text('Search'),
        ),
      ],
    );
  }

  Widget _buildRecentReceipts(List<SaleModel> sales) {
    if (sales.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(
          child: Text(
            'Recent receipts abhi available nahi hain',
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ),
      );
    }

    final pageCount = (sales.length / _pageSize).ceil();
    final safePage = _page.clamp(0, pageCount - 1).toInt();
    final start = safePage * _pageSize;
    final pageItems = sales.skip(start).take(_pageSize).toList();

    return Column(
      children: [
        ...pageItems.map(
          (sale) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _ReceiptListTile(
              sale: sale,
              selected: sale.id == _sale?.id,
              onTap: () => setState(() => _sale = sale),
            ),
          ),
        ),
        if (pageCount > 1) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed:
                    safePage == 0
                        ? null
                        : () => setState(() => _page = safePage - 1),
                icon: const Icon(Icons.chevron_left_rounded),
                label: const Text('Prev'),
              ),
              Expanded(
                child: Text(
                  'Page ${safePage + 1} of $pageCount',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              OutlinedButton.icon(
                onPressed:
                    safePage >= pageCount - 1
                        ? null
                        : () => setState(() => _page = safePage + 1),
                icon: const Icon(Icons.chevron_right_rounded),
                label: const Text('Next'),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Future<void> _search() async {
    setState(() => _isSearching = true);
    try {
      final sale = await ref
          .read(posRepositoryProvider)
          .findSaleForReturn(_invoiceController.text);
      if (!mounted) return;
      setState(() => _sale = sale);
      if (sale == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Invoice nahi mila'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSearching = false);
    }
  }
}

class _ReceiptListTile extends StatelessWidget {
  final SaleModel sale;
  final bool selected;
  final VoidCallback onTap;

  const _ReceiptListTile({
    required this.sale,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final createdAt = sale.createdAt?.toLocal().toString().split('.').first;
    return Material(
      color:
          selected
              ? AppColors.primary.withValues(alpha: 0.08)
              : AppColors.surface,
      borderRadius: BorderRadius.circular(8),
      child: ListTile(
        onTap: onTap,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(
            color: selected ? AppColors.primary : AppColors.border,
          ),
        ),
        leading: CircleAvatar(
          backgroundColor: AppColors.primary.withValues(alpha: 0.1),
          child: const Icon(
            Icons.receipt_long_rounded,
            color: AppColors.primary,
          ),
        ),
        title: Text(
          'Invoice ${sale.id ?? ''}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          [
            if (createdAt != null) createdAt,
            if (sale.customerName != null) sale.customerName,
            '${sale.items.length} items',
          ].join(' - '),
        ),
        trailing: Text(
          'Rs ${sale.total.toStringAsFixed(0)}',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}

class _ReceiptPreview extends ConsumerWidget {
  final SaleModel sale;
  final String? footer;

  const _ReceiptPreview({required this.sale, required this.footer});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            ReceiptService.formatReceipt(
              sale: sale,
              footer: footer,
              duplicate: true,
            ),
            style: const TextStyle(fontFamily: 'monospace'),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 10,
            children: [
              for (final method in ReceiptDeliveryMethod.values)
                OutlinedButton.icon(
                  onPressed:
                      () => ReceiptService.deliver(
                        sale: sale,
                        method: method,
                        footer: footer,
                        duplicate: true,
                        entitlementEvaluator: ref.read(
                          entitlementEvaluatorProvider,
                        ),
                      ),
                  icon: Icon(_iconFor(method)),
                  label: Text(method.label),
                ),
            ],
          ),
        ],
      ),
    );
  }

  IconData _iconFor(ReceiptDeliveryMethod method) {
    switch (method) {
      case ReceiptDeliveryMethod.thermalPrint:
        return Icons.print_rounded;
      case ReceiptDeliveryMethod.whatsapp:
        return Icons.chat_rounded;
      case ReceiptDeliveryMethod.email:
        return Icons.email_rounded;
    }
  }
}
