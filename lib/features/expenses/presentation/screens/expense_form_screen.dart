import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobileshop_saas/features/expenses/presentation/providers/expense_provider.dart';

import '../../../../core/entitlements/entitlement_provider.dart';
import '../../data/models/expense_models.dart';

class ExpenseFormScreen extends ConsumerStatefulWidget {
  const ExpenseFormScreen({super.key});

  @override
  ConsumerState<ExpenseFormScreen> createState() => _ExpenseFormScreenState();
}

class _ExpenseFormScreenState extends ConsumerState<ExpenseFormScreen> {
  final _formKey = GlobalKey<FormState>();

  final _titleController = TextEditingController();
  final _amountController = TextEditingController();
  final _payeeController = TextEditingController();
  final _notesController = TextEditingController();
  final _receiptPathController = TextEditingController();

  DateTime _expenseDate = DateTime.now();

  String? _categoryId;
  String? _categoryName;

  ExpensePaymentMode _paymentMode = ExpensePaymentMode.cash;
  ExpenseStatus _status = ExpenseStatus.confirmed;

  static const _noCategoryValue = '__no_category__';

  @override
  void dispose() {
    _titleController.dispose();
    _amountController.dispose();
    _payeeController.dispose();
    _notesController.dispose();
    _receiptPathController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final categoriesAsync = ref.watch(expenseCategoriesProvider);
    final controllerState = ref.watch(expenseControllerProvider);
    final saving = controllerState.isLoading;
    final receiptsEnabled =
        ref.watch(featureEntitlementProvider('expenses.receipts')).value !=
        false;

    return Scaffold(
      appBar: AppBar(title: const Text('Add Expense')),
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
                    title: 'Expense Details',
                    child: _ResponsiveFields(
                      children: [
                        _AppField(
                          controller: _titleController,
                          label: 'Title',
                          hint: 'Rent / Internet / Utility bill',
                          required: true,
                        ),
                        _AmountField(controller: _amountController),
                        _DateField(
                          date: _expenseDate,
                          onTap: saving ? null : _pickExpenseDate,
                        ),
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
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  _SectionCard(
                    title: 'Category',
                    trailing: TextButton.icon(
                      onPressed: saving ? null : _showCreateCategoryDialog,
                      icon: const Icon(Icons.add),
                      label: const Text('New'),
                    ),
                    child: categoriesAsync.when(
                      loading: () => const LinearProgressIndicator(),
                      error: (error, _) => Text(error.toString()),
                      data: (categories) {
                        return DropdownButtonFormField<String>(
                          initialValue: _categoryId ?? _noCategoryValue,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Expense Category',
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
                          ],
                          onChanged:
                              saving
                                  ? null
                                  : (value) {
                                    if (value == null ||
                                        value == _noCategoryValue) {
                                      setState(() {
                                        _categoryId = null;
                                        _categoryName = null;
                                      });
                                      return;
                                    }

                                    final selected = categories.firstWhere(
                                      (category) => category.id == value,
                                    );

                                    setState(() {
                                      _categoryId = selected.id;
                                      _categoryName = selected.name;
                                    });
                                  },
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  _SectionCard(
                    title: 'Optional Information',
                    child: Column(
                      children: [
                        _ResponsiveFields(
                          children: [
                            _AppField(
                              controller: _payeeController,
                              label: 'Payee Optional',
                              hint: 'Landlord / WAPDA / Staff member',
                            ),
                            if (receiptsEnabled)
                              _AppField(
                                controller: _receiptPathController,
                                label: 'Receipt Local Path Optional',
                                hint: 'For now paste file path if available',
                              ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _AppField(
                          controller: _notesController,
                          label: 'Notes Optional',
                          maxLines: 3,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  _SectionCard(
                    title: 'Save Type',
                    child: Column(
                      children: [
                        RadioListTile<ExpenseStatus>(
                          value: ExpenseStatus.confirmed,
                          groupValue: _status,
                          onChanged:
                              saving
                                  ? null
                                  : (value) {
                                    if (value == null) return;
                                    setState(() => _status = value);
                                  },
                          title: const Text('Confirmed Expense'),
                          subtitle: const Text(
                            'Use this when amount is final and paid/recorded.',
                          ),
                        ),
                        RadioListTile<ExpenseStatus>(
                          value: ExpenseStatus.draft,
                          groupValue: _status,
                          onChanged:
                              saving
                                  ? null
                                  : (value) {
                                    if (value == null) return;
                                    setState(() => _status = value);
                                  },
                          title: const Text('Draft Expense'),
                          subtitle: const Text(
                            'Use this when amount is not final yet.',
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
                    label: Text(saving ? 'Saving...' : 'Save Expense'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _pickExpenseDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _expenseDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );

    if (picked == null) return;

    setState(() {
      _expenseDate = DateTime(picked.year, picked.month, picked.day);
    });
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final amount = double.tryParse(_amountController.text.trim());

    if (amount == null || amount < 0) {
      _message('Enter valid amount');
      return;
    }

    final expense = await ref
        .read(expenseControllerProvider.notifier)
        .createExpense(
          title: _titleController.text,
          expenseDate: _expenseDate,
          amount: amount,
          categoryId: _categoryId,
          categoryName: _categoryName,
          paymentMode: _paymentMode,
          payee: _payeeController.text,
          notes: _notesController.text,
          localReceiptPath: _receiptPathController.text,
          status: _status,
        );

    if (!mounted) return;

    if (expense == null) {
      final error = ref.read(expenseControllerProvider).asError?.error;
      _message(error?.toString() ?? 'Expense not saved');
      return;
    }

    _message('Expense saved');
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/expenses');
    }
  }

  void _showCreateCategoryDialog() {
    final nameController = TextEditingController();
    final descriptionController = TextEditingController();

    showDialog(
      context: context,
      builder: (_) {
        final categoryState = ref.watch(expenseCategoryControllerProvider);
        final saving = categoryState.isLoading;

        return AlertDialog(
          title: const Text('New Expense Category'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Category Name',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: descriptionController,
                decoration: const InputDecoration(
                  labelText: 'Description Optional',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed:
                  saving
                      ? null
                      : () {
                        nameController.dispose();
                        descriptionController.dispose();
                        Navigator.pop(context);
                      },
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed:
                  saving
                      ? null
                      : () async {
                        final name = nameController.text.trim();

                        if (name.isEmpty) {
                          _message('Category name required');
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
                              ref
                                  .read(expenseCategoryControllerProvider)
                                  .asError
                                  ?.error;
                          _message(error?.toString() ?? 'Category not saved');
                          return;
                        }

                        setState(() {
                          _categoryId = category.id;
                          _categoryName = category.name;
                        });

                        nameController.dispose();
                        descriptionController.dispose();

                        Navigator.pop(context);
                      },
              child:
                  saving
                      ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                      : const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  void _message(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;
  final Widget? trailing;

  const _SectionCard({required this.title, required this.child, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _ResponsiveFields extends StatelessWidget {
  final List<Widget> children;

  const _ResponsiveFields({required this.children});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (_, constraints) {
        final isWide = constraints.maxWidth >= 680;
        final itemWidth =
            isWide ? (constraints.maxWidth - 12) / 2 : constraints.maxWidth;

        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children:
              children.map((child) {
                return SizedBox(width: itemWidth, child: child);
              }).toList(),
        );
      },
    );
  }
}

class _AppField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String? hint;
  final bool required;
  final int maxLines;

  const _AppField({
    required this.controller,
    required this.label,
    this.hint,
    this.required = false,
    this.maxLines = 1,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      validator:
          required
              ? (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Required';
                }

                return null;
              }
              : null,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        border: const OutlineInputBorder(),
      ),
    );
  }
}

class _AmountField extends StatelessWidget {
  final TextEditingController controller;

  const _AmountField({required this.controller});

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      validator: (value) {
        final amount = double.tryParse(value?.trim() ?? '');

        if (amount == null) {
          return 'Required';
        }

        if (amount < 0) {
          return 'Amount cannot be negative';
        }

        return null;
      },
      decoration: const InputDecoration(
        labelText: 'Amount',
        hintText: '0',
        prefixText: 'Rs ',
        border: OutlineInputBorder(),
      ),
    );
  }
}

class _DateField extends StatelessWidget {
  final DateTime date;
  final VoidCallback? onTap;

  const _DateField({required this.date, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: InputDecorator(
        decoration: const InputDecoration(
          labelText: 'Expense Date',
          border: OutlineInputBorder(),
          suffixIcon: Icon(Icons.date_range),
        ),
        child: Text(_dateText(date)),
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
