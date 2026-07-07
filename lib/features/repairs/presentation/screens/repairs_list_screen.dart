import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobileshop_saas/core/extensions/repair_ticket_ext.dart';
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
                                  _showTicketPreview(context, ticket);
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
                                _showTicketPreview(context, ticket);
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

  static void _showTicketPreview(
    BuildContext context,
    RepairTicketModel ticket,
  ) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  ticket.ticketNo ?? 'Repair Ticket',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Text('Customer: ${ticket.customerName}'),
                Text('Device: ${ticket.deviceBrand} ${ticket.deviceModel}'),
                Text('Status: ${ticket.status.label}'),
                if (ticket.imei != null && ticket.imei!.trim().isNotEmpty)
                  Text('IMEI: ${ticket.imei}'),
                const SizedBox(height: 12),
                Text(
                  ticket.faultDescription,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Close'),
                ),
              ],
            ),
          ),
        );
      },
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
