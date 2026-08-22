import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:mobileshop_saas/core/constants/app_colors.dart';
import 'package:mobileshop_saas/features/repairs/data/services/thermal_receipt_service.dart';
import 'package:mobileshop_saas/features/settings/data/models/receipt_configuration_model.dart';
import 'package:mobileshop_saas/features/settings/presentation/providers/receipt_settings_provider.dart';

class ReceiptSettingsScreen extends ConsumerStatefulWidget {
  const ReceiptSettingsScreen({super.key});

  @override
  ConsumerState<ReceiptSettingsScreen> createState() =>
      _ReceiptSettingsScreenState();
}

class _ReceiptSettingsScreenState extends ConsumerState<ReceiptSettingsScreen> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _shopNameController;
  late TextEditingController _subtitleController;
  late TextEditingController _phoneController;
  late TextEditingController _addressController;
  late TextEditingController _termsController;
  late TextEditingController _footerController;

  String? _logoPath;
  bool _showLogo = true;
  String _paperSize = '80mm';
  bool _showBarcode = true;
  bool _showQrCode = false;
  bool _showCustomerPhone = true;
  bool _showDeviceColor = true;
  bool _showDeviceImei = true;
  bool _showTechnician = true;
  bool _showEstimatedDate = true;
  bool _showTerms = true;
  bool _showCustomerSignature = true;

  bool _isInitialized = false;
  bool _isPickingLogo = false;
  bool _isTestPrinting = false;

  @override
  void initState() {
    super.initState();
    _shopNameController = TextEditingController();
    _subtitleController = TextEditingController();
    _phoneController = TextEditingController();
    _addressController = TextEditingController();
    _termsController = TextEditingController();
    _footerController = TextEditingController();
  }

  @override
  void dispose() {
    _shopNameController.dispose();
    _subtitleController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _termsController.dispose();
    _footerController.dispose();
    super.dispose();
  }

  void _populateFromConfig(ReceiptConfigurationModel config) {
    if (_isInitialized) return;
    _shopNameController.text = config.shopName;
    _subtitleController.text = config.subtitle ?? '';
    _phoneController.text = config.phone ?? '';
    _addressController.text = config.address ?? '';
    _termsController.text = config.termsAndConditions;
    _footerController.text = config.footerMessage ?? '';
    _logoPath = config.logoPath;
    _showLogo = config.showLogo;
    _paperSize = config.paperSize;
    _showBarcode = config.showBarcode;
    _showQrCode = config.showQrCode;
    _showCustomerPhone = config.showCustomerPhone;
    _showDeviceColor = config.showDeviceColor;
    _showDeviceImei = config.showDeviceImei;
    _showTechnician = config.showTechnician;
    _showEstimatedDate = config.showEstimatedDate;
    _showTerms = config.showTerms;
    _showCustomerSignature = config.showCustomerSignature;
    _isInitialized = true;
  }

  ReceiptConfigurationModel _getCurrentConfig() {
    return ReceiptConfigurationModel(
      shopName: _shopNameController.text.trim().isNotEmpty
          ? _shopNameController.text.trim()
          : 'Mobile Care & Services',
      subtitle: _subtitleController.text.trim().isNotEmpty
          ? _subtitleController.text.trim()
          : null,
      phone: _phoneController.text.trim().isNotEmpty
          ? _phoneController.text.trim()
          : null,
      address: _addressController.text.trim().isNotEmpty
          ? _addressController.text.trim()
          : null,
      logoPath: _logoPath,
      showLogo: _showLogo,
      paperSize: _paperSize,
      showBarcode: _showBarcode,
      showQrCode: _showQrCode,
      showCustomerPhone: _showCustomerPhone,
      showDeviceColor: _showDeviceColor,
      showDeviceImei: _showDeviceImei,
      showTechnician: _showTechnician,
      showEstimatedDate: _showEstimatedDate,
      showTerms: _showTerms,
      termsAndConditions: _termsController.text.trim(),
      showCustomerSignature: _showCustomerSignature,
      footerMessage: _footerController.text.trim().isNotEmpty
          ? _footerController.text.trim()
          : null,
      updatedAt: DateTime.now(),
    );
  }

  Future<void> _pickLogo() async {
    setState(() => _isPickingLogo = true);
    try {
      if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        final result = await FilePicker.pickFiles(type: FileType.image);
        if (result != null && result.files.isNotEmpty) {
          final path = result.files.first.path;
          if (path != null) {
            setState(() {
              _logoPath = path;
              _showLogo = true;
            });
          }
        }
      } else {
        final picker = ImagePicker();
        final picked = await picker.pickImage(
          source: ImageSource.gallery,
          imageQuality: 85,
          maxWidth: 600,
          maxHeight: 300,
        );
        if (picked != null) {
          setState(() {
            _logoPath = picked.path;
            _showLogo = true;
          });
        }
      }
    } catch (e) {
      debugPrint('Logo pick error: $e');
    } finally {
      if (mounted) setState(() => _isPickingLogo = false);
    }
  }

  Future<void> _saveConfig() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final config = _getCurrentConfig();
    final success = await ref
        .read(receiptSettingsControllerProvider.notifier)
        .saveConfiguration(config);

    if (!mounted) return;
    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Receipt format saved successfully!'),
          backgroundColor: AppColors.success,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to save receipt format.'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _resetToDefault() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset to Default?'),
        content: const Text(
          'Are you sure you want to reset all receipt customization settings to default values?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final config = await ref
        .read(receiptSettingsControllerProvider.notifier)
        .resetToDefault();

    if (config != null && mounted) {
      setState(() {
        _isInitialized = false;
        _populateFromConfig(config);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Receipt settings reset to default.')),
      );
    }
  }

  Future<void> _testPrint() async {
    setState(() => _isTestPrinting = true);
    try {
      final config = _getCurrentConfig();
      await ThermalReceiptService.printTestReceipt(config: config);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Test print error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isTestPrinting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final configAsync = ref.watch(receiptConfigurationProvider);
    final controllerState = ref.watch(receiptSettingsControllerProvider);
    final isSaving = controllerState.isLoading;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Receipt & Printer Layout'),
        actions: [
          IconButton(
            tooltip: 'Test Print',
            onPressed: _isTestPrinting ? null : _testPrint,
            icon: _isTestPrinting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.print_outlined),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12.0, left: 4.0),
            child: FilledButton.icon(
              onPressed: isSaving ? null : _saveConfig,
              icon: isSaving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.save_rounded, size: 18),
              label: const Text('Save'),
            ),
          ),
        ],
      ),
      body: configAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Failed to load settings: $error'),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => ref.invalidate(receiptConfigurationProvider),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
        data: (config) {
          _populateFromConfig(config);
          return LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 960;
              final formWidget = _buildFormSection(isSaving);
              final previewWidget = _buildLivePreviewCard();

              if (isWide) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 6,
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(20.0),
                        child: formWidget,
                      ),
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(
                      flex: 5,
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(20.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _buildPreviewHeader(),
                            const SizedBox(height: 12),
                            previewWidget,
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              }

              return DefaultTabController(
                length: 2,
                child: Column(
                  children: [
                    const TabBar(
                      tabs: [
                        Tab(icon: Icon(Icons.tune_rounded), text: 'Configuration'),
                        Tab(icon: Icon(Icons.receipt_long_rounded), text: 'Live Preview'),
                      ],
                    ),
                    Expanded(
                      child: TabBarView(
                        children: [
                          SingleChildScrollView(
                            padding: const EdgeInsets.all(16.0),
                            child: formWidget,
                          ),
                          SingleChildScrollView(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              children: [
                                _buildPreviewHeader(),
                                const SizedBox(height: 12),
                                previewWidget,
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildPreviewHeader() {
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerHighest.withAlpha(120),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Row(
          children: [
            const Icon(Icons.remove_red_eye_outlined, size: 20),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'Live Thermal Slip Preview',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            OutlinedButton.icon(
              onPressed: _isTestPrinting ? null : _testPrint,
              icon: const Icon(Icons.print, size: 16),
              label: const Text('Test Print'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFormSection(bool isSaving) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Paper Size & Printing Mode
          _buildCard(
            title: 'Thermal Paper Format',
            icon: Icons.aspect_ratio_rounded,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Select the roll paper width used in your thermal printer:',
                  style: TextStyle(fontSize: 13, color: Colors.grey),
                ),
                const SizedBox(height: 12),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(
                      value: '80mm',
                      label: Text('80mm (Standard POS)'),
                      icon: Icon(Icons.receipt),
                    ),
                    ButtonSegment(
                      value: '58mm',
                      label: Text('58mm (Mini POS)'),
                      icon: Icon(Icons.phone_android),
                    ),
                  ],
                  selected: {_paperSize},
                  onSelectionChanged: (newSelection) {
                    setState(() {
                      _paperSize = newSelection.first;
                    });
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // 2. Shop Header & Branding
          _buildCard(
            title: 'Shop Information & Header',
            icon: Icons.storefront_rounded,
            child: Column(
              children: [
                TextFormField(
                  controller: _shopNameController,
                  enabled: !isSaving,
                  decoration: const InputDecoration(
                    labelText: 'Shop Name *',
                    hintText: 'e.g., Al-Madina Mobile Care',
                    prefixIcon: Icon(Icons.store),
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => setState(() {}),
                  validator: (v) => v == null || v.trim().isEmpty
                      ? 'Shop name is required'
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _subtitleController,
                  enabled: !isSaving,
                  decoration: const InputDecoration(
                    labelText: 'Subtitle / Tagline (Optional)',
                    hintText: 'e.g., Expert Smartphone Repairs & Accessories',
                    prefixIcon: Icon(Icons.subtitles_outlined),
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _phoneController,
                        enabled: !isSaving,
                        decoration: const InputDecoration(
                          labelText: 'Contact Phone / WhatsApp',
                          hintText: 'e.g., 0300-1234567',
                          prefixIcon: Icon(Icons.phone_outlined),
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _addressController,
                        enabled: !isSaving,
                        decoration: const InputDecoration(
                          labelText: 'Shop Address / Market Location',
                          hintText: 'e.g., Shop #12, Hafeez Center, Lahore',
                          prefixIcon: Icon(Icons.location_on_outlined),
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 8),

                // Logo Section
                Row(
                  children: [
                    if (_logoPath != null && _logoPath!.isNotEmpty) ...[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          width: 60,
                          height: 60,
                          color: Colors.grey.shade200,
                          child: Image.file(
                            File(_logoPath!),
                            fit: BoxFit.contain,
                            errorBuilder: (_, _, _) => const Icon(
                              Icons.broken_image_outlined,
                              color: Colors.grey,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                    ],
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _logoPath != null ? 'Shop Logo Uploaded' : 'Shop Logo (Optional)',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          Text(
                            _logoPath != null
                                ? 'Image will be rendered on thermal receipts'
                                : 'Upload black & white or high-contrast logo',
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                          ),
                        ],
                      ),
                    ),
                    if (_logoPath != null)
                      IconButton(
                        tooltip: 'Remove Logo',
                        onPressed: isSaving
                            ? null
                            : () => setState(() => _logoPath = null),
                        icon: const Icon(Icons.delete_outline, color: Colors.red),
                      ),
                    OutlinedButton.icon(
                      onPressed: isSaving || _isPickingLogo ? null : _pickLogo,
                      icon: const Icon(Icons.image_outlined, size: 18),
                      label: Text(_logoPath != null ? 'Change' : 'Upload Logo'),
                    ),
                  ],
                ),
                if (_logoPath != null) ...[
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Show Logo on Receipt'),
                    subtitle: const Text('Toggle logo visibility on printed receipts'),
                    value: _showLogo,
                    onChanged: (val) => setState(() => _showLogo = val),
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 16),

          // 3. Metadata & Field Toggles
          _buildCard(
            title: 'Receipt Content & Field Toggles',
            icon: Icons.checklist_rounded,
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('Print Barcode (Code128)'),
                  subtitle: const Text('Allows instant lookup with barcode scanner'),
                  secondary: const Icon(Icons.qr_code_2_rounded),
                  value: _showBarcode,
                  onChanged: (v) {
                    setState(() {
                      _showBarcode = v;
                      if (v) _showQrCode = false;
                    });
                  },
                ),
                const Divider(height: 1),
                SwitchListTile(
                  title: const Text('Print QR Code (Alternative)'),
                  subtitle: const Text('2D QR code for ticket lookup'),
                  secondary: const Icon(Icons.qr_code_rounded),
                  value: _showQrCode,
                  onChanged: (v) {
                    setState(() {
                      _showQrCode = v;
                      if (v) _showBarcode = false;
                    });
                  },
                ),
                const Divider(height: 1),
                SwitchListTile(
                  title: const Text('Customer Phone Number'),
                  secondary: const Icon(Icons.phone_outlined),
                  value: _showCustomerPhone,
                  onChanged: (v) => setState(() => _showCustomerPhone = v),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  title: const Text('Device Color'),
                  secondary: const Icon(Icons.palette_outlined),
                  value: _showDeviceColor,
                  onChanged: (v) => setState(() => _showDeviceColor = v),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  title: const Text('Device IMEI / Serial Number'),
                  secondary: const Icon(Icons.fingerprint_rounded),
                  value: _showDeviceImei,
                  onChanged: (v) => setState(() => _showDeviceImei = v),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  title: const Text('Technician Name'),
                  secondary: const Icon(Icons.engineering_outlined),
                  value: _showTechnician,
                  onChanged: (v) => setState(() => _showTechnician = v),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  title: const Text('Estimated Delivery Date'),
                  secondary: const Icon(Icons.event_outlined),
                  value: _showEstimatedDate,
                  onChanged: (v) => setState(() => _showEstimatedDate = v),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  title: const Text('Customer Signature Line'),
                  subtitle: const Text('Intake signature line on printed slip'),
                  secondary: const Icon(Icons.draw_outlined),
                  value: _showCustomerSignature,
                  onChanged: (v) => setState(() => _showCustomerSignature = v),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // 4. Terms & Policy
          _buildCard(
            title: 'Terms & Conditions and Policy Note',
            icon: Icons.gavel_rounded,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Print Terms & Conditions'),
                  subtitle: const Text('Include warranty & intake policies'),
                  value: _showTerms,
                  onChanged: (v) => setState(() => _showTerms = v),
                ),
                if (_showTerms) ...[
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _termsController,
                    enabled: !isSaving,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Terms & Conditions Text',
                      hintText: 'Enter warranty policy, pickup window, disclaimer...',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ],
                const SizedBox(height: 12),
                TextFormField(
                  controller: _footerController,
                  enabled: !isSaving,
                  decoration: const InputDecoration(
                    labelText: 'Footer Message (e.g. Thank You Note)',
                    hintText: 'e.g., Thank you for choosing us! Visit again.',
                    prefixIcon: Icon(Icons.favorite_border_rounded),
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Bottom Action Row
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: isSaving ? null : _resetToDefault,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Reset to Default'),
              ),
              const Spacer(),
              FilledButton.icon(
                onPressed: isSaving ? null : _saveConfig,
                icon: isSaving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.check_rounded),
                label: const Text('Save Configuration'),
              ),
            ],
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildCard({
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Theme.of(context).dividerColor.withAlpha(60)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 22, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 10),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }

  Widget _buildLivePreviewCard() {
    final is58mm = _paperSize.contains('58');
    final shopName = _shopNameController.text.trim().isNotEmpty
        ? _shopNameController.text.trim()
        : 'Mobile Care & Services';
    final subtitle = _subtitleController.text.trim();
    final phone = _phoneController.text.trim();
    final address = _addressController.text.trim();
    final terms = _termsController.text.trim();
    final footer = _footerController.text.trim();
    final dateStr = DateFormat('dd-MMM-yyyy hh:mm a').format(DateTime.now());

    final mono = GoogleFonts.courierPrime(
      fontSize: is58mm ? 10.5 : 12.0,
      color: Colors.black87,
      height: 1.25,
    );

    final monoBold = GoogleFonts.courierPrime(
      fontSize: is58mm ? 11.0 : 12.5,
      fontWeight: FontWeight.bold,
      color: Colors.black,
      height: 1.25,
    );

    final monoTitle = GoogleFonts.courierPrime(
      fontSize: is58mm ? 14.0 : 16.0,
      fontWeight: FontWeight.bold,
      color: Colors.black,
      height: 1.2,
    );

    final monoSmall = GoogleFonts.courierPrime(
      fontSize: is58mm ? 8.5 : 9.5,
      color: Colors.black54,
      height: 1.2,
    );

    Widget lineRow(String label, String value, {bool isBold = false}) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 1.5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$label: ', style: monoBold),
            Expanded(
              child: Text(
                value,
                textAlign: TextAlign.right,
                style: isBold ? monoBold : mono,
              ),
            ),
          ],
        ),
      );
    }

    Widget receiptDivider() {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4.0),
        child: Text(
          is58mm
              ? '---------------------------'
              : '----------------------------------------',
          textAlign: TextAlign.center,
          style: monoBold,
          maxLines: 1,
        ),
      );
    }

    return Center(
      child: Container(
        width: is58mm ? 270 : 340,
        decoration: BoxDecoration(
          color: const Color(0xFFFDFDFD),
          borderRadius: BorderRadius.circular(4),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(30),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
          border: Border.all(color: Colors.grey.shade300, width: 1),
        ),
        padding: EdgeInsets.symmetric(
          horizontal: is58mm ? 12 : 18,
          vertical: 16,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Top Zig-zag / simulated tear
            Container(
              height: 4,
              color: Colors.grey.shade200,
              margin: const EdgeInsets.only(bottom: 8),
            ),

            // Logo Preview
            if (_showLogo && _logoPath != null && _logoPath!.isNotEmpty) ...[
              Center(
                child: SizedBox(
                  height: is58mm ? 36 : 48,
                  child: Image.file(
                    File(_logoPath!),
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) => const SizedBox(),
                  ),
                ),
              ),
              const SizedBox(height: 6),
            ],

            // Shop Header
            Text(shopName, textAlign: TextAlign.center, style: monoTitle),
            if (subtitle.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(subtitle, textAlign: TextAlign.center, style: mono),
            ],
            if (phone.isNotEmpty) ...[
              Text('Tel: $phone', textAlign: TextAlign.center, style: monoSmall),
            ],
            if (address.isNotEmpty) ...[
              Text(address, textAlign: TextAlign.center, style: monoSmall),
            ],

            receiptDivider(),

            Center(
              child: Text(
                'REPAIR INTAKE RECEIPT',
                style: monoBold,
              ),
            ),
            const SizedBox(height: 4),
            lineRow('Ticket No', 'TK-2026-0891', isBold: true),
            lineRow('Date', dateStr),
            lineRow('Status', 'IN_PROGRESS'),

            receiptDivider(),

            lineRow('Customer', 'Muhammad Ali', isBold: true),
            if (_showCustomerPhone) lineRow('Phone', '0300-1234567'),

            const SizedBox(height: 4),
            lineRow('Device', 'Samsung Galaxy S23 Ultra', isBold: true),
            if (_showDeviceColor) lineRow('Color', 'Phantom Black'),
            if (_showDeviceImei) lineRow('IMEI', '864209040123456'),
            if (_showTechnician) lineRow('Tech', 'Asif'),
            if (_showEstimatedDate) lineRow('Est. Date', '24-Aug-2026'),

            receiptDivider(),

            Text('Reported Fault:', style: monoBold),
            const SizedBox(height: 2),
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade400, width: 0.5),
                borderRadius: BorderRadius.circular(2),
              ),
              child: Text(
                'Screen glass broken, touch working fine. Display replacement requested.',
                style: mono,
              ),
            ),

            receiptDivider(),

            lineRow('Estimated Cost', 'Rs 18,500', isBold: true),
            lineRow('Advance Paid', 'Rs 5,000'),
            lineRow('Balance Due', 'Rs 13,500', isBold: true),

            if (_showBarcode || _showQrCode) ...[
              const SizedBox(height: 8),
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    border: Border.all(color: Colors.grey.shade300, width: 0.5),
                  ),
                  child: Column(
                    children: [
                      Icon(
                        _showQrCode ? Icons.qr_code_2 : Icons.barcode_reader,
                        size: is58mm ? 36 : 48,
                      ),
                      Text('*TK-2026-0891*', style: monoSmall),
                    ],
                  ),
                ),
              ),
            ],

            if (_showTerms && terms.isNotEmpty) ...[
              receiptDivider(),
              Text('Terms & Conditions:', style: monoBold),
              const SizedBox(height: 2),
              Text(terms, style: monoSmall),
            ],

            if (_showCustomerSignature) ...[
              const SizedBox(height: 12),
              Text('Customer Sign: ______________', style: monoSmall),
            ],

            if (footer.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(footer, textAlign: TextAlign.center, style: mono),
            ],

            const SizedBox(height: 8),
            Container(
              height: 4,
              color: Colors.grey.shade200,
            ),
          ],
        ),
      ),
    );
  }
}
