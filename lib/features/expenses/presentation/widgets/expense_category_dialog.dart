import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/expense_models.dart';
import '../providers/expense_provider.dart';

Future<ExpenseCategoryModel?> showExpenseCategoryDialog(BuildContext context) {
  return showDialog<ExpenseCategoryModel>(
    context: context,
    builder: (_) => const _ExpenseCategoryDialog(),
  );
}

class _ExpenseCategoryDialog extends ConsumerStatefulWidget {
  const _ExpenseCategoryDialog();

  @override
  ConsumerState<_ExpenseCategoryDialog> createState() =>
      _ExpenseCategoryDialogState();
}

class _ExpenseCategoryDialogState
    extends ConsumerState<_ExpenseCategoryDialog> {
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Category name is required')),
      );
      return;
    }

    setState(() => _saving = true);
    final category = await ref
        .read(expenseCategoryControllerProvider.notifier)
        .createCategory(name: name, description: _descriptionController.text);
    if (!mounted) return;

    if (category == null) {
      final error = ref.read(expenseCategoryControllerProvider).asError?.error;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error?.toString() ?? 'Category not saved')),
      );
      return;
    }

    Navigator.of(context).pop(category);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New Expense Category'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _nameController,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Category Name',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _descriptionController,
            decoration: const InputDecoration(
              labelText: 'Description Optional',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child:
              _saving
                  ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                  : const Text('Save'),
        ),
      ],
    );
  }
}
