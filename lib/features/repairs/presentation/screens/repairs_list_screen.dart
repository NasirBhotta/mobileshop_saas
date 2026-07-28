import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/gestures.dart' show PointerScrollEvent;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobileshop_saas/core/extensions/repair_ticket_ext.dart';
import 'package:mobileshop_saas/core/utils/responsive.dart';
import 'package:mobileshop_saas/features/repairs/presentation/providers/repair_provider.dart';
import 'package:mobileshop_saas/features/accounts/data/models/account_models.dart';
import 'package:mobileshop_saas/features/accounts/presentation/providers/accounts_provider.dart';
import 'package:mobileshop_saas/features/pos/data/models/sale_payment_model.dart';
import 'package:mobileshop_saas/features/pos/domain/pos_payment_account_policy.dart';
import '../../data/models/repair_ticket_model.dart';
import '../widgets/repair_completion_dialog.dart';

class RepairsListScreen extends ConsumerWidget {
  const RepairsListScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ticketsAsync = ref.watch(repairTicketsProvider);
    final selectedStatus = ref.watch(selectedRepairStatusFilterProvider);
    final syncState = ref.watch(repairSyncControllerProvider);
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Repairs'),
        actions: [
          IconButton(
            tooltip: 'Sync',
            onPressed:
                syncState.isLoading
                    ? null
                    : () async {
                      await ref
                          .read(repairSyncControllerProvider.notifier)
                          .sync();
                    },
            icon:
                syncState.isLoading
                    ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                    : const Icon(Icons.sync),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/repairs/new'),
        icon: const Icon(Icons.add),
        label: const Text('New Repair'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            _RepairStatusFilterBar(
              selectedStatus: selectedStatus,
              onChanged: (status) {
                ref.read(selectedRepairStatusFilterProvider.notifier).state =
                    status;
              },
            ),
            const Divider(height: 1),
            Expanded(
              child: ticketsAsync.when(
                loading: () {
                  return const Center(child: CircularProgressIndicator());
                },
                error: (error, _) {
                  return _RepairErrorView(
                    message: error.toString(),
                    onRetry: () {
                      ref.invalidate(repairTicketsProvider);
                    },
                  );
                },
                data: (tickets) {
                  if (tickets.isEmpty) {
                    return RefreshIndicator(
                      onRefresh:
                          () =>
                              ref
                                  .read(repairSyncControllerProvider.notifier)
                                  .sync(),
                      child: LayoutBuilder(
                        builder:
                            (context, constraints) => ListView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              children: [
                                SizedBox(
                                  height: constraints.maxHeight,
                                  child: _EmptyRepairsView(
                                    selectedStatus: selectedStatus,
                                    onCreate:
                                        () => context.push('/repairs/new'),
                                  ),
                                ),
                              ],
                            ),
                      ),
                    );
                  }
                  return RefreshIndicator(
                    onRefresh:
                        () =>
                            ref
                                .read(repairSyncControllerProvider.notifier)
                                .sync(),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final isWide = constraints.maxWidth >= 850;
                        if (isWide) {
                          return GridView.builder(
                            padding: const EdgeInsets.all(16),
                            gridDelegate:
                                const SliverGridDelegateWithMaxCrossAxisExtent(
                                  maxCrossAxisExtent: 420,
                                  mainAxisSpacing: 12,
                                  crossAxisSpacing: 12,
                                  childAspectRatio: 1.65,
                                ),
                            itemCount: tickets.length,
                            itemBuilder: (context, index) {
                              final ticket = tickets[index];
                              return _RepairTicketCard(
                                ticket: ticket,
                                onTap: () {
                                  _showTicketDetails(context, ref, ticket);
                                },
                              );
                            },
                          );
                        }
                        return ListView.separated(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.all(12),
                          itemCount: tickets.length,
                          separatorBuilder: (_, _) {
                            return const SizedBox(height: 10);
                          },
                          itemBuilder: (context, index) {
                            final ticket = tickets[index];
                            return _RepairTicketCard(
                              ticket: ticket,
                              onTap: () {
                                _showTicketDetails(context, ref, ticket);
                              },
                            );
                          },
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

  static void _showTicketDetails(
    BuildContext context,
    WidgetRef ref,
    RepairTicketModel ticket,
  ) {
    final details = _RepairTicketDetails(
      ticket: ticket,
      onStatusChanged: ({required status, note, totalCost}) async {
        final controller = ref.read(repairTicketControllerProvider.notifier);
        final updatedTicket =
            status == RepairTicketStatus.cancelled
                ? await controller.cancelRepair(ticket)
                : await controller.updateStatus(
                  ticket: ticket,
                  status: status,
                  note: note,
                  totalCost: totalCost,
                );

        if (updatedTicket == null) {
          final state = ref.read(repairTicketControllerProvider);
          final error =
              state.asError?.error.toString() ?? 'Status update nahi ho saka';
          if (context.mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(error)));
          }
          return false;
        }

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Status ${status.label} ho gaya')),
          );
        }
        return true;
      },
    );

    if (Responsive.isDesktop(context)) {
      showDialog<void>(
        context: context,
        builder: (dialogContext) {
          return Dialog(
            insetPadding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: details,
            ),
          );
        },
      );
      return;
    }

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
          ),
          child: details,
        );
      },
    );
  }
}

typedef _StatusChanged =
    Future<bool> Function({
      required RepairTicketStatus status,
      String? note,
      double? totalCost,
    });

class _RepairTicketDetails extends ConsumerStatefulWidget {
  final RepairTicketModel ticket;
  final _StatusChanged onStatusChanged;

  const _RepairTicketDetails({
    required this.ticket,
    required this.onStatusChanged,
  });

  @override
  ConsumerState<_RepairTicketDetails> createState() =>
      _RepairTicketDetailsState();
}

class _RepairTicketDetailsState extends ConsumerState<_RepairTicketDetails> {
  final _formKey = GlobalKey<FormState>();
  final _noteController = TextEditingController();

  RepairTicketStatus? _selectedStatus;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final statuses = _nextStatuses(widget.ticket.status);
    _selectedStatus = statuses.isEmpty ? null : statuses.first;
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ticket = widget.ticket;
    final imei = ticket.imei?.trim();
    final estimatedCost = ticket.estimatedCost;
    final totalCost = ticket.totalCost;
    final statuses = _nextStatuses(ticket.status);
    final selectedStatus = _selectedStatus;
    final paymentsAsync = ref.watch(repairPaymentsProvider(ticket.id));
    final payments = paymentsAsync.value;
    final paid = payments?.fold<double>(
      0,
      (sum, payment) => sum + payment.amount,
    );
    final balance =
        totalCost == null || paid == null
            ? null
            : (totalCost - paid).clamp(0, double.infinity).toDouble();

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      ticket.ticketNo ?? 'Repair Ticket',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed:
                        _isSaving ? null : () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                runSpacing: 6,
                children: [
                  _DetailLine(label: 'Customer', value: ticket.customerName),
                  _DetailLine(
                    label: 'Device',
                    value: '${ticket.deviceBrand} ${ticket.deviceModel}',
                  ),
                  _DetailLine(label: 'Status', value: ticket.status.label),
                  if (imei != null && imei.isNotEmpty)
                    _DetailLine(label: 'IMEI', value: imei),
                  if (estimatedCost != null)
                    _DetailLine(
                      label: 'Service Estimate',
                      value: 'Rs ${estimatedCost.toStringAsFixed(0)}',
                    ),
                  if (totalCost != null)
                    _DetailLine(
                      label: 'Final Bill',
                      value: 'Rs ${totalCost.toStringAsFixed(0)}',
                    ),
                  _DetailLine(
                    label: 'Received',
                    value:
                        paid == null
                            ? paymentsAsync.hasError
                                ? 'Unable to load'
                                : 'Loading...'
                            : 'Rs ${paid.toStringAsFixed(0)}',
                  ),
                  if (balance != null)
                    _DetailLine(
                      label: 'Remaining',
                      value: 'Rs ${balance.toStringAsFixed(0)}',
                    ),
                ],
              ),
              if (totalCost != null &&
                  balance != null &&
                  balance > 0.009 &&
                  ticket.status != RepairTicketStatus.cancelled) ...[
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed:
                      _isSaving ? null : () => _showPaymentDialog(balance),
                  icon: const Icon(Icons.payments_outlined),
                  label: const Text('Receive Payment'),
                ),
              ],
              const SizedBox(height: 12),
              Text(
                ticket.faultDescription,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: _isSaving ? null : _archive,
                icon: const Icon(Icons.archive_outlined),
                label: const Text('Archive Ticket'),
              ),
              const SizedBox(height: 12),
              if (statuses.isEmpty)
                Text(
                  'Is ticket ka status ab change nahi ho sakta.',
                  style: Theme.of(context).textTheme.bodyMedium,
                )
              else ...[
                DropdownButtonFormField<RepairTicketStatus>(
                  initialValue: selectedStatus,
                  decoration: const InputDecoration(
                    labelText: 'Next status',
                    border: OutlineInputBorder(),
                  ),
                  items:
                      statuses
                          .map(
                            (status) => DropdownMenuItem(
                              value: status,
                              child: Text(status.label),
                            ),
                          )
                          .toList(),
                  onChanged:
                      _isSaving
                          ? null
                          : (status) {
                            setState(() {
                              _selectedStatus = status;
                            });
                          },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _noteController,
                  enabled: !_isSaving,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Status note optional',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed:
                      _isSaving || selectedStatus == null
                          ? null
                          : () => _submit(selectedStatus),
                  icon:
                      _isSaving
                          ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                          : const Icon(Icons.done),
                  label: Text(_isSaving ? 'Updating...' : 'Update Status'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showPaymentDialog(double remaining) async {
    List<AccountModel> availableAccounts;
    try {
      availableAccounts = await ref.read(accountsProvider.future);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Receiving accounts load nahi ho sake: $error')),
      );
      return;
    }
    if (!mounted) return;

    final amountController = TextEditingController(
      text: remaining.toStringAsFixed(0),
    );
    final noteController = TextEditingController();
    var method = PaymentMethod.cash;
    String? accountId;
    var isReceiving = false;
    String? paymentError;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder:
          (dialogContext) => StatefulBuilder(
            builder: (context, setDialogState) {
              final compatible = PosPaymentAccountPolicy.compatibleAccounts(
                method,
                availableAccounts,
              );
              final effectiveAccountId =
                  accountId ??
                  PosPaymentAccountPolicy.suggestedAccount(
                    method,
                    compatible,
                  )?.id;
              return AlertDialog(
                title: const Text('Receive Repair Payment'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: amountController,
                      enabled: !isReceiving,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: 'Amount',
                        helperText:
                            'Remaining Rs ${remaining.toStringAsFixed(0)}',
                      ),
                    ),
                    DropdownButtonFormField<PaymentMethod>(
                      initialValue: method,
                      decoration: const InputDecoration(labelText: 'Method'),
                      items:
                          PaymentMethod.values
                              .where((value) => value != PaymentMethod.credit)
                              .map(
                                (value) => DropdownMenuItem(
                                  value: value,
                                  child: Text(value.label),
                                ),
                              )
                              .toList(),
                      onChanged:
                          isReceiving
                              ? null
                              : (value) {
                                if (value == null) return;
                                setDialogState(() {
                                  method = value;
                                  accountId = null;
                                });
                              },
                    ),
                    DropdownButtonFormField<String>(
                      initialValue: effectiveAccountId,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: 'Receiving Account',
                        helperText:
                            compatible.isEmpty
                                ? 'Create a compatible account first.'
                                : null,
                      ),
                      items:
                          compatible
                              .map(
                                (account) => DropdownMenuItem(
                                  value: account.id,
                                  child: Text(account.name),
                                ),
                              )
                              .toList(),
                      onChanged:
                          isReceiving || compatible.isEmpty
                              ? null
                              : (value) =>
                                  setDialogState(() => accountId = value),
                    ),
                    TextField(
                      controller: noteController,
                      enabled: !isReceiving,
                      decoration: const InputDecoration(
                        labelText: 'Note optional',
                      ),
                    ),
                    if (paymentError != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        paymentError!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed:
                        isReceiving
                            ? null
                            : () => Navigator.of(dialogContext).pop(),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed:
                        isReceiving || effectiveAccountId == null
                            ? null
                            : () async {
                              final amount =
                                  double.tryParse(
                                    amountController.text.trim(),
                                  ) ??
                                  0;
                              if (amount <= 0 || amount > remaining + 0.01) {
                                setDialogState(() {
                                  paymentError =
                                      'Enter an amount between Rs 1 and '
                                      'Rs ${remaining.toStringAsFixed(0)}.';
                                });
                                return;
                              }
                              setDialogState(() {
                                isReceiving = true;
                                paymentError = null;
                              });
                              final ok = await ref
                                  .read(
                                    repairPaymentControllerProvider.notifier,
                                  )
                                  .recordPayment(
                                    ticket: widget.ticket,
                                    amount: amount,
                                    method: method.code,
                                    accountId: effectiveAccountId,
                                    note: noteController.text,
                                  );
                              if (!dialogContext.mounted || !mounted) return;
                              if (ok) {
                                Navigator.of(dialogContext).pop();
                                ScaffoldMessenger.of(this.context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Payment received'),
                                  ),
                                );
                              } else {
                                final error =
                                    ref
                                        .read(repairPaymentControllerProvider)
                                        .asError
                                        ?.error
                                        .toString() ??
                                    'Payment receive nahi ho saki';
                                setDialogState(() {
                                  isReceiving = false;
                                  paymentError = error;
                                });
                              }
                            },
                    child:
                        isReceiving
                            ? const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                                SizedBox(width: 8),
                                Text('Receiving...'),
                              ],
                            )
                            : const Text('Receive'),
                  ),
                ],
              );
            },
          ),
    );
    amountController.dispose();
    noteController.dispose();
  }

  Future<void> _submit(RepairTicketStatus status) async {
    if (status == RepairTicketStatus.completed) {
      final completed = await showRepairCompletionDialog(
        context,
        ref,
        widget.ticket,
      );
      if (!mounted || !completed) return;
      Navigator.of(context).pop();
      return;
    }
    final isValid = _formKey.currentState?.validate() ?? false;
    if (!isValid) return;

    setState(() {
      _isSaving = true;
    });

    final updated = await widget.onStatusChanged(
      status: status,
      note: _noteController.text,
      totalCost: null,
    );

    if (!mounted) return;

    setState(() {
      _isSaving = false;
    });

    if (updated) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _archive() async {
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder:
              (dialogContext) => AlertDialog(
                title: const Text('Archive ticket?'),
                content: const Text(
                  'Ticket list se hide ho ga. Financial history, payments, '
                  'parts aur reversal records delete nahi honge.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(false),
                    child: const Text('Back'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.of(dialogContext).pop(true),
                    child: const Text('Archive'),
                  ),
                ],
              ),
        ) ??
        false;
    if (!confirmed || !mounted) return;
    setState(() => _isSaving = true);
    final archived = await ref
        .read(repairTicketControllerProvider.notifier)
        .archiveRepair(widget.ticket);
    if (!mounted) return;
    setState(() => _isSaving = false);
    if (archived) {
      Navigator.of(context).pop();
    }
  }

  static List<RepairTicketStatus> _nextStatuses(RepairTicketStatus current) {
    return RepairTicketStatus.values
        .where((status) => current.canMoveTo(status))
        .toList();
  }
}

class _DetailLine extends StatelessWidget {
  final String label;
  final String value;

  const _DetailLine({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: RichText(
        text: TextSpan(
          style: Theme.of(context).textTheme.bodyMedium,
          children: [
            TextSpan(
              text: '$label: ',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            TextSpan(text: value),
          ],
        ),
      ),
    );
  }
}

class _RepairStatusFilterBar extends StatefulWidget {
  final RepairTicketStatus? selectedStatus;
  final ValueChanged<RepairTicketStatus?> onChanged;

  const _RepairStatusFilterBar({
    required this.selectedStatus,
    required this.onChanged,
  });

  @override
  State<_RepairStatusFilterBar> createState() => _RepairStatusFilterBarState();
}

class _RepairStatusFilterBarState extends State<_RepairStatusFilterBar> {
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final statuses = <RepairTicketStatus?>[
      null,
      RepairTicketStatus.received,
      RepairTicketStatus.diagnosed,
      RepairTicketStatus.inProgress,
      RepairTicketStatus.waitingPart,
      RepairTicketStatus.completed,
      RepairTicketStatus.delivered,
      RepairTicketStatus.cancelled,
    ];
    return SizedBox(
      height: 56,
      child: Listener(
        onPointerSignal: (event) {
          if (event is! PointerScrollEvent || !_scrollController.hasClients) {
            return;
          }

          final delta =
              event.scrollDelta.dx == 0
                  ? event.scrollDelta.dy
                  : event.scrollDelta.dx;
          final position = _scrollController.position;
          final offset = (_scrollController.offset + delta).clamp(
            position.minScrollExtent,
            position.maxScrollExtent,
          );

          _scrollController.jumpTo(offset);
        },
        child: ScrollConfiguration(
          behavior: const _StatusFilterScrollBehavior(),
          child: SingleChildScrollView(
            controller: _scrollController,
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                for (final status in statuses) ...[
                  FilterChip(
                    selected: widget.selectedStatus == status,
                    label: Text(status == null ? 'All' : status.label),
                    onSelected: (_) => widget.onChanged(status),
                  ),
                  if (status != statuses.last) const SizedBox(width: 8),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusFilterScrollBehavior extends MaterialScrollBehavior {
  const _StatusFilterScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices {
    return {
      PointerDeviceKind.touch,
      PointerDeviceKind.mouse,
      PointerDeviceKind.stylus,
      PointerDeviceKind.trackpad,
      PointerDeviceKind.unknown,
    };
  }
}

class _RepairTicketCard extends StatelessWidget {
  final RepairTicketModel ticket;
  final VoidCallback onTap;
  const _RepairTicketCard({required this.ticket, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final createdDate = _formatDate(ticket.createdAt);
    final imei = ticket.imei?.trim();
    final estimatedCost = ticket.estimatedCost;
    final estimate =
        estimatedCost == null
            ? null
            : 'Service est. Rs ${estimatedCost.toStringAsFixed(0)}';
    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      ticket.ticketNo ?? 'No Ticket No',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  _StatusBadge(status: ticket.status),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                ticket.customerName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 4),
              Text(
                '${ticket.deviceBrand} ${ticket.deviceModel}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (imei != null && imei.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  'IMEI: $imei',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              const SizedBox(height: 8),
              Text(
                ticket.faultDescription,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(
                    Icons.schedule,
                    size: 16,
                    color: Theme.of(context).textTheme.bodySmall?.color,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    createdDate,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (estimate != null) ...[
                    const Spacer(),
                    Text(
                      estimate,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _formatDate(DateTime? date) {
    if (date == null) return 'No date';
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    final year = date.year.toString();
    return '$day-$month-$year';
  }
}

class _StatusBadge extends StatelessWidget {
  final RepairTicketStatus status;
  const _StatusBadge({required this.status});
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        status.label,
        style: Theme.of(
          context,
        ).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _EmptyRepairsView extends StatelessWidget {
  final RepairTicketStatus? selectedStatus;
  final VoidCallback onCreate;
  const _EmptyRepairsView({
    required this.selectedStatus,
    required this.onCreate,
  });
  @override
  Widget build(BuildContext context) {
    final status = selectedStatus;
    final text =
        status == null
            ? 'Abhi koi repair ticket nahi bana.'
            : '${status.label} status mein koi repair ticket nahi hai.';
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.build_circle_outlined, size: 52),
              const SizedBox(height: 12),
              Text(
                'No Repairs',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(text, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: onCreate,
                icon: const Icon(Icons.add),
                label: const Text('Create Repair Ticket'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RepairErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _RepairErrorView({required this.message, required this.onRetry});
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 52),
              const SizedBox(height: 12),
              Text(
                'Repairs load nahi ho sake',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
