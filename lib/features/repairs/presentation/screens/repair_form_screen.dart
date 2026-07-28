import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobileshop_saas/core/entitlements/entitlement_provider.dart';
import 'package:go_router/go_router.dart';
import 'package:mobileshop_saas/features/inventory/presentation/providers/inventory_provider.dart';
import 'package:mobileshop_saas/features/repairs/presentation/providers/repair_provider.dart';

class RepairFormScreen extends ConsumerStatefulWidget {
  const RepairFormScreen({super.key});

  @override
  ConsumerState<RepairFormScreen> createState() => _RepairFormScreenState();
}

class _RepairFormScreenState extends ConsumerState<RepairFormScreen> {
  final _formKey = GlobalKey<FormState>();

  // Customer fields
  final _customerNameController = TextEditingController();
  final _customerPhoneController = TextEditingController();

  // Device fields
  final _deviceBrandController = TextEditingController();
  final _deviceModelController = TextEditingController();
  final _deviceColorController = TextEditingController();
  final _imeiController = TextEditingController();

  // Repair issue
  final _faultDescriptionController = TextEditingController();

  // Estimate fields
  final _estimatedCostController = TextEditingController();
  final _estimateNoteController = TextEditingController();

  DateTime? _estimatedCompletionAt;

  // Product is optional.
  //
  // Agar repair item shop inventory se related hai,
  // user product select kar sakta hai.
  //
  // Agar external customer ka phone hai, product select karna zaroori nahi.
  static const _externalProductValue = '__external_device__';
  String _selectedProductValue = _externalProductValue;

  @override
  void dispose() {
    _customerNameController.dispose();
    _customerPhoneController.dispose();
    _deviceBrandController.dispose();
    _deviceModelController.dispose();
    _deviceColorController.dispose();
    _imeiController.dispose();
    _faultDescriptionController.dispose();
    _estimatedCostController.dispose();
    _estimateNoteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final imeiEnabled =
        ref.watch(featureEntitlementProvider('repairs.imei_linking')).value !=
        false;
    final productsAsync = ref.watch(productsProvider);
    final createState = ref.watch(repairTicketControllerProvider);
    final isSaving = createState.isLoading;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Back',
          onPressed: isSaving ? null : _closeForm,
          icon: const Icon(Icons.arrow_back),
        ),
        title: const Text('Create Repair Ticket'),
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
                  _SectionCard(
                    title: 'Customer Details',
                    subtitle: 'Customer ka basic info yahan save hoga.',
                    child: _ResponsiveFormWrap(
                      children: [
                        _AppTextField(
                          controller: _customerNameController,
                          label: 'Customer name',
                          hint: 'Example: Ali Raza',
                          enabled: !isSaving,
                          validator: _requiredValidator,
                        ),
                        _AppTextField(
                          controller: _customerPhoneController,
                          label: 'Customer phone',
                          hint: 'Example: 03001234567',
                          enabled: !isSaving,
                          keyboardType: TextInputType.phone,
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  _SectionCard(
                    title: 'Device Details',
                    subtitle:
                        'Device ka model, IMEI aur optional inventory product link.',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        productsAsync.when(
                          data: (products) {
                            return DropdownButtonFormField<String>(
                              initialValue: _selectedProductValue,
                              decoration: const InputDecoration(
                                labelText: 'Linked inventory product optional',
                                border: OutlineInputBorder(),
                              ),
                              items: [
                                const DropdownMenuItem(
                                  value: _externalProductValue,
                                  child: Text(
                                    'External device / no product link',
                                  ),
                                ),
                                ...products.map(
                                  (product) => DropdownMenuItem(
                                    value: product.id,
                                    child: Text(
                                      '${product.name} (${product.sku})'
                                      '${product.imeiTracked ? ' • IMEI' : ''}',
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                              ],
                              onChanged:
                                  isSaving
                                      ? null
                                      : (value) {
                                        setState(() {
                                          _selectedProductValue =
                                              value ?? _externalProductValue;
                                        });
                                      },
                            );
                          },
                          loading: () {
                            return const LinearProgressIndicator();
                          },
                          error: (_, _) {
                            return const Text(
                              'Products load nahi ho sake. Ticket phir bhi external device ke tor par create ho sakta hai.',
                            );
                          },
                        ),

                        const SizedBox(height: 16),

                        _ResponsiveFormWrap(
                          children: [
                            _AppTextField(
                              controller: _deviceBrandController,
                              label: 'Device brand',
                              hint: 'Example: Samsung',
                              enabled: !isSaving,
                              validator: _requiredValidator,
                            ),
                            _AppTextField(
                              controller: _deviceModelController,
                              label: 'Device model',
                              hint: 'Example: A15',
                              enabled: !isSaving,
                              validator: _requiredValidator,
                            ),
                            _AppTextField(
                              controller: _deviceColorController,
                              label: 'Device color optional',
                              hint: 'Example: Black',
                              enabled: !isSaving,
                            ),
                            if (imeiEnabled)
                              _AppTextField(
                                controller: _imeiController,
                                label: 'IMEI optional',
                                hint: 'Example: 356789XXXXXXXXX',
                                enabled: !isSaving,
                                keyboardType: TextInputType.number,
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  _SectionCard(
                    title: 'Fault Description',
                    subtitle:
                        'Customer ne device mein jo problem batayi hai woh yahan likho.',
                    child: _AppTextField(
                      controller: _faultDescriptionController,
                      label: 'Fault / issue',
                      hint: 'Example: Charging nahi ho rahi',
                      enabled: !isSaving,
                      maxLines: 4,
                      validator: _requiredValidator,
                    ),
                  ),

                  const SizedBox(height: 16),

                  _SectionCard(
                    title: 'Repair Charge Estimate',
                    subtitle:
                        'Estimated service/labour charge; parts completion par automatically add honge.',
                    child: Column(
                      children: [
                        _ResponsiveFormWrap(
                          children: [
                            _AppTextField(
                              controller: _estimatedCostController,
                              label: 'Estimated service charge optional',
                              hint: 'Example: 500',
                              enabled: !isSaving,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              validator: _optionalAmountValidator,
                            ),
                            _DatePickerField(
                              label: 'Estimated completion optional',
                              value: _estimatedCompletionAt,
                              enabled: !isSaving,
                              onTap: _pickEstimatedDate,
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _AppTextField(
                          controller: _estimateNoteController,
                          label: 'Estimate note optional',
                          hint:
                              'Example: Parts available hone par confirm hoga',
                          enabled: !isSaving,
                          maxLines: 2,
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  FilledButton.icon(
                    onPressed: isSaving ? null : _submit,
                    icon:
                        isSaving
                            ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                            : const Icon(Icons.build_circle_outlined),
                    label: Text(
                      isSaving ? 'Saving...' : 'Create Repair Ticket',
                    ),
                  ),

                  const SizedBox(height: 12),

                  OutlinedButton(
                    onPressed: isSaving ? null : _closeForm,
                    child: const Text('Cancel'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _closeForm() {
    if (context.canPop()) {
      context.pop();
      return;
    }

    context.go('/repairs');
  }

  Future<void> _pickEstimatedDate() async {
    final now = DateTime.now();

    final selected = await showDatePicker(
      context: context,
      initialDate: _estimatedCompletionAt ?? now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );

    if (selected == null) return;

    setState(() {
      _estimatedCompletionAt = selected;
    });
  }

  Future<void> _submit() async {
    final isValid = _formKey.currentState?.validate() ?? false;
    if (!isValid) return;

    final productId =
        _selectedProductValue == _externalProductValue
            ? null
            : _selectedProductValue;

    final estimatedCost = _parseOptionalAmount(_estimatedCostController.text);

    final controller = ref.read(repairTicketControllerProvider.notifier);

    final ticket = await controller.createTicket(
      customerName: _customerNameController.text,
      customerPhone: _customerPhoneController.text,
      productId: productId,
      deviceBrand: _deviceBrandController.text,
      deviceModel: _deviceModelController.text,
      deviceColor: _deviceColorController.text,
      imei: _imeiController.text,
      faultDescription: _faultDescriptionController.text,
      estimatedCost: estimatedCost,
      estimatedCompletionAt: _estimatedCompletionAt,
      estimateNote: _estimateNoteController.text,
    );

    if (!mounted) return;

    if (ticket == null) {
      final state = ref.read(repairTicketControllerProvider);
      final error = state.asError?.error.toString() ?? 'Something went wrong';

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error)));
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Repair ticket ${ticket.ticketNo ?? ''} created')),
    );

    context.go('/repairs');
  }

  String? _requiredValidator(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Required';
    }
    return null;
  }

  String? _optionalAmountValidator(String? value) {
    if (value == null || value.trim().isEmpty) return null;

    final amount = double.tryParse(value.trim());
    if (amount == null) {
      return 'Enter valid amount';
    }

    if (amount < 0) {
      return 'Amount cannot be negative';
    }

    return null;
  }

  double? _parseOptionalAmount(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    return double.tryParse(trimmed);
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;

  const _SectionCard({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }
}

class _ResponsiveFormWrap extends StatelessWidget {
  final List<Widget> children;

  const _ResponsiveFormWrap({required this.children});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 650;
        final itemWidth =
            isWide ? (constraints.maxWidth - 12) / 2 : constraints.maxWidth;

        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final child in children)
              SizedBox(width: itemWidth, child: child),
          ],
        );
      },
    );
  }
}

class _AppTextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String? hint;
  final bool enabled;
  final int maxLines;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;

  const _AppTextField({
    required this.controller,
    required this.label,
    this.hint,
    this.enabled = true,
    this.maxLines = 1,
    this.keyboardType,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      enabled: enabled,
      maxLines: maxLines,
      keyboardType: keyboardType,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        border: const OutlineInputBorder(),
      ),
    );
  }
}

class _DatePickerField extends StatelessWidget {
  final String label;
  final DateTime? value;
  final bool enabled;
  final VoidCallback onTap;

  const _DatePickerField({
    required this.label,
    required this.value,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final selectedDate = value;
    final text =
        selectedDate == null
            ? 'Select date'
            : '${selectedDate.day.toString().padLeft(2, '0')}-'
                '${selectedDate.month.toString().padLeft(2, '0')}-'
                '${selectedDate.year}';

    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(4),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          suffixIcon:
              value == null
                  ? const Icon(Icons.calendar_month_outlined)
                  : const Icon(Icons.event_available_outlined),
        ),
        child: Text(text),
      ),
    );
  }
}
