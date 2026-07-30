import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobileshop_saas/core/constants/app_strings.dart';
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
          tooltip: AppStrings.repairBack,
          onPressed: isSaving ? null : _closeForm,
          icon: const Icon(Icons.arrow_back),
        ),
        title: const Text(AppStrings.repairCreateTicket),
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
                    title: AppStrings.repairCustomerDetails,
                    subtitle: AppStrings.repairCustomerDetailsSubtitle,
                    child: _ResponsiveFormWrap(
                      children: [
                        _AppTextField(
                          controller: _customerNameController,
                          label: AppStrings.repairCustomerName,
                          hint: AppStrings.repairCustomerNameHint,
                          enabled: !isSaving,
                          validator: _requiredValidator,
                        ),
                        _AppTextField(
                          controller: _customerPhoneController,
                          label: AppStrings.repairCustomerPhone,
                          hint: AppStrings.repairCustomerPhoneHint,
                          enabled: !isSaving,
                          keyboardType: TextInputType.phone,
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  _SectionCard(
                    title: AppStrings.repairDeviceDetails,
                    subtitle: AppStrings.repairDeviceDetailsSubtitle,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        productsAsync.when(
                          data: (products) {
                            return DropdownButtonFormField<String>(
                              isExpanded: true,
                              initialValue: _selectedProductValue,
                              decoration: const InputDecoration(
                                labelText: AppStrings.repairLinkedProduct,
                                border: OutlineInputBorder(),
                              ),
                              items: [
                                const DropdownMenuItem(
                                  value: _externalProductValue,
                                  child: Text(AppStrings.repairExternalDevice),
                                ),
                                ...products.map(
                                  (product) => DropdownMenuItem(
                                    value: product.id,
                                    child: Text(
                                      AppStrings.repairProductLabel(
                                        product.name,
                                        product.sku,
                                        product.imeiTracked,
                                      ),
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
                              AppStrings.repairProductsLoadFailed,
                            );
                          },
                        ),

                        const SizedBox(height: 16),

                        _ResponsiveFormWrap(
                          children: [
                            _AppTextField(
                              controller: _deviceBrandController,
                              label: AppStrings.repairDeviceBrand,
                              hint: AppStrings.repairDeviceBrandHint,
                              enabled: !isSaving,
                              validator: _requiredValidator,
                            ),
                            _AppTextField(
                              controller: _deviceModelController,
                              label: AppStrings.repairDeviceModel,
                              hint: AppStrings.repairDeviceModelHint,
                              enabled: !isSaving,
                              validator: _requiredValidator,
                            ),
                            _AppTextField(
                              controller: _deviceColorController,
                              label: AppStrings.repairDeviceColor,
                              hint: AppStrings.repairDeviceColorHint,
                              enabled: !isSaving,
                            ),
                            if (imeiEnabled)
                              _AppTextField(
                                controller: _imeiController,
                                label: AppStrings.repairImeiOptional,
                                hint: AppStrings.repairImeiHint,
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
                    title: AppStrings.repairFaultDescription,
                    subtitle: AppStrings.repairFaultDescriptionSubtitle,
                    child: _AppTextField(
                      controller: _faultDescriptionController,
                      label: AppStrings.repairFaultIssue,
                      hint: AppStrings.repairFaultHint,
                      enabled: !isSaving,
                      maxLines: 4,
                      validator: _requiredValidator,
                    ),
                  ),

                  const SizedBox(height: 16),

                  _SectionCard(
                    title: AppStrings.repairChargeEstimate,
                    subtitle: AppStrings.repairChargeEstimateSubtitle,
                    child: Column(
                      children: [
                        _ResponsiveFormWrap(
                          children: [
                            _AppTextField(
                              controller: _estimatedCostController,
                              label: AppStrings.repairEstimatedServiceCharge,
                              hint: AppStrings.repairEstimatedServiceChargeHint,
                              enabled: !isSaving,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              validator: _optionalAmountValidator,
                            ),
                            _DatePickerField(
                              label: AppStrings.repairEstimatedCompletion,
                              value: _estimatedCompletionAt,
                              enabled: !isSaving,
                              onTap: _pickEstimatedDate,
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _AppTextField(
                          controller: _estimateNoteController,
                          label: AppStrings.repairEstimateNote,
                          hint: AppStrings.repairEstimateNoteHint,
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
                      isSaving
                          ? AppStrings.repairSaving
                          : AppStrings.repairCreateTicket,
                    ),
                  ),

                  const SizedBox(height: 12),

                  OutlinedButton(
                    onPressed: isSaving ? null : _closeForm,
                    child: const Text(AppStrings.repairCancel),
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
      final error =
          state.asError?.error.toString() ??
          AppStrings.repairSomethingWentWrong;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error)));
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppStrings.repairTicketCreated(ticket.ticketNo ?? '')),
      ),
    );

    context.go('/repairs');
  }

  String? _requiredValidator(String? value) {
    if (value == null || value.trim().isEmpty) {
      return AppStrings.repairRequired;
    }
    return null;
  }

  String? _optionalAmountValidator(String? value) {
    if (value == null || value.trim().isEmpty) return null;

    final amount = double.tryParse(value.trim());
    if (amount == null) {
      return AppStrings.repairValidAmount;
    }

    if (amount < 0) {
      return AppStrings.repairAmountNotNegative;
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
            ? AppStrings.repairSelectDate
            : AppStrings.repairDate(selectedDate);

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
