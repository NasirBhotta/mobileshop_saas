import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
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

  // Device Photos
  final List<String> _photoPaths = [];
  bool _isPickingPhoto = false;

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
                              initialValue: _selectedProductValue,
                              decoration: const InputDecoration(
                                labelText: AppStrings.repairLinkedProduct,
                                border: OutlineInputBorder(),
                              ),
                              items: [
                                const DropdownMenuItem<String>(
                                  value: _externalProductValue,
                                  child: Text(AppStrings.repairExternalDevice),
                                ),
                                ...products.map(
                                  (product) => DropdownMenuItem<String>(
                                    value: product.id,
                                    child: Text(
                                      '${product.name} (${product.sku})',
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                              ],
                              onChanged:
                                  isSaving
                                      ? null
                                      : (value) {
                                        if (value == null) return;
                                        setState(() {
                                          _selectedProductValue = value;
                                        });
                                      },
                            );
                          },
                          loading:
                              () => const Center(
                                child: Padding(
                                  padding: EdgeInsets.all(8.0),
                                  child: CircularProgressIndicator(),
                                ),
                              ),
                          error:
                              (_, _) => const Text(
                                AppStrings.repairProductsLoadFailed,
                                style: TextStyle(color: Colors.red),
                              ),
                        ),
                        const SizedBox(height: 12),
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
                    title: AppStrings.repairDevicePhotos,
                    subtitle: AppStrings.repairDevicePhotosSubtitle,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 12,
                          runSpacing: 8,
                          children: [
                            OutlinedButton.icon(
                              onPressed:
                                  (isSaving || _isPickingPhoto)
                                      ? null
                                      : _pickFromCamera,
                              icon: const Icon(
                                Icons.camera_alt_outlined,
                                size: 18,
                              ),
                              label: const Text(AppStrings.repairTakePhoto),
                            ),
                            OutlinedButton.icon(
                              onPressed:
                                  (isSaving || _isPickingPhoto)
                                      ? null
                                      : _pickFromGallery,
                              icon: const Icon(
                                Icons.photo_library_outlined,
                                size: 18,
                              ),
                              label: const Text(AppStrings.repairPickGallery),
                            ),
                          ],
                        ),
                        if (_photoPaths.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          SizedBox(
                            height: 100,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              itemCount: _photoPaths.length,
                              separatorBuilder:
                                  (_, _) => const SizedBox(width: 10),
                              itemBuilder: (context, index) {
                                final path = _photoPaths[index];
                                return Stack(
                                  children: [
                                    GestureDetector(
                                      onTap: () => _previewPhoto(path),
                                      child: Container(
                                        width: 100,
                                        height: 100,
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                          border: Border.all(
                                            color:
                                                Theme.of(context).dividerColor,
                                          ),
                                          image: DecorationImage(
                                            image: FileImage(File(path)),
                                            fit: BoxFit.cover,
                                          ),
                                        ),
                                      ),
                                    ),
                                    Positioned(
                                      top: 4,
                                      right: 4,
                                      child: GestureDetector(
                                        onTap:
                                            isSaving
                                                ? null
                                                : () => _removePhoto(index),
                                        child: Container(
                                          padding: const EdgeInsets.all(3),
                                          decoration: BoxDecoration(
                                            color: Colors.black.withAlpha(180),
                                            shape: BoxShape.circle,
                                          ),
                                          child: const Icon(
                                            Icons.close,
                                            size: 14,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                          ),
                        ],
                      ],
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

  Future<void> _saveLocalImageFiles(List<String> paths) async {
    final appDir = await getApplicationDocumentsDirectory();
    final photosDir = Directory(p.join(appDir.path, 'repairs', 'photos'));
    if (!photosDir.existsSync()) {
      photosDir.createSync(recursive: true);
    }
    for (final srcPath in paths) {
      if (srcPath.trim().isEmpty) continue;
      final srcFile = File(srcPath);
      if (!srcFile.existsSync()) continue;
      final ext =
          p.extension(srcPath).isNotEmpty ? p.extension(srcPath) : '.jpg';
      final fileName = 'repair_local_${const Uuid().v4()}$ext';
      final savedFile = await srcFile.copy(p.join(photosDir.path, fileName));
      _photoPaths.add(savedFile.path);
    }
    if (mounted) setState(() {});
  }

  Future<void> _pickFromCamera() async {
    setState(() => _isPickingPhoto = true);
    try {
      if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Camera device mobile phones aur tablets par dastiyab hai. Desktop par pictures add karne ke liye Gallery use karein.',
              ),
            ),
          );
        }
        return;
      }

      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 75,
        maxWidth: 1280,
        maxHeight: 1280,
      );
      if (picked != null) {
        await _saveLocalImageFiles([picked.path]);
      }
    } catch (e) {
      debugPrint('Camera pick error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Camera error: ${e.toString()}'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isPickingPhoto = false);
    }
  }

  Future<void> _pickFromGallery() async {
    setState(() => _isPickingPhoto = true);
    try {
      if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        final result = await FilePicker.pickFiles(
          type: FileType.image,
          allowMultiple: true,
        );
        if (result != null && result.files.isNotEmpty) {
          final validPaths =
              result.files.map((f) => f.path).whereType<String>().toList();
          await _saveLocalImageFiles(validPaths);
        }
      } else {
        try {
          final picker = ImagePicker();
          final pickedList = await picker.pickMultiImage(
            imageQuality: 75,
            maxWidth: 1280,
            maxHeight: 1280,
          );
          if (pickedList.isNotEmpty) {
            await _saveLocalImageFiles(pickedList.map((p) => p.path).toList());
          }
        } catch (_) {
          final result = await FilePicker.pickFiles(
            type: FileType.image,
            allowMultiple: true,
          );
          if (result != null && result.files.isNotEmpty) {
            final validPaths =
                result.files.map((f) => f.path).whereType<String>().toList();
            await _saveLocalImageFiles(validPaths);
          }
        }
      }
    } catch (e) {
      debugPrint('Gallery pick error: $e');
    } finally {
      if (mounted) setState(() => _isPickingPhoto = false);
    }
  }

  void _removePhoto(int index) {
    setState(() {
      _photoPaths.removeAt(index);
    });
  }

  void _previewPhoto(String path) {
    showDialog<void>(
      context: context,
      builder:
          (dialogCtx) => Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.all(16),
            child: Stack(
              alignment: Alignment.topRight,
              children: [
                InteractiveViewer(
                  clipBehavior: Clip.none,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child:
                        File(path).existsSync()
                            ? Image.file(File(path), fit: BoxFit.contain)
                            : Image.network(path, fit: BoxFit.contain),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(dialogCtx).pop(),
                  icon: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.black.withAlpha(180),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.close,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ),
              ],
            ),
          ),
    );
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
      photoPaths: _photoPaths,
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
