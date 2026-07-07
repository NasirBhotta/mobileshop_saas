import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobileshop_saas/core/extensions/repair_ticket_ext.dart';
import 'package:mobileshop_saas/core/utils/responsive.dart';
import 'package:mobileshop_saas/features/repairs/presentation/providers/repair_provider.dart';
import '../../data/models/repair_ticket_model.dart';

class RepairsListScreen extends ConsumerWidget {
  const RepairsListScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ticketsAsync = ref.watch(repairTicketsProvider);
    final selectedStatus = ref.watch(selectedRepairStatusFilterProvider);
    final syncState = ref.watch(repairSyncControllerProvider);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Back',
          onPressed: () => _leaveRepairs(context),
          icon: const Icon(Icons.arrow_back),
        ),
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
                    return _EmptyRepairsView(
                      selectedStatus: selectedStatus,
                      onCreate: () => context.push('/repairs/new'),
                    );
                  }
                  return RefreshIndicator(
                    onRefresh: () async {
                      await ref
                          .read(repairSyncControllerProvider.notifier)
                          .sync();
                      ref.invalidate(repairTicketsProvider);
                    },
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

  static void _leaveRepairs(BuildContext context) {
    if (context.canPop()) {
      context.pop();
      return;
    }

    context.go('/dashboard');
  }

  static void _showTicketDetails(
    BuildContext context,
    WidgetRef ref,
    RepairTicketModel ticket,
  ) {
    final details = _RepairTicketDetails(
      ticket: ticket,
      onStatusChanged: ({required status, note, totalCost}) async {
        final updatedTicket = await ref
            .read(repairTicketControllerProvider.notifier)
            .updateStatus(
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

class _RepairTicketDetails extends StatefulWidget {
  final RepairTicketModel ticket;
  final _StatusChanged onStatusChanged;

  const _RepairTicketDetails({
    required this.ticket,
    required this.onStatusChanged,
  });

  @override
  State<_RepairTicketDetails> createState() => _RepairTicketDetailsState();
}

class _RepairTicketDetailsState extends State<_RepairTicketDetails> {
  final _formKey = GlobalKey<FormState>();
  final _noteController = TextEditingController();
  final _totalCostController = TextEditingController();

  RepairTicketStatus? _selectedStatus;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final statuses = _nextStatuses(widget.ticket.status);
    _selectedStatus = statuses.isEmpty ? null : statuses.first;

    final amount = widget.ticket.totalCost ?? widget.ticket.estimatedCost;
    if (amount != null) {
      _totalCostController.text = amount.toStringAsFixed(0);
    }
  }

  @override
  void dispose() {
    _noteController.dispose();
    _totalCostController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ticket = widget.ticket;
    final statuses = _nextStatuses(ticket.status);
    final selectedStatus = _selectedStatus;
    final needsAmount = selectedStatus == RepairTicketStatus.completed;

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
                  if (ticket.imei != null && ticket.imei!.trim().isNotEmpty)
                    _DetailLine(label: 'IMEI', value: ticket.imei!),
                  if (ticket.estimatedCost != null)
                    _DetailLine(
                      label: 'Estimate',
                      value: 'Rs ${ticket.estimatedCost!.toStringAsFixed(0)}',
                    ),
                  if (ticket.totalCost != null)
                    _DetailLine(
                      label: 'Final Amount',
                      value: 'Rs ${ticket.totalCost!.toStringAsFixed(0)}',
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                ticket.faultDescription,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 20),
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
                if (needsAmount) ...[
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _totalCostController,
                    enabled: !_isSaving,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Final amount received',
                      prefixText: 'Rs ',
                      border: OutlineInputBorder(),
                    ),
                    validator: _amountValidator,
                  ),
                ],
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

  Future<void> _submit(RepairTicketStatus status) async {
    final isValid = _formKey.currentState?.validate() ?? false;
    if (!isValid) return;

    setState(() {
      _isSaving = true;
    });

    final updated = await widget.onStatusChanged(
      status: status,
      note: _noteController.text,
      totalCost:
          status == RepairTicketStatus.completed
              ? double.tryParse(_totalCostController.text.trim())
              : null,
    );

    if (!mounted) return;

    setState(() {
      _isSaving = false;
    });

    if (updated) {
      Navigator.of(context).pop();
    }
  }

  String? _amountValidator(String? value) {
    final amount = double.tryParse(value?.trim() ?? '');
    if (amount == null) {
      return 'Final amount enter karo';
    }
    if (amount < 0) {
      return 'Amount negative nahi ho sakta';
    }
    return null;
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

class _RepairStatusFilterBar extends StatelessWidget {
  final RepairTicketStatus? selectedStatus;
  final ValueChanged<RepairTicketStatus?> onChanged;
  const _RepairStatusFilterBar({
    required this.selectedStatus,
    required this.onChanged,
  });
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
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        itemCount: statuses.length,
        separatorBuilder: (_, _) {
          return const SizedBox(width: 8);
        },
        itemBuilder: (context, index) {
          final status = statuses[index];
          final isSelected = selectedStatus == status;
          return FilterChip(
            selected: isSelected,
            label: Text(status == null ? 'All' : status.label),
            onSelected: (_) => onChanged(status),
          );
        },
      ),
    );
  }
}

class _RepairTicketCard extends StatelessWidget {
  final RepairTicketModel ticket;
  final VoidCallback onTap;
  const _RepairTicketCard({required this.ticket, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final createdDate = _formatDate(ticket.createdAt);
    final estimate =
        ticket.estimatedCost == null
            ? null
            : 'Est. Rs ${ticket.estimatedCost!.toStringAsFixed(0)}';
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
              if (ticket.imei != null && ticket.imei!.trim().isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  'IMEI: ${ticket.imei}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              const SizedBox(height: 8),
              Expanded(
                child: Text(
                  ticket.faultDescription,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
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
    final text =
        selectedStatus == null
            ? 'Abhi koi repair ticket nahi bana.'
            : '${selectedStatus!.label} status mein koi repair ticket nahi hai.';
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
