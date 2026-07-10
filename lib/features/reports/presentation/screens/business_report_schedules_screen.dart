import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobileshop_saas/features/reports/presentation/providers/business_report_provider.dart';
import 'package:mobileshop_saas/features/reports/presentation/widgets/reports_back_button.dart';

import '../../data/models/business_report_models.dart';

class BusinessReportSchedulesScreen extends ConsumerWidget {
  const BusinessReportSchedulesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final schedulesAsync = ref.watch(businessReportSchedulesProvider);
    final jobsAsync = ref.watch(businessReportDeliveryJobsProvider);
    final controllerState = ref.watch(businessReportScheduleControllerProvider);

    return Scaffold(
      appBar: AppBar(
        leading: const ReportsBackButton(),
        title: const Text('Scheduled Business Reports'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: () {
              ref.invalidate(businessReportSchedulesProvider);
              ref.invalidate(businessReportDeliveryJobsProvider);
            },
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.go('/reports/business/schedules/new'),
        icon: const Icon(Icons.add),
        label: const Text('New Schedule'),
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 980;

            final schedulesPanel = schedulesAsync.when(
              loading: () => const _LoadingCard(title: 'Schedules'),
              error: (error, _) => _ErrorCard(title: 'Schedules', error: error),
              data:
                  (schedules) => _SchedulesPanel(
                    schedules: schedules,
                    isLoading: controllerState.isLoading,
                  ),
            );

            final jobsPanel = jobsAsync.when(
              loading: () => const _LoadingCard(title: 'Delivery Jobs'),
              error:
                  (error, _) =>
                      _ErrorCard(title: 'Delivery Jobs', error: error),
              data: (jobs) => _DeliveryJobsPanel(jobs: jobs),
            );

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
                                Expanded(flex: 3, child: schedulesPanel),
                                const SizedBox(width: 12),
                                Expanded(flex: 2, child: jobsPanel),
                              ],
                            )
                            : Column(
                              children: [
                                schedulesPanel,
                                const SizedBox(height: 12),
                                jobsPanel,
                              ],
                            ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _SchedulesPanel extends ConsumerWidget {
  final List<BusinessReportScheduleModel> schedules;
  final bool isLoading;

  const _SchedulesPanel({required this.schedules, required this.isLoading});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _SectionCard(
      title: 'Schedules',
      icon: Icons.schedule_send_outlined,
      child:
          schedules.isEmpty
              ? const _EmptyView(
                icon: Icons.schedule_send_outlined,
                title: 'No scheduled reports yet',
                subtitle:
                    'Create daily, weekly, or monthly delivery for sales, P&L, inventory, cash flow, repairs, or dashboard reports.',
              )
              : Column(
                children: [
                  for (final schedule in schedules) ...[
                    _ScheduleCard(
                      schedule: schedule,
                      isLoading: isLoading,
                      onStatusChange: (status) async {
                        final ok = await ref
                            .read(
                              businessReportScheduleControllerProvider.notifier,
                            )
                            .updateStatus(schedule: schedule, status: status);

                        if (!context.mounted) return;

                        final error =
                            ref
                                .read(businessReportScheduleControllerProvider)
                                .asError;

                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              ok
                                  ? 'Schedule updated'
                                  : error?.error.toString() ??
                                      'Could not update schedule',
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 10),
                  ],
                ],
              ),
    );
  }
}

class _ScheduleCard extends StatelessWidget {
  final BusinessReportScheduleModel schedule;
  final bool isLoading;
  final ValueChanged<String> onStatusChange;

  const _ScheduleCard({
    required this.schedule,
    required this.isLoading,
    required this.onStatusChange,
  });

  @override
  Widget build(BuildContext context) {
    final isActive = schedule.status == 'active';
    final isPaused = schedule.status == 'paused';
    final isCancelled = schedule.status == 'cancelled';

    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 640;

            final info = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        schedule.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w900),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _StatusChip(status: schedule.status),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _MiniInfo(
                      icon: Icons.analytics_outlined,
                      label: schedule.reportType.label,
                    ),
                    _MiniInfo(
                      icon: Icons.repeat,
                      label: _title(schedule.cadence),
                    ),
                    _MiniInfo(
                      icon: Icons.account_tree_outlined,
                      label:
                          schedule.reportScope == 'all_branches'
                              ? 'All Branches'
                              : 'Current Branch',
                    ),
                    _MiniInfo(
                      icon: Icons.file_download_outlined,
                      label: schedule.exportFormat.toUpperCase(),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  schedule.sendToEmail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 4),
                Text(
                  'Next: ${_dateTimeText(schedule.nextRunAt)}'
                  '${schedule.lastRunAt == null ? '' : ' · Last: ${_dateTimeText(schedule.lastRunAt!)}'}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            );

            final actions = Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 8,
              children: [
                if (!isActive && !isCancelled)
                  OutlinedButton.icon(
                    onPressed:
                        isLoading ? null : () => onStatusChange('active'),
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Activate'),
                  ),
                if (isActive)
                  OutlinedButton.icon(
                    onPressed:
                        isLoading ? null : () => onStatusChange('paused'),
                    icon: const Icon(Icons.pause),
                    label: const Text('Pause'),
                  ),
                if (!isCancelled)
                  OutlinedButton.icon(
                    onPressed:
                        isLoading ? null : () => onStatusChange('cancelled'),
                    icon: const Icon(Icons.cancel_outlined),
                    label: const Text('Cancel'),
                  ),
                if (isPaused) const SizedBox.shrink(),
              ],
            );

            if (isWide) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: info),
                  const SizedBox(width: 12),
                  actions,
                ],
              );
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [info, const SizedBox(height: 12), actions],
            );
          },
        ),
      ),
    );
  }
}

class _DeliveryJobsPanel extends StatelessWidget {
  final List<BusinessReportDeliveryJobModel> jobs;

  const _DeliveryJobsPanel({required this.jobs});

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'Delivery Jobs',
      icon: Icons.mark_email_read_outlined,
      child:
          jobs.isEmpty
              ? const _EmptyView(
                icon: Icons.mark_email_unread_outlined,
                title: 'No delivery jobs',
                subtitle:
                    'When scheduled reports are queued, their send status will appear here.',
              )
              : Column(
                children: [
                  for (final job in jobs) ...[
                    _DeliveryJobTile(job: job),
                    const Divider(height: 18),
                  ],
                ],
              ),
    );
  }
}

class _DeliveryJobTile extends StatelessWidget {
  final BusinessReportDeliveryJobModel job;

  const _DeliveryJobTile({required this.job});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(child: Icon(_jobIcon(job.status))),
      title: Text(
        job.reportType.label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '${_dateText(job.dateFrom)} - ${_dateText(job.dateTo)}\n'
        '${job.sendToEmail}'
        '${job.errorMessage == null ? '' : '\n${job.errorMessage}'}',
      ),
      isThreeLine: job.errorMessage != null,
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          _StatusChip(status: job.status),
          const SizedBox(height: 4),
          Text(
            job.exportFormat.toUpperCase(),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  IconData _jobIcon(String status) {
    switch (status) {
      case 'sent':
        return Icons.check_circle_outline;
      case 'failed':
        return Icons.error_outline;
      case 'processing':
        return Icons.hourglass_top;
      case 'pending':
      default:
        return Icons.schedule_outlined;
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
                      fontWeight: FontWeight.w900,
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

class _MiniInfo extends StatelessWidget {
  final IconData icon;
  final String label;

  const _MiniInfo({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: Icon(icon, size: 16),
      label: Text(label),
      visualDensity: VisualDensity.compact,
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String status;

  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      'active' || 'sent' => Theme.of(context).colorScheme.primary,
      'failed' || 'cancelled' => Theme.of(context).colorScheme.error,
      _ => Theme.of(context).colorScheme.secondary,
    };

    return Chip(
      label: Text(_title(status)),
      side: BorderSide(color: color),
      labelStyle: TextStyle(color: color, fontWeight: FontWeight.w800),
      visualDensity: VisualDensity.compact,
    );
  }
}

class _EmptyView extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _EmptyView({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 34, horizontal: 12),
      child: Column(
        children: [
          Icon(icon, size: 46, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _LoadingCard extends StatelessWidget {
  final String title;

  const _LoadingCard({required this.title});

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: title,
      icon: Icons.hourglass_empty,
      child: const Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: CircularProgressIndicator()),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  final String title;
  final Object error;

  const _ErrorCard({required this.title, required this.error});

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: title,
      icon: Icons.error_outline,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Text(
          error.toString(),
          textAlign: TextAlign.center,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      ),
    );
  }
}

String _title(String value) {
  return value
      .replaceAll('_', ' ')
      .split(' ')
      .where((part) => part.trim().isNotEmpty)
      .map((part) {
        final lower = part.toLowerCase();
        return '${lower[0].toUpperCase()}${lower.substring(1)}';
      })
      .join(' ');
}

String _dateText(DateTime date) {
  final day = date.day.toString().padLeft(2, '0');
  final month = date.month.toString().padLeft(2, '0');
  final year = date.year.toString();

  return '$day-$month-$year';
}

String _dateTimeText(DateTime date) {
  final day = date.day.toString().padLeft(2, '0');
  final month = date.month.toString().padLeft(2, '0');
  final year = date.year.toString();

  final hour = date.hour.toString().padLeft(2, '0');
  final minute = date.minute.toString().padLeft(2, '0');

  return '$day-$month-$year $hour:$minute';
}
