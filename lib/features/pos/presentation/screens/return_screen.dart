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
  final _refundController = TextEditingController();
  final _overrideReasonController = TextEditingController();
  final _refundFocusNode = FocusNode();
  bool _isSearching = false;

  @override
  void dispose() {
    _invoiceController.dispose();
    _refundController.dispose();
    _overrideReasonController.dispose();
    _refundFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(returnDraftProvider);
    final controller = ref.watch(returnControllerProvider);
    final sale = draft.sale;
    _syncRefundController(draft);

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
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 760;
          final content = ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _InvoiceSearchBar(
                controller: _invoiceController,
                isSearching: _isSearching,
                isWide: isWide,
                onSearch: _searchInvoice,
              ),
              const SizedBox(height: 16),
              if (sale == null)
                const _EmptyReturnState()
              else ...[
                _SaleSummary(draft: draft),
                const SizedBox(height: 16),
                if (isWide)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: _ReturnItemsList(draft: draft)),
                      const SizedBox(width: 16),
                      SizedBox(
                        width: 340,
                        child: _RefundDecisionPanel(
                          draft: draft,
                          controller: controller,
                          refundController: _refundController,
                          refundFocusNode: _refundFocusNode,
                          overrideReasonController: _overrideReasonController,
                          onRefundChanged: _setRefundAmount,
                        ),
                      ),
                    ],
                  )
                else ...[
                  _ReturnItemsList(draft: draft),
                  const SizedBox(height: 16),
                  _RefundDecisionPanel(
                    draft: draft,
                    controller: controller,
                    refundController: _refundController,
                    refundFocusNode: _refundFocusNode,
                    overrideReasonController: _overrideReasonController,
                    onRefundChanged: _setRefundAmount,
                  ),
                ],
              ],
              const SizedBox(height: 24),
              _PendingReturnsPanel(isBusy: controller.isLoading),
            ],
          );

          return Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1180),
              child: content,
            ),
          );
        },
      ),
    );
  }

  void _syncRefundController(ReturnDraftState draft) {
    if (_refundFocusNode.hasFocus) return;

    final value = draft.refundAmount.toStringAsFixed(0);
    if (_refundController.text == value) return;

    _refundController.text = value;
  }

  void _setRefundAmount(String value) {
    final normalized = value.replaceAll(',', '').trim();
    final amount = double.tryParse(normalized) ?? 0;
    ref.read(returnDraftProvider.notifier).setRefundAmount(amount);
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

class _InvoiceSearchBar extends StatelessWidget {
  final TextEditingController controller;
  final bool isSearching;
  final bool isWide;
  final VoidCallback onSearch;

  const _InvoiceSearchBar({
    required this.controller,
    required this.isSearching,
    required this.isWide,
    required this.onSearch,
  });

  @override
  Widget build(BuildContext context) {
    final searchField = TextField(
      controller: controller,
      decoration: const InputDecoration(
        labelText: 'Original invoice ID',
        hintText: 'Invoice ID ya first 8 chars',
        border: OutlineInputBorder(),
        prefixIcon: Icon(Icons.receipt_long_rounded),
      ),
      textInputAction: TextInputAction.search,
      onSubmitted: (_) => onSearch(),
    );
    final button = FilledButton.icon(
      onPressed: isSearching ? null : onSearch,
      icon:
          isSearching
              ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
              : const Icon(Icons.search_rounded),
      label: const Text('Search'),
    );

    if (isWide) {
      return Row(
        children: [
          Expanded(child: searchField),
          const SizedBox(width: 10),
          SizedBox(height: 48, child: button),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        searchField,
        const SizedBox(height: 10),
        SizedBox(height: 48, child: button),
      ],
    );
  }
}

class _ReturnItemsList extends ConsumerWidget {
  final ReturnDraftState draft;

  const _ReturnItemsList({required this.draft});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sale = draft.sale;
    if (sale == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Returned items',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 10),
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
      ],
    );
  }
}

class _RefundDecisionPanel extends ConsumerWidget {
  final ReturnDraftState draft;
  final AsyncValue<SaleReturnModel?> controller;
  final TextEditingController refundController;
  final FocusNode refundFocusNode;
  final TextEditingController overrideReasonController;
  final ValueChanged<String> onRefundChanged;

  const _RefundDecisionPanel({
    required this.draft,
    required this.controller,
    required this.refundController,
    required this.refundFocusNode,
    required this.overrideReasonController,
    required this.onRefundChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final maxRefund = draft.maxRefundAmount;
    final actualRefund = draft.refundAmount;
    final hasReturnItems = maxRefund > 0;
    final saleId = draft.sale?.id;
    final refundPreview =
        draft.refundMethod == RefundMethod.cash &&
                actualRefund > 0 &&
                saleId != null
            ? ref.watch(
              returnRefundPreviewProvider((
                saleId: saleId,
                refundAmount: actualRefund,
              )),
            )
            : null;
    final creditCapacity =
        draft.refundMethod == RefundMethod.credit &&
                actualRefund > 0 &&
                saleId != null
            ? ref.watch(returnCreditCapacityProvider(saleId))
            : null;
    final hasRefundDestination =
        actualRefund <= 0 ||
        (draft.refundMethod == RefundMethod.cash
            ? (refundPreview?.value?.isNotEmpty ?? false)
            : (creditCapacity?.value ?? 0) + 0.01 >= actualRefund);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Refund decision',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          _RefundAmountRow(
            label: 'Max refundable',
            value: 'Rs ${maxRefund.toStringAsFixed(0)}',
            color: AppColors.textPrimary,
          ),
          const SizedBox(height: 8),
          _RefundAmountRow(
            label: 'Actual refund',
            value: 'Rs ${actualRefund.toStringAsFixed(0)}',
            color: AppColors.success,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: refundController,
            focusNode: refundFocusNode,
            enabled: hasReturnItems && !controller.isLoading,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Refund amount shopkeeper will pay',
              helperText:
                  '0 se Rs ${maxRefund.toStringAsFixed(0)} tak amount set karein',
              border: const OutlineInputBorder(),
              prefixText: 'Rs ',
            ),
            onChanged: onRefundChanged,
          ),
          if (draft.refundAmountInput > maxRefund) ...[
            const SizedBox(height: 8),
            const Text(
              'Entered amount max refundable se zyada hai, submit par max amount use hogi.',
              style: TextStyle(fontSize: 12, color: AppColors.warning),
            ),
          ],
          const SizedBox(height: 14),
          SegmentedButton<RefundMethod>(
            segments: const [
              ButtonSegment(
                value: RefundMethod.cash,
                icon: Icon(Icons.payments_rounded),
                label: Text('Original account'),
              ),
              ButtonSegment(
                value: RefundMethod.credit,
                icon: Icon(Icons.account_balance_wallet_rounded),
                label: Text('Adjust Khata'),
              ),
            ],
            selected: {draft.refundMethod},
            onSelectionChanged:
                controller.isLoading
                    ? null
                    : (values) => ref
                        .read(returnDraftProvider.notifier)
                        .setRefundMethod(values.first),
          ),
          if (actualRefund > 0) ...[
            const SizedBox(height: 12),
            _RefundDestinationCard(
              refundMethod: draft.refundMethod,
              refundAmount: actualRefund,
              preview: refundPreview,
              creditCapacity: creditCapacity,
            ),
          ],
          const SizedBox(height: 12),
          TextField(
            controller: overrideReasonController,
            enabled: !controller.isLoading,
            decoration: const InputDecoration(
              labelText: 'Owner override reason (if needed)',
              border: OutlineInputBorder(),
            ),
            maxLines: 2,
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed:
                controller.isLoading || !hasReturnItems || !hasRefundDestination
                    ? null
                    : () => ref
                        .read(returnControllerProvider.notifier)
                        .submit(
                          overrideReason: overrideReasonController.text.trim(),
                        ),
            icon:
                controller.isLoading
                    ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                    : const Icon(Icons.assignment_return_rounded),
            label: Text('Process Return Rs ${actualRefund.toStringAsFixed(0)}'),
          ),
        ],
      ),
    );
  }
}

class _RefundDestinationCard extends StatelessWidget {
  final RefundMethod refundMethod;
  final double refundAmount;
  final AsyncValue<List<SaleReturnRefundPreviewModel>>? preview;
  final AsyncValue<double>? creditCapacity;

  const _RefundDestinationCard({
    required this.refundMethod,
    required this.refundAmount,
    required this.preview,
    required this.creditCapacity,
  });

  @override
  Widget build(BuildContext context) {
    if (refundMethod == RefundMethod.credit) {
      return creditCapacity!.when(
        loading:
            () => const _ReturnFlowCard(
              icon: Icons.sync_rounded,
              title: 'Customer Khata check ho raha hai',
              message: 'Available credit return capacity load ho rahi hai...',
            ),
        error:
            (_, _) => const _ReturnFlowCard(
              icon: Icons.error_outline_rounded,
              title: 'Customer Khata unavailable',
              message: 'Invoice customer aur outstanding verify nahi ho saka.',
              color: AppColors.error,
            ),
        data: (capacity) {
          final allowed = capacity + 0.01 >= refundAmount;
          return _ReturnFlowCard(
            icon:
                allowed
                    ? Icons.person_remove_alt_1_rounded
                    : Icons.error_outline_rounded,
            title:
                allowed
                    ? 'Refund destination: Customer Khata'
                    : 'Khata refund available nahi',
            message:
                allowed
                    ? 'Cash kisi account se nahi niklega. Customer outstanding '
                        'se −Rs ${refundAmount.toStringAsFixed(0)} hoga.'
                    : 'Is invoice ki available Khata capacity '
                        'Rs ${capacity.toStringAsFixed(0)} hai.',
            color: allowed ? AppColors.primary : AppColors.error,
          );
        },
      );
    }

    return preview!.when(
      loading:
          () => const _ReturnFlowCard(
            icon: Icons.sync_rounded,
            title: 'Refund accounts check ho rahe hain',
            message: 'Original payment accounts load ho rahe hain...',
          ),
      error:
          (_, _) => const _ReturnFlowCard(
            icon: Icons.error_outline_rounded,
            title: 'Refund account unavailable',
            message:
                'Original payment account verify nahi hua. Return process na '
                'karein aur invoice payments check karein.',
            color: AppColors.error,
          ),
      data: (legs) {
        if (legs.isEmpty) {
          return const _ReturnFlowCard(
            icon: Icons.error_outline_rounded,
            title: 'Refund account nahi mila',
            message:
                'Is invoice mein refundable cash/wallet/card payment available '
                'nahi hai. Adjust Khata select karein ya invoice check karein.',
            color: AppColors.error,
          );
        }
        final details = legs
            .map(
              (leg) =>
                  '${leg.paymentMethod} • ${leg.accountName}: '
                  '−Rs ${leg.amount.toStringAsFixed(0)}',
            )
            .join('\n');
        return _ReturnFlowCard(
          icon: Icons.account_balance_wallet_rounded,
          title: 'Refund kis account se niklega',
          message: details,
        );
      },
    );
  }
}

class _ReturnFlowCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final Color color;

  const _ReturnFlowCard({
    required this.icon,
    required this.title,
    required this.message,
    this.color = AppColors.primary,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 3),
                Text(
                  message,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RefundAmountRow extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _RefundAmountRow({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(color: AppColors.textSecondary),
          ),
        ),
        Text(
          value,
          style: TextStyle(color: color, fontWeight: FontWeight.w900),
        ),
      ],
    );
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
                (saleReturn) =>
                    _PendingReturnTile(saleReturn: saleReturn, isBusy: isBusy),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _PendingReturnTile extends ConsumerWidget {
  final SaleReturnModel saleReturn;
  final bool isBusy;

  const _PendingReturnTile({required this.saleReturn, required this.isBusy});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final approveButton = FilledButton(
      onPressed:
          isBusy
              ? null
              : () => ref
                  .read(returnControllerProvider.notifier)
                  .approve(saleReturn),
      child: Text('Approve Rs ${saleReturn.refundAmount.toStringAsFixed(0)}'),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 560;
        final info = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Invoice #${_shortId(saleReturn.originalSaleId)}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 3),
            Text(
              saleReturn.approvalRequiredReason ??
                  'Manager/Owner approval required',
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ],
        );

        return Padding(
          padding: const EdgeInsets.only(top: 8),
          child:
              isNarrow
                  ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [info, const SizedBox(height: 8), approveButton],
                  )
                  : Row(
                    children: [
                      Expanded(child: info),
                      const SizedBox(width: 12),
                      approveButton,
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
                  'Invoice #${_shortId(sale.id)}',
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
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                'Rs ${draft.refundAmount.toStringAsFixed(0)}',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.success,
                ),
              ),
              Text(
                'Max Rs ${draft.maxRefundAmount.toStringAsFixed(0)}',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
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
                  'Sold $sold - Returned $returned - Available $available',
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

String _shortId(String? id) {
  final raw = id?.trim();
  if (raw == null || raw.isEmpty) return 'SALE';
  final short = raw.length <= 8 ? raw : raw.substring(0, 8);
  return short.toUpperCase();
}
