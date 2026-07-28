import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_colors.dart';
import '../../data/models/procurement_models.dart';
import '../providers/procurement_provider.dart';

Future<void> showSupplierHistoryDialog(
  BuildContext context,
  SupplierModel supplier,
) {
  return showDialog<void>(
    context: context,
    builder:
        (_) => Dialog(
          insetPadding: const EdgeInsets.all(16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900, maxHeight: 720),
            child: SupplierHistoryDialog(supplier: supplier),
          ),
        ),
  );
}

class SupplierHistoryDialog extends ConsumerStatefulWidget {
  final SupplierModel supplier;

  const SupplierHistoryDialog({super.key, required this.supplier});

  @override
  ConsumerState<SupplierHistoryDialog> createState() =>
      _SupplierHistoryDialogState();
}

class _SupplierHistoryDialogState extends ConsumerState<SupplierHistoryDialog> {
  int? _days = 30;

  @override
  Widget build(BuildContext context) {
    final overview = ref.watch(supplierOverviewProvider(widget.supplier));
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.supplier.name,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Text(
                      'Supplier account & purchase history',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Close',
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: overview.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error:
                (error, _) => _HistoryError(
                  error: error,
                  onRetry:
                      () => ref.invalidate(
                        supplierOverviewProvider(widget.supplier),
                      ),
                ),
            data: (data) {
              final cutoff =
                  _days == null
                      ? null
                      : DateTime.now().subtract(Duration(days: _days!));
              final entries =
                  data.ledgerEntries
                      .where(
                        (entry) =>
                            cutoff == null ||
                            !entry.occurredAt.isBefore(cutoff),
                      )
                      .toList();
              final orders =
                  data.purchaseOrders
                      .where(
                        (order) =>
                            cutoff == null ||
                            order.createdAt == null ||
                            !order.createdAt!.isBefore(cutoff),
                      )
                      .toList();
              return DefaultTabController(
                length: 3,
                child: Column(
                  children: [
                    _Summary(data: data),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          const Expanded(
                            child: TabBar(
                              isScrollable: true,
                              tabs: [
                                Tab(text: 'Statement'),
                                Tab(text: 'Orders'),
                                Tab(text: 'Details'),
                              ],
                            ),
                          ),
                          DropdownButton<int?>(
                            value: _days,
                            underline: const SizedBox.shrink(),
                            items: const [
                              DropdownMenuItem(
                                value: 30,
                                child: Text('30 days'),
                              ),
                              DropdownMenuItem(
                                value: 90,
                                child: Text('90 days'),
                              ),
                              DropdownMenuItem(
                                value: null,
                                child: Text('All time'),
                              ),
                            ],
                            onChanged: (value) => setState(() => _days = value),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: TabBarView(
                        children: [
                          _Statement(entries: entries),
                          _Orders(orders: orders),
                          _Details(data: data),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _Summary extends StatelessWidget {
  final SupplierOverviewModel data;

  const _Summary({required this.data});

  @override
  Widget build(BuildContext context) {
    final items = [
      ('Ordered', data.totalOrdered, Icons.shopping_cart_outlined),
      ('Received', data.totalReceived, Icons.inventory_2_outlined),
      ('Paid', data.totalPaid, Icons.payments_outlined),
      (
        'Payable now',
        data.supplier.outstandingBalance,
        Icons.account_balance_wallet_outlined,
      ),
      ('Stock pending', data.pendingOrderValue, Icons.pending_actions_outlined),
    ];
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final item in items)
            SizedBox(
              width: 150,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(item.$3, size: 18),
                      const SizedBox(height: 8),
                      Text(
                        item.$1,
                        style: const TextStyle(color: AppColors.textSecondary),
                      ),
                      Text(
                        _money(item.$2),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Statement extends StatelessWidget {
  final List<SupplierLedgerEntryModel> entries;

  const _Statement({required this.entries});

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return const _EmptyHistory(
        message: 'No receipt or payment in this period.',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: entries.length,
      separatorBuilder: (_, _) => const Divider(),
      itemBuilder: (_, index) {
        final entry = entries[index];
        final isReceipt = entry.direction == SupplierLedgerDirection.increase;
        return ListTile(
          contentPadding: EdgeInsets.zero,
          leading: CircleAvatar(
            child: Icon(
              isReceipt ? Icons.inventory_2_outlined : Icons.payments_outlined,
            ),
          ),
          title: Text(
            entry.description ??
                (isReceipt ? 'Goods received' : 'Supplier payment'),
          ),
          subtitle: Text('${_date(entry.occurredAt)} • ${entry.referenceType}'),
          trailing: Text(
            '${isReceipt ? '+' : '-'}${_money(entry.amount)}',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: isReceipt ? AppColors.error : AppColors.success,
            ),
          ),
        );
      },
    );
  }
}

class _Orders extends StatelessWidget {
  final List<PurchaseOrderModel> orders;

  const _Orders({required this.orders});

  @override
  Widget build(BuildContext context) {
    if (orders.isEmpty) {
      return const _EmptyHistory(message: 'No purchase orders in this period.');
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: orders.length,
      separatorBuilder: (_, _) => const Divider(),
      itemBuilder: (_, index) {
        final order = orders[index];
        final pending = (order.totalExpectedCost - order.totalReceivedCost)
            .clamp(0, double.infinity);
        return ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(order.poNo),
          subtitle: Text(
            '${_date(order.createdAt)} • ${order.status.label} • '
            '${order.items.length} item(s)',
          ),
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(_money(order.totalExpectedCost)),
              Text(
                'Pending ${_money(pending)}',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Details extends StatelessWidget {
  final SupplierOverviewModel data;

  const _Details({required this.data});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _detail('Open orders', '${data.openOrderCount}'),
        _detail('First dealing', _date(data.firstActivityAt)),
        _detail('Last dealing', _date(data.lastActivityAt)),
        _detail('Current payable', _money(data.supplier.outstandingBalance)),
        _detail('Recorded statement balance', _money(data.statementBalance)),
        if (data.hasStatementMismatch)
          const Card(
            color: Color(0xfffff3cd),
            child: Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                'Old payable and recorded statement do not match. Current payable '
                'is kept as the working balance; reconcile legacy opening balance '
                'before relying on the statement total.',
              ),
            ),
          ),
      ],
    );
  }

  Widget _detail(String label, String value) => ListTile(
    contentPadding: EdgeInsets.zero,
    title: Text(label),
    trailing: Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
  );
}

class _HistoryError extends StatelessWidget {
  final Object error;
  final VoidCallback onRetry;

  const _HistoryError({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(error.toString(), textAlign: TextAlign.center),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Retry'),
          ),
        ],
      ),
    ),
  );
}

class _EmptyHistory extends StatelessWidget {
  final String message;

  const _EmptyHistory({required this.message});

  @override
  Widget build(BuildContext context) => Center(
    child: Text(
      message,
      style: const TextStyle(color: AppColors.textSecondary),
    ),
  );
}

String _money(num value) => 'Rs ${value.toStringAsFixed(0)}';

String _date(DateTime? value) {
  if (value == null) return '—';
  final local = value.toLocal();
  return '${local.day.toString().padLeft(2, '0')}/'
      '${local.month.toString().padLeft(2, '0')}/${local.year}';
}
