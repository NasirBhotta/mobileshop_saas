import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_colors.dart';
import '../../data/models/sale_return_model.dart';
import '../providers/pos_provider.dart';

class ReturnScreen extends ConsumerStatefulWidget {
  const ReturnScreen({super.key});

  @override
  ConsumerState<ReturnScreen> createState() => _ReturnScreenState();
}

class _ReturnScreenState extends ConsumerState<ReturnScreen> {
  final _invoiceController = TextEditingController();
  final _overrideReasonController = TextEditingController();
  bool _isSearching = false;

  @override
  void dispose() {
    _invoiceController.dispose();
    _overrideReasonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(returnDraftProvider);
    final controller = ref.watch(returnControllerProvider);
    final sale = draft.sale;

    ref.listen(returnControllerProvider, (previous, next) {
      next.whenOrNull(
        data: (result) {
          if (result == null || !mounted) return;
          final isPending = result.status == SaleReturnStatus.pendingApproval;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                isPending
                    ? 'Return approval ke liye pending hai'
                    : 'Return processed. Refund Rs ${result.refundAmount.toStringAsFixed(0)}',
              ),
              backgroundColor:
                  isPending ? AppColors.warning : AppColors.success,
            ),
          );
        },
        error: (error, _) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(error.toString()),
              backgroundColor: AppColors.error,
            ),
          );
        },
      );
    });

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Return / Refund'),
        backgroundColor: AppColors.surface,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _invoiceController,
                  decoration: const InputDecoration(
                    labelText: 'Original invoice ID',
                    hintText: 'Invoice ID ya first 8 chars',
                    border: OutlineInputBorder(),
                  ),
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _searchInvoice(),
                ),
              ),
              const SizedBox(width: 10),
              FilledButton.icon(
                onPressed: _isSearching ? null : _searchInvoice,
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
          ),
          const SizedBox(height: 16),
          if (sale == null)
            const _EmptyReturnState()
          else ...[
            _SaleSummary(draft: draft),
            const SizedBox(height: 16),
            ...sale.items.map((item) {
              final returned =
                  draft.alreadyReturnedByProductId[item.productId] ?? 0;
              final available = item.quantity - returned;
              final selected = draft.quantitiesByProductId[item.productId] ?? 0;
              return _ReturnItemTile(
                name: item.productName,
                sold: item.quantity,
                returned: returned,
                available: available,
                selected: selected,
                onChanged:
                    (value) => ref
                        .read(returnDraftProvider.notifier)
                        .setQuantity(item.productId, value),
              );
            }),
            const SizedBox(height: 16),
            SegmentedButton<RefundMethod>(
              segments: const [
                ButtonSegment(
                  value: RefundMethod.cash,
                  icon: Icon(Icons.payments_rounded),
                  label: Text('Cash'),
                ),
                ButtonSegment(
                  value: RefundMethod.credit,
                  icon: Icon(Icons.account_balance_wallet_rounded),
                  label: Text('Credit'),
                ),
              ],
              selected: {draft.refundMethod},
              onSelectionChanged:
                  (values) => ref
                      .read(returnDraftProvider.notifier)
                      .setRefundMethod(values.first),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _overrideReasonController,
              decoration: const InputDecoration(
                labelText: 'Owner override reason (if needed)',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed:
                  controller.isLoading
                      ? null
                      : () => ref
                          .read(returnControllerProvider.notifier)
                          .submit(
                            overrideReason:
                                _overrideReasonController.text.trim(),
                          ),
              icon:
                  controller.isLoading
                      ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                      : const Icon(Icons.assignment_return_rounded),
              label: Text(
                'Process Refund Rs ${draft.refundAmount.toStringAsFixed(0)}',
              ),
            ),
          ],
          const SizedBox(height: 24),
          _PendingReturnsPanel(isBusy: controller.isLoading),
        ],
      ),
    );
  }

  Future<void> _searchInvoice() async {
    setState(() => _isSearching = true);
    try {
      final sale = await ref
          .read(returnDraftProvider.notifier)
          .searchInvoice(_invoiceController.text);
      if (sale == null && mounted) {
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

class _PendingReturnsPanel extends ConsumerWidget {
  final bool isBusy;

  const _PendingReturnsPanel({required this.isBusy});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pendingReturns = ref.watch(pendingReturnsProvider);

    return pendingReturns.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => const SizedBox.shrink(),
      data: (returns) {
        if (returns.isEmpty) return const SizedBox.shrink();

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
              const Text(
                'Pending approvals',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              ...returns.map(
                (saleReturn) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    'Invoice #${saleReturn.originalSaleId.substring(0, 8).toUpperCase()}',
                  ),
                  subtitle: Text(
                    saleReturn.approvalRequiredReason ??
                        'Manager/Owner approval required',
                  ),
                  trailing: FilledButton(
                    onPressed:
                        isBusy
                            ? null
                            : () => ref
                                .read(returnControllerProvider.notifier)
                                .approve(saleReturn),
                    child: Text(
                      'Approve Rs ${saleReturn.refundAmount.toStringAsFixed(0)}',
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _EmptyReturnState extends StatelessWidget {
  const _EmptyReturnState();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: const Column(
        children: [
          Icon(Icons.receipt_long_rounded, size: 48, color: AppColors.textHint),
          SizedBox(height: 12),
          Text(
            'Original invoice search karein',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          SizedBox(height: 4),
          Text(
            'Return sirf original sale items ke against process hogi.',
            style: TextStyle(color: AppColors.textSecondary),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _SaleSummary extends StatelessWidget {
  final ReturnDraftState draft;

  const _SaleSummary({required this.draft});

  @override
  Widget build(BuildContext context) {
    final sale = draft.sale!;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Invoice #${sale.id?.substring(0, 8).toUpperCase()}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                if (sale.createdAt != null)
                  Text(
                    sale.createdAt!.toLocal().toString().split('.').first,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
              ],
            ),
          ),
          Text(
            'Rs ${draft.refundAmount.toStringAsFixed(0)}',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.success,
            ),
          ),
        ],
      ),
    );
  }
}

class _ReturnItemTile extends StatelessWidget {
  final String name;
  final int sold;
  final int returned;
  final int available;
  final int selected;
  final ValueChanged<int> onChanged;

  const _ReturnItemTile({
    required this.name,
    required this.sold,
    required this.returned,
    required this.available,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  'Sold $sold · Returned $returned · Available $available',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: selected <= 0 ? null : () => onChanged(selected - 1),
            icon: const Icon(Icons.remove_rounded),
          ),
          SizedBox(
            width: 36,
            child: Text(
              '$selected',
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          IconButton(
            onPressed:
                selected >= available ? null : () => onChanged(selected + 1),
            icon: const Icon(Icons.add_rounded),
          ),
        ],
      ),
    );
  }
}
