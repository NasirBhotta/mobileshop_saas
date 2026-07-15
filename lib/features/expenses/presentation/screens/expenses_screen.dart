import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobileshop_saas/features/expenses/presentation/providers/expense_provider.dart';

import '../../../../core/entitlements/entitlement_provider.dart';
import '../../data/models/expense_models.dart';

class ExpensesScreen extends ConsumerWidget {
  const ExpensesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final expensesAsync = ref.watch(expensesProvider);
    final syncState = ref.watch(expenseSyncControllerProvider);
    final reportingEnabled =
        ref.watch(featureEntitlementProvider('expenses.reporting')).value !=
        false;
    final recurringEnabled =
        ref.watch(featureEntitlementProvider('expenses.recurring')).value !=
        false;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Expenses'),
        actions: [
          if (reportingEnabled)
            IconButton(
              tooltip: 'Report',
              onPressed: () => context.push('/expenses/report'),
              icon: const Icon(Icons.analytics_outlined),
            ),
          if (recurringEnabled)
            IconButton(
              tooltip: 'Recurring Expenses',
              onPressed: () => context.push('/expenses/recurring'),
              icon: const Icon(Icons.repeat),
            ),
          IconButton(
            tooltip: 'Sync',
            onPressed:
                syncState.isLoading
                    ? null
                    : () async {
                      await ref
                          .read(expenseSyncControllerProvider.notifier)
                          .sync();

                      if (!context.mounted) return;

                      final error =
                          ref.read(expenseSyncControllerProvider).asError;

                      if (error != null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(error.error.toString())),
                        );
                        return;
                      }

                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Expenses synced')),
                      );
                    },
            icon:
                syncState.isLoading
                    ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                    : const Icon(Icons.sync),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/expenses/new'),
        icon: const Icon(Icons.add),
        label: const Text('Add Expense'),
      ),
      body: Column(
        children: [
          const _ExpenseFilters(),
          const Divider(height: 1),
          Expanded(
            child: expensesAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => _ExpenseErrorView(error: error),
              data: (expenses) {
                if (expenses.isEmpty) {
                  return const _EmptyExpensesView();
                }

                return RefreshIndicator(
                  onRefresh: () async {
                    ref.invalidate(expensesProvider);
                    ref.invalidate(expenseReportProvider);
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
                                childAspectRatio: 1.55,
                              ),
                          itemCount: expenses.length,
                          itemBuilder: (_, index) {
                            final expense = expenses[index];
                            return _ExpenseCard(
                              key: ValueKey(expense.id),
                              expense: expense,
                            );
                          },
                        );
                      }

                      return ListView.separated(
                        padding: const EdgeInsets.all(12),
                        itemCount: expenses.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (_, index) {
                          final expense = expenses[index];
                          return _ExpenseCard(
                            key: ValueKey(expense.id),
                            expense: expense,
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
    );
  }
}

class _ExpenseFilters extends ConsumerWidget {
  const _ExpenseFilters();

  static const _allCategoryValue = '__all_categories__';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final range = ref.watch(expenseDateRangeProvider);
    final selectedStatus = ref.watch(selectedExpenseStatusProvider);
    final selectedSource = ref.watch(selectedExpenseSourceProvider);
    final selectedCategoryId = ref.watch(selectedExpenseCategoryProvider);
    final categoriesAsync = ref.watch(expenseCategoriesProvider);

    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth >= 760;

                final dateRangeButton = _DateRangeButton(
                  from: range.from,
                  to: range.to,
                  onTap: () => _pickDateRange(context, ref, range),
                );

                final categoryDropdown = categoriesAsync.when(
                  loading: () => const LinearProgressIndicator(),
                  error: (_, _) => const SizedBox.shrink(),
                  data: (categories) {
                    return DropdownButtonFormField<String>(
                      initialValue: selectedCategoryId ?? _allCategoryValue,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Category',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: [
                        const DropdownMenuItem(
                          value: _allCategoryValue,
                          child: Text('All Categories'),
                        ),
                        for (final category in categories)
                          DropdownMenuItem(
                            value: category.id,
                            child: Text(category.name),
                          ),
                      ],
                      onChanged: (value) {
                        ref
                            .read(selectedExpenseCategoryProvider.notifier)
                            .state = value == _allCategoryValue ? null : value;

                        ref.invalidate(expensesProvider);
                        ref.invalidate(expenseReportProvider);
                      },
                    );
                  },
                );

                if (isWide) {
                  return Row(
                    children: [
                      Expanded(child: dateRangeButton),
                      const SizedBox(width: 12),
                      Expanded(child: categoryDropdown),
                    ],
                  );
                }

                return Column(
                  children: [
                    dateRangeButton,
                    const SizedBox(height: 10),
                    categoryDropdown,
                  ],
                );
              },
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 42,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  _FilterChip(
                    label: 'All Status',
                    selected: selectedStatus == null,
                    onTap: () {
                      ref.read(selectedExpenseStatusProvider.notifier).state =
                          null;
                      ref.invalidate(expensesProvider);
                    },
                  ),
                  for (final status in ExpenseStatus.values)
                    _FilterChip(
                      label: status.label,
                      selected: selectedStatus == status,
                      onTap: () {
                        ref.read(selectedExpenseStatusProvider.notifier).state =
                            status;
                        ref.invalidate(expensesProvider);
                      },
                    ),
                  const SizedBox(width: 10),
                  _FilterChip(
                    label: 'All Sources',
                    selected: selectedSource == null,
                    onTap: () {
                      ref.read(selectedExpenseSourceProvider.notifier).state =
                          null;
                      ref.invalidate(expensesProvider);
                    },
                  ),
                  for (final source in ExpenseSource.values)
                    _FilterChip(
                      label: source.label,
                      selected: selectedSource == source,
                      onTap: () {
                        ref.read(selectedExpenseSourceProvider.notifier).state =
                            source;
                        ref.invalidate(expensesProvider);
                      },
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickDateRange(
    BuildContext context,
    WidgetRef ref,
    ExpenseDateRange current,
  ) async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: DateTimeRange(start: current.from, end: current.to),
    );

    if (picked == null) return;

    ref.read(expenseDateRangeProvider.notifier).state = ExpenseDateRange(
      from: DateTime(picked.start.year, picked.start.month, picked.start.day),
      to: DateTime(picked.end.year, picked.end.month, picked.end.day),
    );

    ref.invalidate(expensesProvider);
    ref.invalidate(expenseReportProvider);
  }
}

class _DateRangeButton extends StatelessWidget {
  final DateTime from;
  final DateTime to;
  final VoidCallback onTap;

  const _DateRangeButton({
    required this.from,
    required this.to,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: InputDecorator(
        decoration: const InputDecoration(
          labelText: 'Date Range',
          border: OutlineInputBorder(),
          isDense: true,
          suffixIcon: Icon(Icons.date_range),
        ),
        child: Text('${_dateText(from)} - ${_dateText(to)}'),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        selected: selected,
        label: Text(label),
        onSelected: (_) => onTap(),
      ),
    );
  }
}

class _ExpenseCard extends ConsumerWidget {
  final ExpenseModel expense;

  const _ExpenseCard({super.key, required this.expense});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDraft = expense.status == ExpenseStatus.draft;
    final isVoided = expense.status == ExpenseStatus.voided;

    return Card(
      elevation: 0,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _showExpenseDetails(context, ref, expense),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      expense.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  _ExpenseStatusBadge(status: expense.status),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Rs ${expense.amount.toStringAsFixed(0)}',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  _MiniInfo(
                    icon: Icons.category_outlined,
                    text: expense.categoryName ?? 'Uncategorized',
                  ),
                  _MiniInfo(
                    icon: Icons.payment,
                    text: expense.paymentMode.label,
                  ),
                  _MiniInfo(
                    icon: Icons.calendar_today_outlined,
                    text: _dateText(expense.expenseDate),
                  ),
                  if (expense.source == ExpenseSource.recurring)
                    const _MiniInfo(icon: Icons.repeat, text: 'Recurring'),
                  if (expense.receiptPhotoPath != null ||
                      expense.localReceiptPath != null)
                    const _MiniInfo(
                      icon: Icons.receipt_long_outlined,
                      text: 'Receipt',
                    ),
                ],
              ),
              if (expense.notes != null &&
                  expense.notes!.trim().isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  expense.notes!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              const Spacer(),
              Row(
                children: [
                  if (isDraft)
                    Expanded(
                      child: FilledButton(
                        onPressed:
                            () => _showConfirmDialog(context, ref, expense),
                        child: const Text('Confirm'),
                      ),
                    ),
                  if (isDraft) const SizedBox(width: 8),
                  if (!isVoided)
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _confirmVoid(context, ref, expense),
                        child: const Text('Void'),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showExpenseDetails(
    BuildContext context,
    WidgetRef ref,
    ExpenseModel expense,
  ) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (_) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  expense.title,
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                _DetailRow(
                  label: 'Amount',
                  value: 'Rs ${expense.amount.toStringAsFixed(0)}',
                ),
                _DetailRow(
                  label: 'Date',
                  value: _dateText(expense.expenseDate),
                ),
                _DetailRow(
                  label: 'Category',
                  value: expense.categoryName ?? '-',
                ),
                _DetailRow(label: 'Payment', value: expense.paymentMode.label),
                _DetailRow(label: 'Status', value: expense.status.label),
                _DetailRow(label: 'Source', value: expense.source.label),
                if (expense.payee != null)
                  _DetailRow(label: 'Payee', value: expense.payee!),
                if (expense.notes != null)
                  _DetailRow(label: 'Notes', value: expense.notes!),
                if (expense.receiptPhotoPath != null)
                  _DetailRow(
                    label: 'Receipt',
                    value: expense.receiptPhotoPath!,
                  ),
                const SizedBox(height: 12),
                if (expense.status == ExpenseStatus.draft)
                  FilledButton(
                    onPressed: () {
                      Navigator.pop(context);
                      _showConfirmDialog(context, ref, expense);
                    },
                    child: const Text('Confirm Draft Expense'),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showConfirmDialog(
    BuildContext context,
    WidgetRef ref,
    ExpenseModel expense,
  ) {
    final amountController = TextEditingController(
      text: expense.amount.toStringAsFixed(0),
    );

    showDialog(
      context: context,
      builder: (_) {
        return AlertDialog(
          title: const Text('Confirm Expense'),
          content: TextField(
            controller: amountController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Actual Amount',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                amountController.dispose();
                Navigator.pop(context);
              },
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                final amount = double.tryParse(amountController.text.trim());

                if (amount == null || amount < 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Enter valid amount')),
                  );
                  return;
                }

                final ok = await ref
                    .read(expenseControllerProvider.notifier)
                    .confirmExpense(expense: expense, actualAmount: amount);

                amountController.dispose();

                if (!context.mounted) return;

                Navigator.pop(context);

                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      ok ? 'Expense confirmed' : 'Expense not confirmed',
                    ),
                  ),
                );
              },
              child: const Text('Confirm'),
            ),
          ],
        );
      },
    );
  }

  void _confirmVoid(BuildContext context, WidgetRef ref, ExpenseModel expense) {
    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Void Expense?'),
          content: const Text(
            'This will exclude the expense from confirmed expense reports.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                Navigator.pop(dialogContext);

                final ok = await ref
                    .read(expenseControllerProvider.notifier)
                    .voidExpense(expense);

                if (!context.mounted) return;

                final error = ref.read(expenseControllerProvider).asError;

                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      ok
                          ? 'Expense voided'
                          : error?.error.toString() ?? 'Expense not voided',
                    ),
                  ),
                );
              },
              child: const Text('Void'),
            ),
          ],
        );
      },
    );
  }
}

class _ExpenseStatusBadge extends StatelessWidget {
  final ExpenseStatus status;

  const _ExpenseStatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    return Chip(
      visualDensity: VisualDensity.compact,
      label: Text(status.label),
    );
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

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Text(
              label,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          Expanded(
            child: Text(value, style: Theme.of(context).textTheme.bodySmall),
          ),
        ],
      ),
    );
  }
}

class _EmptyExpensesView extends StatelessWidget {
  const _EmptyExpensesView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.receipt_long_outlined,
                size: 54,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 12),
              Text(
                'No expenses found',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              const Text(
                'Add rent, utilities, salaries, internet bills, transport, and other shop expenses here.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => context.push('/expenses/new'),
                icon: const Icon(Icons.add),
                label: const Text('Add Expense'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ExpenseErrorView extends StatelessWidget {
  final Object error;

  const _ExpenseErrorView({required this.error});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(error.toString(), textAlign: TextAlign.center),
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
