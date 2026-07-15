import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobileshop_saas/features/expenses/presentation/providers/expense_provider.dart';

import '../../data/models/expense_models.dart';

class RecurringExpensesScreen extends ConsumerWidget {
  const RecurringExpensesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rulesAsync = ref.watch(recurringExpenseRulesProvider);
    final controllerState = ref.watch(recurringExpenseControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Recurring Expenses'),
        actions: [
          IconButton(
            tooltip: 'Sync Due Expenses',
            onPressed:
                controllerState.isLoading
                    ? null
                    : () async {
                      final count =
                          await ref
                              .read(recurringExpenseControllerProvider.notifier)
                              .generateDueDrafts();

                      if (!context.mounted) return;

                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            count > 0
                                ? '$count recurring expense(s) generated'
                                : 'No due recurring expenses',
                          ),
                        ),
                      );
                    },
            icon:
                controllerState.isLoading
                    ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                    : const Icon(Icons.playlist_add_check),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/expenses/recurring/new'),
        icon: const Icon(Icons.add),
        label: const Text('New Rule'),
      ),
      body: rulesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _RecurringErrorView(error: error),
        data: (rules) {
          if (rules.isEmpty) {
            return const _EmptyRecurringView();
          }

          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(recurringExpenseRulesProvider);
              ref.invalidate(activeRecurringExpenseRulesProvider);
            },
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth >= 850;

                if (isWide) {
                  return GridView.builder(
                    padding: const EdgeInsets.all(16),
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 430,
                          mainAxisSpacing: 12,
                          crossAxisSpacing: 12,
                          childAspectRatio: 1.45,
                        ),
                    itemCount: rules.length,
                    itemBuilder: (_, index) {
                      return _RecurringRuleCard(rule: rules[index]);
                    },
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: rules.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (_, index) {
                    return _RecurringRuleCard(rule: rules[index]);
                  },
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _RecurringRuleCard extends ConsumerWidget {
  final RecurringExpenseRuleModel rule;

  const _RecurringRuleCard({required this.rule});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isActive = rule.status == 'active';
    final isPaused = rule.status == 'paused';
    final isCancelled = rule.status == 'cancelled';

    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    rule.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                _RuleStatusBadge(status: rule.status),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Rs ${rule.estimatedAmount.toStringAsFixed(0)}',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 5,
              children: [
                _MiniInfo(
                  icon: Icons.category_outlined,
                  text: rule.categoryName,
                ),
                _MiniInfo(
                  icon: Icons.repeat,
                  text: '${rule.frequency.label} / ${rule.intervalCount}',
                ),
                _MiniInfo(icon: Icons.payment, text: rule.paymentMode.label),
                _MiniInfo(
                  icon: Icons.calendar_today_outlined,
                  text: 'Next: ${_dateText(rule.nextDueDate)}',
                ),
                _MiniInfo(
                  icon: Icons.notifications_active_outlined,
                  text: '${rule.reminderDaysBefore} day reminder',
                ),
              ],
            ),
            if (rule.note != null && rule.note!.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                rule.note!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (isActive)
                  OutlinedButton.icon(
                    onPressed:
                        () => _updateStatus(context, ref, rule, 'paused'),
                    icon: const Icon(Icons.pause),
                    label: const Text('Pause'),
                  ),
                if (isPaused)
                  FilledButton.icon(
                    onPressed:
                        () => _updateStatus(context, ref, rule, 'active'),
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Activate'),
                  ),
                if (!isCancelled)
                  OutlinedButton.icon(
                    onPressed: () => _confirmCancel(context, ref, rule),
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
    RecurringExpenseRuleModel rule,
    String status,
  ) async {
    final ok = await ref
        .read(recurringExpenseControllerProvider.notifier)
        .updateStatus(rule: rule, status: status);

    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok ? 'Recurring rule updated' : 'Could not update recurring rule',
        ),
      ),
    );
  }

  void _confirmCancel(
    BuildContext context,
    WidgetRef ref,
    RecurringExpenseRuleModel rule,
  ) {
    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Cancel Recurring Rule?'),
          content: Text(
            'This will stop future draft expenses for "${rule.title}".',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Back'),
            ),
            FilledButton(
              onPressed: () async {
                Navigator.pop(dialogContext);

                await _updateStatus(context, ref, rule, 'cancelled');
              },
              child: const Text('Cancel Rule'),
            ),
          ],
        );
      },
    );
  }
}

class _RuleStatusBadge extends StatelessWidget {
  final String status;

  const _RuleStatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    return Chip(
      visualDensity: VisualDensity.compact,
      label: Text(_statusLabel(status)),
    );
  }

  String _statusLabel(String value) {
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
        Text(text, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _EmptyRecurringView extends StatelessWidget {
  const _EmptyRecurringView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.repeat,
                size: 56,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 12),
              Text(
                'No recurring expenses',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              const Text(
                'Create rules for monthly rent, utilities, salaries, internet bills, or other repeating costs.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => context.push('/expenses/recurring/new'),
                icon: const Icon(Icons.add),
                label: const Text('Create Rule'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecurringErrorView extends StatelessWidget {
  final Object error;

  const _RecurringErrorView({required this.error});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            error.toString(),
            textAlign: TextAlign.center,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
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
