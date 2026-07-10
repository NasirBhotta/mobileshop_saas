import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobileshop_saas/features/reports/presentation/providers/sales_report_provider.dart';
import 'package:mobileshop_saas/features/reports/presentation/widgets/reports_back_button.dart';

import '../../data/models/sales_report_models.dart';

class SalesReportSchedulesScreen extends ConsumerWidget {
  const SalesReportSchedulesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final schedulesAsync = ref.watch(salesReportSchedulesProvider);
    final jobsAsync = ref.watch(salesReportDeliveryJobsProvider);
    final controllerState = ref.watch(salesReportScheduleControllerProvider);

    return Scaffold(
      appBar: AppBar(
        leading: const ReportsBackButton(),
        title: const Text('Scheduled Sales Reports'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed:
                controllerState.isLoading
                    ? null
                    : () {
                      ref.invalidate(salesReportSchedulesProvider);
                      ref.invalidate(salesReportDeliveryJobsProvider);
                    },
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.go('/reports/sales/schedules/new'),
        icon: const Icon(Icons.add),
        label: const Text('New Schedule'),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(salesReportSchedulesProvider);
            ref.invalidate(salesReportDeliveryJobsProvider);
          },
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 950;

              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1180),
                      child:
                          isWide
                              ? Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    flex: 3,
                                    child: _SchedulesPanel(
                                      schedulesAsync: schedulesAsync,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    flex: 2,
                                    child: _DeliveryJobsPanel(
                                      jobsAsync: jobsAsync,
                                    ),
                                  ),
                                ],
                              )
                              : Column(
                                children: [
                                  _SchedulesPanel(
                                    schedulesAsync: schedulesAsync,
                                  ),
                                  const SizedBox(height: 12),
                                  _DeliveryJobsPanel(jobsAsync: jobsAsync),
                                ],
                              ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _SchedulesPanel extends StatelessWidget {
  final AsyncValue<List<SalesReportScheduleModel>> schedulesAsync;

  const _SchedulesPanel({required this.schedulesAsync});

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'Report Schedules',
      icon: Icons.schedule_send_outlined,
      child: schedulesAsync.when(
        loading:
            () => const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
        error: (error, _) => _ErrorText(error: error),
        data: (schedules) {
          if (schedules.isEmpty) {
            return const _EmptySchedulesView();
          }

          return Column(
            children: [
              for (final schedule in schedules) ...[
                _ScheduleCard(schedule: schedule),
                const SizedBox(height: 10),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _DeliveryJobsPanel extends StatelessWidget {
  final AsyncValue<List<SalesReportDeliveryJobModel>> jobsAsync;

  const _DeliveryJobsPanel({required this.jobsAsync});

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'Delivery History',
      icon: Icons.mark_email_read_outlined,
      child: jobsAsync.when(
        loading:
            () => const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
        error: (error, _) => _ErrorText(error: error),
        data: (jobs) {
          if (jobs.isEmpty) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: Text('No delivery jobs yet')),
            );
          }

          return Column(
            children: [
              for (final job in jobs.take(20)) ...[
                _DeliveryJobTile(job: job),
                const Divider(height: 1),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _ScheduleCard extends ConsumerWidget {
  final SalesReportScheduleModel schedule;

  const _ScheduleCard({required this.schedule});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isActive = schedule.status == 'active';
    final isPaused = schedule.status == 'paused';
    final isCancelled = schedule.status == 'cancelled';
    final controllerState = ref.watch(salesReportScheduleControllerProvider);

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    schedule.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                _StatusChip(status: schedule.status),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _MiniInfo(icon: Icons.repeat, text: schedule.cadence.label),
                _MiniInfo(
                  icon: Icons.storefront_outlined,
                  text: schedule.reportScope.label,
                ),
                _MiniInfo(
                  icon: Icons.file_download_outlined,
                  text: schedule.exportFormat.label,
                ),
                _MiniInfo(
                  icon: Icons.email_outlined,
                  text: schedule.sendToEmail,
                ),
                _MiniInfo(
                  icon: Icons.event_available_outlined,
                  text: 'Next: ${_dateTimeText(schedule.nextRunAt)}',
                ),
                if (schedule.lastRunAt != null)
                  _MiniInfo(
                    icon: Icons.history,
                    text: 'Last: ${_dateTimeText(schedule.lastRunAt!)}',
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (isActive)
                  OutlinedButton.icon(
                    onPressed:
                        controllerState.isLoading
                            ? null
                            : () =>
                                _updateStatus(context, ref, schedule, 'paused'),
                    icon: const Icon(Icons.pause),
                    label: const Text('Pause'),
                  ),
                if (isPaused)
                  FilledButton.icon(
                    onPressed:
                        controllerState.isLoading
                            ? null
                            : () =>
                                _updateStatus(context, ref, schedule, 'active'),
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Activate'),
                  ),
                if (!isCancelled)
                  OutlinedButton.icon(
                    onPressed:
                        controllerState.isLoading
                            ? null
                            : () => _confirmCancel(context, ref, schedule),
                    icon: const Icon(Icons.cancel_outlined),
                    label: const Text('Cancel'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _updateStatus(
    BuildContext context,
    WidgetRef ref,
    SalesReportScheduleModel schedule,
    String status,
  ) async {
    final ok = await ref
        .read(salesReportScheduleControllerProvider.notifier)
        .updateStatus(schedule: schedule, status: status);

    if (!context.mounted) return;

    final error = ref.read(salesReportScheduleControllerProvider).asError;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok ? 'Schedule updated' : error?.error.toString() ?? 'Not updated',
        ),
      ),
    );
  }

  void _confirmCancel(
    BuildContext context,
    WidgetRef ref,
    SalesReportScheduleModel schedule,
  ) {
    showDialog<void>(
      context: context,
      builder: (_) {
        return AlertDialog(
          title: const Text('Cancel Schedule?'),
          content: Text(
            'This will stop future automated reports for "${schedule.name}".',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Back'),
            ),
            FilledButton(
              onPressed: () async {
                Navigator.pop(context);

                await _updateStatus(context, ref, schedule, 'cancelled');
              },
              child: const Text('Cancel Schedule'),
            ),
          ],
        );
      },
    );
  }
}

class _DeliveryJobTile extends StatelessWidget {
  final SalesReportDeliveryJobModel job;

  const _DeliveryJobTile({required this.job});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(child: Icon(_jobIcon(job.status))),
      title: Text(
        '${job.exportFormat.label} report · ${job.status.toUpperCase()}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '${_dateText(job.dateFrom)} - ${_dateText(job.dateTo)}\n${job.sendToEmail}',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing:
          job.createdAt == null
              ? null
              : Text(
                _dateText(job.createdAt!),
                style: Theme.of(context).textTheme.bodySmall,
              ),
    );
  }

  IconData _jobIcon(String status) {
    switch (status) {
      case 'sent':
        return Icons.check;
      case 'failed':
        return Icons.error_outline;
      case 'processing':
        return Icons.hourglass_top;
      case 'pending':
      default:
        return Icons.schedule;
    }
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

class _StatusChip extends StatelessWidget {
  final String status;

  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    return Chip(
      visualDensity: VisualDensity.compact,
      label: Text(_label(status)),
    );
  }

  String _label(String value) {
    switch (value) {
      case 'active':
        return 'Active';
      case 'paused':
        return 'Paused';
      case 'cancelled':
        return 'Cancelled';
      default:
        return value;
    }
  }
}

class _MiniInfo extends StatelessWidget {
  final IconData icon;
  final String text;

  const _MiniInfo({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15),
        const SizedBox(width: 4),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 220),
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}

class _EmptySchedulesView extends StatelessWidget {
  const _EmptySchedulesView();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 26),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            children: [
              Icon(
                Icons.schedule_send_outlined,
                size: 54,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 10),
              Text(
                'No scheduled reports',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              const Text(
                'Business and Enterprise tenants can receive sales reports automatically by email.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => context.go('/reports/sales/schedules/new'),
                icon: const Icon(Icons.add),
                label: const Text('Create Schedule'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorText extends StatelessWidget {
  final Object error;

  const _ErrorText({required this.error});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(18),
      child: Text(
        error.toString(),
        textAlign: TextAlign.center,
        style: TextStyle(color: Theme.of(context).colorScheme.error),
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

String _dateTimeText(DateTime date) {
  final hour = date.hour.toString().padLeft(2, '0');
  final minute = date.minute.toString().padLeft(2, '0');
  return '${_dateText(date)} $hour:$minute';
}
