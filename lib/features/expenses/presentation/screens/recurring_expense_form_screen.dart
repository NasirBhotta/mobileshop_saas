import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobileshop_saas/features/expenses/presentation/providers/expense_provider.dart';

import '../../data/models/expense_models.dart';

class RecurringExpenseFormScreen extends ConsumerStatefulWidget {
  const RecurringExpenseFormScreen({super.key});

  @override
  ConsumerState<RecurringExpenseFormScreen> createState() =>
      _RecurringExpenseFormScreenState();
}

class _RecurringExpenseFormScreenState
    extends ConsumerState<RecurringExpenseFormScreen> {
  final _formKey = GlobalKey<FormState>();

  final _titleController = TextEditingController();
  final _amountController = TextEditingController();
  final _payeeController = TextEditingController();
  final _noteController = TextEditingController();
  final _intervalController = TextEditingController(text: '1');
  final _reminderController = TextEditingController(text: '3');
  final _newCategoryController = TextEditingController();

  String? _selectedCategoryId;
  String? _selectedCategoryName;

  ExpensePaymentMode _paymentMode = ExpensePaymentMode.cash;
  RecurringExpenseFrequency _frequency = RecurringExpenseFrequency.monthly;

  DateTime _startDate = DateTime.now();
  DateTime? _endDate;

  static const _addCategoryValue = '__add_new_category__';
  static const _noCategoryValue = '__no_category__';

  @override
  void dispose() {
    _titleController.dispose();
    _amountController.dispose();
    _payeeController.dispose();
    _noteController.dispose();
    _intervalController.dispose();
    _reminderController.dispose();
    _newCategoryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final categoriesAsync = ref.watch(expenseCategoriesProvider);
    final ruleState = ref.watch(recurringExpenseControllerProvider);
    final categoryState = ref.watch(expenseCategoryControllerProvider);

    final saving = ruleState.isLoading || categoryState.isLoading;

    return Scaffold(
      appBar: AppBar(title: const Text('Create Recurring Expense')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _SectionCard(
                    title: 'Basic Details',
                    child: Column(
                      children: [
                        _ResponsiveWrap(
                          children: [
                            TextFormField(
                              controller: _titleController,
                              decoration: const InputDecoration(
                                labelText: 'Title',
                                hintText: 'Monthly rent, internet bill...',
                                border: OutlineInputBorder(),
                              ),
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'Title is required';
                                }

                                return null;
                              },
                            ),
                            TextFormField(
                              controller: _amountController,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: const InputDecoration(
                                labelText: 'Estimated Amount',
                                prefixText: 'Rs ',
                                border: OutlineInputBorder(),
                              ),
                              validator: (value) {
                                final amount = double.tryParse(
                                  value?.trim() ?? '',
                                );

                                if (amount == null) {
                                  return 'Enter valid amount';
                                }

                                if (amount < 0) {
                                  return 'Amount cannot be negative';
                                }

                                return null;
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        categoriesAsync.when(
                          loading: () => const LinearProgressIndicator(),
                          error:
                              (error, _) => Text(
                                error.toString(),
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.error,
                                ),
                              ),
                          data: (categories) {
                            return DropdownButtonFormField<String>(
                              initialValue:
                                  _selectedCategoryId ?? _noCategoryValue,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                labelText: 'Category',
                                border: OutlineInputBorder(),
                              ),
                              items: [
                                const DropdownMenuItem(
                                  value: _noCategoryValue,
                                  child: Text('No Category'),
                                ),
                                for (final category in categories)
                                  DropdownMenuItem(
                                    value: category.id,
                                    child: Text(category.name),
                                  ),
                                const DropdownMenuItem(
                                  value: _addCategoryValue,
                                  child: Text('+ Add New Category'),
                                ),
                              ],
                              onChanged:
                                  saving
                                      ? null
                                      : (value) async {
                                        if (value == null) return;

                                        if (value == _addCategoryValue) {
                                          await _showAddCategoryDialog();
                                          return;
                                        }

                                        if (value == _noCategoryValue) {
                                          setState(() {
                                            _selectedCategoryId = null;
                                            _selectedCategoryName = null;
                                          });
                                          return;
                                        }

                                        final category = categories.firstWhere(
                                          (item) => item.id == value,
                                        );

                                        setState(() {
                                          _selectedCategoryId = category.id;
                                          _selectedCategoryName = category.name;
                                        });
                                      },
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  _SectionCard(
                    title: 'Schedule',
                    child: Column(
                      children: [
                        _ResponsiveWrap(
                          children: [
                            DropdownButtonFormField<RecurringExpenseFrequency>(
                              initialValue: _frequency,
                              decoration: const InputDecoration(
                                labelText: 'Frequency',
                                border: OutlineInputBorder(),
                              ),
                              items:
                                  RecurringExpenseFrequency.values.map((freq) {
                                    return DropdownMenuItem(
                                      value: freq,
                                      child: Text(freq.label),
                                    );
                                  }).toList(),
                              onChanged:
                                  saving
                                      ? null
                                      : (value) {
                                        if (value == null) return;
                                        setState(() => _frequency = value);
                                      },
                            ),
                            TextFormField(
                              controller: _intervalController,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'Repeat Every',
                                hintText: '1',
                                border: OutlineInputBorder(),
                              ),
                              validator: (value) {
                                final interval = int.tryParse(
                                  value?.trim() ?? '',
                                );

                                if (interval == null || interval <= 0) {
                                  return 'Enter valid interval';
                                }

                                return null;
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _ResponsiveWrap(
                          children: [
                            _DateField(
                              label: 'Start Date',
                              value: _startDate,
                              onTap: saving ? null : _pickStartDate,
                            ),
                            _DateField(
                              label: 'End Date Optional',
                              value: _endDate,
                              placeholder: 'No end date',
                              onTap: saving ? null : _pickEndDate,
                              onClear:
                                  _endDate == null
                                      ? null
                                      : () {
                                        setState(() => _endDate = null);
                                      },
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _reminderController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Reminder Days Before',
                            hintText: '3',
                            border: OutlineInputBorder(),
                          ),
                          validator: (value) {
                            final days = int.tryParse(value?.trim() ?? '');

                            if (days == null || days < 0) {
                              return 'Enter valid reminder days';
                            }

                            return null;
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  _SectionCard(
                    title: 'Optional Information',
                    child: Column(
                      children: [
                        _ResponsiveWrap(
                          children: [
                            DropdownButtonFormField<ExpensePaymentMode>(
                              initialValue: _paymentMode,
                              decoration: const InputDecoration(
                                labelText: 'Payment Mode',
                                border: OutlineInputBorder(),
                              ),
                              items:
                                  ExpensePaymentMode.values.map((mode) {
                                    return DropdownMenuItem(
                                      value: mode,
                                      child: Text(mode.label),
                                    );
                                  }).toList(),
                              onChanged:
                                  saving
                                      ? null
                                      : (value) {
                                        if (value == null) return;
                                        setState(() => _paymentMode = value);
                                      },
                            ),
                            TextFormField(
                              controller: _payeeController,
                              decoration: const InputDecoration(
                                labelText: 'Payee optional',
                                hintText: 'Landlord, WAPDA, ISP...',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _noteController,
                          maxLines: 3,
                          decoration: const InputDecoration(
                            labelText: 'Note optional',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: saving ? null : _submit,
                    icon:
                        saving
                            ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                            : const Icon(Icons.save),
                    label: Text(saving ? 'Saving...' : 'Create Recurring Rule'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _pickStartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
    );

    if (picked == null) return;

    setState(() {
      _startDate = DateTime(picked.year, picked.month, picked.day);

      if (_endDate != null && _endDate!.isBefore(_startDate)) {
        _endDate = null;
      }
    });
  }

  Future<void> _pickEndDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _endDate ?? _startDate,
      firstDate: _startDate,
      lastDate: DateTime.now().add(const Duration(days: 365 * 10)),
    );

    if (picked == null) return;

    setState(() {
      _endDate = DateTime(picked.year, picked.month, picked.day);
    });
  }

  Future<void> _showAddCategoryDialog() async {
    _newCategoryController.clear();
    final descriptionController = TextEditingController();

    try {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Add Expense Category'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _newCategoryController,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Category name',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: descriptionController,
                decoration: const InputDecoration(
                  labelText: 'Description optional',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                final name = _newCategoryController.text.trim();

                if (name.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Category name is required')),
                  );
                  return;
                }

                final category = await ref
                    .read(expenseCategoryControllerProvider.notifier)
                    .createCategory(
                      name: name,
                      description: descriptionController.text,
                    );

                if (!mounted) return;

                if (category == null) {
                  final error =
                      ref.read(expenseCategoryControllerProvider).asError;

                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        error?.error.toString() ?? 'Category not created',
                      ),
                    ),
                  );
                  return;
                }

                setState(() {
                  _selectedCategoryId = category.id;
                  _selectedCategoryName = category.name;
                });

                if (dialogContext.mounted) {
                  Navigator.of(dialogContext).pop();
                }
              },
              child: const Text('Save'),
            ),
          ],
        );
        },
      );
    } finally {
      descriptionController.dispose();
    }
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final amount = double.parse(_amountController.text.trim());
    final interval = int.parse(_intervalController.text.trim());
    final reminderDays = int.parse(_reminderController.text.trim());

    if (_endDate != null && _endDate!.isBefore(_startDate)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('End date cannot be before start date')),
      );
      return;
    }

    final categoryName = _selectedCategoryName ?? 'Other';

    final rule = await ref
        .read(recurringExpenseControllerProvider.notifier)
        .createRule(
          title: _titleController.text,
          categoryName: categoryName,
          categoryId: _selectedCategoryId,
          estimatedAmount: amount,
          paymentMode: _paymentMode,
          payee: _payeeController.text,
          note: _noteController.text,
          frequency: _frequency,
          intervalCount: interval,
          startDate: _startDate,
          endDate: _endDate,
          reminderDaysBefore: reminderDays,
        );

    if (!mounted) return;

    if (rule == null) {
      final error = ref.read(recurringExpenseControllerProvider).asError;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error?.error.toString() ?? 'Recurring rule not saved'),
        ),
      );

      return;
    }

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Recurring rule created')));

    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/expenses/recurring');
    }
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;

  const _SectionCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _ResponsiveWrap extends StatelessWidget {
  final List<Widget> children;

  const _ResponsiveWrap({required this.children});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (_, constraints) {
        final itemWidth =
            constraints.maxWidth >= 700
                ? (constraints.maxWidth - 12) / 2
                : constraints.maxWidth;

        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children:
              children
                  .map((child) => SizedBox(width: itemWidth, child: child))
                  .toList(),
        );
      },
    );
  }
}

class _DateField extends StatelessWidget {
  final String label;
  final DateTime? value;
  final String? placeholder;
  final VoidCallback? onTap;
  final VoidCallback? onClear;

  const _DateField({
    required this.label,
    required this.value,
    this.placeholder,
    required this.onTap,
    this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          suffixIcon:
              onClear == null
                  ? const Icon(Icons.date_range)
                  : IconButton(
                    onPressed: onClear,
                    icon: const Icon(Icons.close),
                  ),
        ),
        child: Text(
          value == null ? (placeholder ?? 'Select date') : _dateText(value!),
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
