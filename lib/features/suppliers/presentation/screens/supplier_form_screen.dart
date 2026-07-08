import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobileshop_saas/features/suppliers/presentation/providers/procurement_provider.dart';

class SupplierFormScreen extends ConsumerStatefulWidget {
  const SupplierFormScreen({super.key});

  @override
  ConsumerState<SupplierFormScreen> createState() => _SupplierFormScreenState();
}

class _SupplierFormScreenState extends ConsumerState<SupplierFormScreen> {
  final _formKey = GlobalKey<FormState>();

  final _name = TextEditingController();
  final _contact = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _address = TextEditingController();
  final _city = TextEditingController();
  final _terms = TextEditingController();
  final _notes = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _contact.dispose();
    _phone.dispose();
    _email.dispose();
    _address.dispose();
    _city.dispose();
    _terms.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(supplierControllerProvider);
    final saving = state.isLoading;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Back to suppliers',
          onPressed: saving ? null : () => context.go('/suppliers'),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: const Text('Add Supplier'),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 850),
            child: Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _WrapFields(
                    children: [
                      _Field(
                        controller: _name,
                        label: 'Supplier name',
                        required: true,
                      ),
                      _Field(controller: _contact, label: 'Contact person'),
                      _Field(controller: _phone, label: 'Phone'),
                      _Field(controller: _email, label: 'Email'),
                      _Field(controller: _city, label: 'City'),
                      _Field(
                        controller: _terms,
                        label: 'Payment terms',
                        hint: 'Net 30 / COD',
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _Field(
                    controller: _address,
                    label: 'Physical address',
                    maxLines: 3,
                  ),
                  const SizedBox(height: 12),
                  _Field(controller: _notes, label: 'Notes', maxLines: 3),
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
                    label: Text(saving ? 'Saving...' : 'Save Supplier'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final supplier = await ref
        .read(supplierControllerProvider.notifier)
        .createSupplier(
          name: _name.text,
          contactPerson: _contact.text,
          phone: _phone.text,
          email: _email.text,
          address: _address.text,
          city: _city.text,
          paymentTerms: _terms.text,
          notes: _notes.text,
        );

    if (!mounted) return;

    if (supplier == null) {
      final error =
          ref.read(supplierControllerProvider).asError?.error.toString();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error ?? 'Supplier not saved')));
      return;
    }

    context.go('/suppliers');
  }
}

class _WrapFields extends StatelessWidget {
  final List<Widget> children;

  const _WrapFields({required this.children});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (_, constraints) {
        final width =
            constraints.maxWidth >= 650
                ? (constraints.maxWidth - 12) / 2
                : constraints.maxWidth;

        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children:
              children.map((e) => SizedBox(width: width, child: e)).toList(),
        );
      },
    );
  }
}

class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String? hint;
  final bool required;
  final int maxLines;

  const _Field({
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
              ? (v) => v == null || v.trim().isEmpty ? 'Required' : null
              : null,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        border: const OutlineInputBorder(),
      ),
    );
  }
}
