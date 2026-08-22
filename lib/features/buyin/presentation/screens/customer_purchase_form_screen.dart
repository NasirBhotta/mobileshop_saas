import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import 'package:mobileshop_saas/core/constants/app_colors.dart';
import 'package:mobileshop_saas/core/utils/responsive.dart';
import 'package:mobileshop_saas/features/accounts/data/models/account_models.dart';
import 'package:mobileshop_saas/features/accounts/presentation/providers/accounts_provider.dart';
import 'package:mobileshop_saas/features/buyin/data/models/customer_purchase_model.dart';
import 'package:mobileshop_saas/features/buyin/data/services/buyin_thermal_receipt_service.dart';
import 'package:mobileshop_saas/features/buyin/presentation/providers/customer_purchase_provider.dart';
import 'package:mobileshop_saas/features/inventory/data/models/category_model.dart';
import 'package:mobileshop_saas/features/inventory/data/models/product_model.dart';
import 'package:mobileshop_saas/features/inventory/presentation/providers/inventory_provider.dart';
import 'package:mobileshop_saas/features/settings/presentation/providers/receipt_settings_provider.dart';

class CustomerPurchaseFormScreen extends ConsumerStatefulWidget {
  const CustomerPurchaseFormScreen({super.key});

  @override
  ConsumerState<CustomerPurchaseFormScreen> createState() => _CustomerPurchaseFormScreenState();
}

class _CustomerPurchaseFormScreenState extends ConsumerState<CustomerPurchaseFormScreen> {
  final _formKey = GlobalKey<FormState>();

  // ── Seller Controllers ──
  final _sellerNameController = TextEditingController();
  final _sellerCnicController = TextEditingController();
  final _sellerPhoneController = TextEditingController();
  final _sellerAddressController = TextEditingController();

  // ── Device Controllers ──
  final _productNameController = TextEditingController();
  final _imei1Controller = TextEditingController();
  final _imei2Controller = TextEditingController();
  final _colorController = TextEditingController();
  final _notesController = TextEditingController();

  // ── Financial Controllers ──
  final _purchasePriceController = TextEditingController();
  final _expectedSalePriceController = TextEditingController();

  // ── State Selections ──
  bool _isNewProductMode = true;
  String? _selectedProductId;
  String? _selectedCategoryId;
  String? _selectedStorage = '128 GB';
  String? _selectedCondition = '10/10 (Mint)';
  final Set<String> _selectedAccessories = {'Original Box', 'Charger'};
  String? _selectedAccountId;
  String _paymentMethod = 'cash';
  bool _declarationAgreed = true;
  bool _isSubmitting = false;

  String? _cnicFrontPath;
  String? _cnicBackPath;

  static const List<String> _storageOptions = [
    '32 GB',
    '64 GB',
    '128 GB',
    '256 GB',
    '512 GB',
    '1 TB',
  ];

  static const List<String> _conditionOptions = [
    '10/10 (Mint)',
    '9/10 (Minor Scratches)',
    '8/10 (Visible Signs)',
    '7/10 (Average / Dent)',
    'Repaired / Screen Replaced',
  ];

  static const List<String> _accessoryOptions = [
    'Original Box',
    'Charger',
    'Data Cable',
    'Handsfree / Earphones',
    'Warranty Card',
    'Purchase Receipt (Original)',
  ];

  @override
  void dispose() {
    _sellerNameController.dispose();
    _sellerCnicController.dispose();
    _sellerPhoneController.dispose();
    _sellerAddressController.dispose();
    _productNameController.dispose();
    _imei1Controller.dispose();
    _imei2Controller.dispose();
    _colorController.dispose();
    _notesController.dispose();
    _purchasePriceController.dispose();
    _expectedSalePriceController.dispose();
    super.dispose();
  }

  Future<void> _pickImage({required bool isFront}) async {
    try {
      if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        final result = await FilePicker.pickFiles(type: FileType.image);
        if (result != null && result.files.isNotEmpty) {
          final path = result.files.first.path;
          if (path != null) {
            setState(() {
              if (isFront) {
                _cnicFrontPath = path;
              } else {
                _cnicBackPath = path;
              }
            });
          }
        }
      } else {
        final picker = ImagePicker();
        final picked = await picker.pickImage(
          source: ImageSource.gallery,
          imageQuality: 80,
        );
        if (picked != null) {
          setState(() {
            if (isFront) {
              _cnicFrontPath = picked.path;
            } else {
              _cnicBackPath = picked.path;
            }
          });
        }
      }
    } catch (e) {
      debugPrint('CNIC photo pick error: $e');
    }
  }

  Future<void> _submitForm() async {
    if (!_formKey.currentState!.validate()) return;

    if (!_declarationAgreed) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please accept the legal owner declaration before proceeding.'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    final purchasePrice = double.tryParse(_purchasePriceController.text.trim()) ?? 0.0;
    final expectedSalePrice = double.tryParse(_expectedSalePriceController.text.trim()) ?? 0.0;

    setState(() => _isSubmitting = true);

    try {
      final purchase = await ref
          .read(customerPurchaseControllerProvider.notifier)
          .createPurchase(
            sellerName: _sellerNameController.text.trim(),
            sellerCnic: _sellerCnicController.text.trim(),
            sellerPhone: _sellerPhoneController.text.trim(),
            sellerAddress: _sellerAddressController.text.trim().isNotEmpty
                ? _sellerAddressController.text.trim()
                : null,
            cnicFrontUrl: _cnicFrontPath,
            cnicBackUrl: _cnicBackPath,
            existingProductId: _isNewProductMode ? null : _selectedProductId,
            productName: _productNameController.text.trim(),
            categoryId: _selectedCategoryId,
            imei1: _imei1Controller.text.trim(),
            imei2: _imei2Controller.text.trim().isNotEmpty
                ? _imei2Controller.text.trim()
                : null,
            color: _colorController.text.trim().isNotEmpty
                ? _colorController.text.trim()
                : null,
            storage: _selectedStorage,
            deviceCondition: _selectedCondition,
            accessories: _selectedAccessories.join(', '),
            purchasePrice: purchasePrice,
            expectedSalePrice: expectedSalePrice,
            paymentAccountId: _selectedAccountId,
            paymentMethod: _paymentMethod,
            notes: _notesController.text.trim().isNotEmpty
                ? _notesController.text.trim()
                : null,
            declarationAgreed: _declarationAgreed,
          );

      if (!mounted) return;
      setState(() => _isSubmitting = false);

      if (purchase != null) {
        _showSuccessDialog(purchase);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to save purchase record.'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      final cleanMsg = e.toString().replaceAll('Exception:', '').trim();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(cleanMsg),
          backgroundColor: AppColors.error,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  void _showSuccessDialog(CustomerPurchaseModel purchase) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        final currencyFormat = NumberFormat('#,##0.00', 'en_US');
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: const [
              Icon(Icons.check_circle_rounded, color: AppColors.success, size: 28),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Used Device Intake Complete!',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Mobile: ${purchase.productName}',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
              const SizedBox(height: 4),
              Text('IMEI: ${purchase.imei1}'),
              Text('Seller: ${purchase.sellerName} (CNIC: ${purchase.sellerCnic})'),
              Text(
                'Cost Paid: Rs. ${currencyFormat.format(purchase.purchasePrice)}',
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.green.withAlpha(20),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green.withAlpha(60)),
                ),
                child: Row(
                  children: const [
                    Icon(Icons.inventory_2_rounded, color: Colors.green, size: 20),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Device has been added to inventory and is ready for POS sale.',
                        style: TextStyle(fontSize: 12, color: Colors.green),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actionsPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          actions: [
            TextButton.icon(
              onPressed: () async {
                final config = await ref.read(receiptConfigurationProvider.future);
                await BuyInThermalReceiptService.printBuyInAgreement(
                  purchase: purchase,
                  config: config,
                );
              },
              icon: const Icon(Icons.print_rounded),
              label: const Text('Print Agreement'),
            ),
            TextButton.icon(
              onPressed: () => BuyInThermalReceiptService.shareBuyInText(purchase),
              icon: const Icon(Icons.share_rounded),
              label: const Text('Share'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                if (mounted) {
                  if (context.canPop()) {
                    context.pop();
                  } else {
                    context.go('/buyin');
                  }
                }
              },
              child: const Text('Done'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final categoriesAsync = ref.watch(categoriesProvider);
    final productsAsync = ref.watch(productsProvider);
    final accountsAsync = ref.watch(accountsProvider);
    final isDesktop = Responsive.isDesktop(context);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/buyin');
            }
          },
        ),
        title: const Text('Used Device Buy-In (Intake)'),
        elevation: 0,
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: EdgeInsets.symmetric(
              horizontal: isDesktop ? 48.0 : 16.0,
              vertical: 20.0,
            ),
            children: [
              _buildHeaderBanner(),
              const SizedBox(height: 16),

              if (isDesktop)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        children: [
                          _buildSellerCard(),
                          const SizedBox(height: 16),
                          _buildDeviceSpecsCard(categoriesAsync, productsAsync),
                        ],
                      ),
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      child: Column(
                        children: [
                          _buildFinancialsCard(accountsAsync),
                          const SizedBox(height: 16),
                          _buildDeclarationCard(),
                          const SizedBox(height: 24),
                          _buildSubmitButton(),
                        ],
                      ),
                    ),
                  ],
                )
              else
                Column(
                  children: [
                    _buildSellerCard(),
                    const SizedBox(height: 16),
                    _buildDeviceSpecsCard(categoriesAsync, productsAsync),
                    const SizedBox(height: 16),
                    _buildFinancialsCard(accountsAsync),
                    const SizedBox(height: 16),
                    _buildDeclarationCard(),
                    const SizedBox(height: 24),
                    _buildSubmitButton(),
                    const SizedBox(height: 32),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderBanner() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.primary.withAlpha(20),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withAlpha(60)),
      ),
      child: Row(
        children: [
          Icon(Icons.verified_user_rounded, color: AppColors.primary, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text(
                  'Legal Customer Buy-In & Ownership Verification',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                SizedBox(height: 2),
                Text(
                  'Record seller CNIC, phone, device condition & auto-add to inventory with zero friction.',
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSellerCard() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.withAlpha(50)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: const [
                Icon(Icons.person_pin_rounded, color: AppColors.primary),
                SizedBox(width: 8),
                Text(
                  '1. Seller (Customer) Verification',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const Divider(height: 24),

            // Seller Name
            TextFormField(
              controller: _sellerNameController,
              decoration: const InputDecoration(
                labelText: 'Seller Full Name *',
                prefixIcon: Icon(Icons.person_outline_rounded),
                border: OutlineInputBorder(),
              ),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter seller name' : null,
            ),
            const SizedBox(height: 12),

            // CNIC
            TextFormField(
              controller: _sellerCnicController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'CNIC / National ID *',
                hintText: '35201-1234567-1',
                prefixIcon: Icon(Icons.badge_outlined),
                border: OutlineInputBorder(),
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Enter CNIC number for legal record';
                if (v.trim().length < 13) return 'Enter a valid CNIC';
                return null;
              },
            ),
            const SizedBox(height: 12),

            // Phone
            TextFormField(
              controller: _sellerPhoneController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Contact Phone Number *',
                hintText: '0300-1234567',
                prefixIcon: Icon(Icons.phone_outlined),
                border: OutlineInputBorder(),
              ),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter phone number' : null,
            ),
            const SizedBox(height: 12),

            // Address
            TextFormField(
              controller: _sellerAddressController,
              decoration: const InputDecoration(
                labelText: 'Residential Address (Optional)',
                prefixIcon: Icon(Icons.location_on_outlined),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 14),

            // CNIC Attachments
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pickImage(isFront: true),
                    icon: Icon(
                      _cnicFrontPath != null ? Icons.check_circle_rounded : Icons.camera_alt_outlined,
                      color: _cnicFrontPath != null ? AppColors.success : null,
                    ),
                    label: Text(_cnicFrontPath != null ? 'CNIC Front Added' : 'CNIC Front'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pickImage(isFront: false),
                    icon: Icon(
                      _cnicBackPath != null ? Icons.check_circle_rounded : Icons.camera_alt_outlined,
                      color: _cnicBackPath != null ? AppColors.success : null,
                    ),
                    label: Text(_cnicBackPath != null ? 'CNIC Back Added' : 'CNIC Back'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeviceSpecsCard(
    AsyncValue<List<CategoryModel>> categoriesAsync,
    AsyncValue<List<ProductModel>> productsAsync,
  ) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.withAlpha(50)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: const [
                Icon(Icons.phone_android_rounded, color: AppColors.primary),
                SizedBox(width: 8),
                Text(
                  '2. Device Specifications & Inspection',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const Divider(height: 24),

            // Mode Selector
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(
                  value: true,
                  label: Text('New Used Model'),
                  icon: Icon(Icons.add_box_outlined),
                ),
                ButtonSegment(
                  value: false,
                  label: Text('Existing Catalog'),
                  icon: Icon(Icons.list_alt_rounded),
                ),
              ],
              selected: {_isNewProductMode},
              onSelectionChanged: (set) {
                setState(() {
                  _isNewProductMode = set.first;
                  if (_isNewProductMode) _selectedProductId = null;
                });
              },
            ),
            const SizedBox(height: 14),

            if (_isNewProductMode) ...[
              TextFormField(
                controller: _productNameController,
                decoration: const InputDecoration(
                  labelText: 'Device Brand & Model *',
                  hintText: 'e.g. iPhone 13 Pro Max 256GB / Samsung A54',
                  prefixIcon: Icon(Icons.smartphone_rounded),
                  border: OutlineInputBorder(),
                ),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter device name/model' : null,
              ),
              const SizedBox(height: 12),
              categoriesAsync.when(
                data: (categories) {
                  return DropdownButtonFormField<String>(
                    initialValue: _selectedCategoryId,
                    decoration: const InputDecoration(
                      labelText: 'Category',
                      prefixIcon: Icon(Icons.category_outlined),
                      border: OutlineInputBorder(),
                    ),
                    items: categories
                        .map((c) => DropdownMenuItem(value: c.id, child: Text(c.name)))
                        .toList(),
                    onChanged: (val) => setState(() => _selectedCategoryId = val),
                  );
                },
                loading: () => const LinearProgressIndicator(),
                error: (err, stack) => const SizedBox.shrink(),
              ),
            ] else ...[
              productsAsync.when(
                data: (products) {
                  return DropdownButtonFormField<String>(
                    initialValue: _selectedProductId,
                    decoration: const InputDecoration(
                      labelText: 'Select Product from Catalog *',
                      prefixIcon: Icon(Icons.inventory_2_outlined),
                      border: OutlineInputBorder(),
                    ),
                    items: products
                        .map((p) => DropdownMenuItem(
                              value: p.id,
                              child: Text('${p.name} (In stock: ${p.stock})'),
                            ))
                        .toList(),
                    onChanged: (val) {
                      setState(() {
                        _selectedProductId = val;
                        final p = products.firstWhere((item) => item.id == val);
                        _productNameController.text = p.name;
                        _selectedCategoryId = p.categoryId;
                        if (_expectedSalePriceController.text.isEmpty && p.salePrice > 0) {
                          _expectedSalePriceController.text = p.salePrice.toStringAsFixed(0);
                        }
                      });
                    },
                    validator: (v) => (v == null || v.isEmpty) ? 'Select a product' : null,
                  );
                },
                loading: () => const LinearProgressIndicator(),
                error: (err, stack) => const SizedBox.shrink(),
              ),
            ],
            const SizedBox(height: 12),

            // IMEI 1 & IMEI 2
            TextFormField(
              controller: _imei1Controller,
              decoration: const InputDecoration(
                labelText: 'IMEI 1 / Serial Number *',
                hintText: '15-digit unique IMEI',
                prefixIcon: Icon(Icons.qr_code_2_rounded),
                border: OutlineInputBorder(),
              ),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter IMEI 1' : null,
            ),
            const SizedBox(height: 12),

            TextFormField(
              controller: _imei2Controller,
              decoration: const InputDecoration(
                labelText: 'IMEI 2 (Optional - Dual SIM)',
                hintText: 'Secondary IMEI',
                prefixIcon: Icon(Icons.pin_outlined),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),

            // Color & Storage
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _colorController,
                    decoration: const InputDecoration(
                      labelText: 'Color',
                      hintText: 'e.g. Sierra Blue, Black',
                      prefixIcon: Icon(Icons.palette_outlined),
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _selectedStorage,
                    decoration: const InputDecoration(
                      labelText: 'Storage',
                      border: OutlineInputBorder(),
                    ),
                    items: _storageOptions
                        .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                        .toList(),
                    onChanged: (val) => setState(() => _selectedStorage = val),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Condition Dropdown
            DropdownButtonFormField<String>(
              initialValue: _selectedCondition,
              decoration: const InputDecoration(
                labelText: 'Physical Condition Grade',
                prefixIcon: Icon(Icons.star_half_rounded),
                border: OutlineInputBorder(),
              ),
              items: _conditionOptions
                  .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                  .toList(),
              onChanged: (val) => setState(() => _selectedCondition = val),
            ),
            const SizedBox(height: 14),

            // Accessories Checkboxes
            const Text(
              'Included Accessories:',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: _accessoryOptions.map((acc) {
                final isSelected = _selectedAccessories.contains(acc);
                return FilterChip(
                  label: Text(acc, style: const TextStyle(fontSize: 12)),
                  selected: isSelected,
                  onSelected: (selected) {
                    setState(() {
                      if (selected) {
                        _selectedAccessories.add(acc);
                      } else {
                        _selectedAccessories.remove(acc);
                      }
                    });
                  },
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFinancialsCard(AsyncValue<List<AccountModel>> accountsAsync) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.withAlpha(50)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: const [
                Icon(Icons.payments_rounded, color: AppColors.primary),
                SizedBox(width: 8),
                Text(
                  '3. Pricing & Payment Outflow',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const Divider(height: 24),

            // Purchase Price
            TextFormField(
              controller: _purchasePriceController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}'))],
              decoration: const InputDecoration(
                labelText: 'Purchase / Cost Price (Paid to Seller) *',
                hintText: 'Rs. 0.00',
                prefixText: 'Rs. ',
                prefixIcon: Icon(Icons.money_off_rounded),
                border: OutlineInputBorder(),
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Enter purchase cost';
                final n = double.tryParse(v);
                if (n == null || n < 0) return 'Enter valid amount';
                return null;
              },
            ),
            const SizedBox(height: 12),

            // Expected Sale Price
            TextFormField(
              controller: _expectedSalePriceController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}'))],
              decoration: const InputDecoration(
                labelText: 'Expected POS Selling Price',
                hintText: 'Rs. 0.00',
                prefixText: 'Rs. ',
                prefixIcon: Icon(Icons.attach_money_rounded),
                border: OutlineInputBorder(),
                helperText: 'Price at which this device will be sold on POS screen.',
              ),
            ),
            const SizedBox(height: 14),

            // Payment Account Dropdown
            accountsAsync.when(
              data: (accounts) {
                return DropdownButtonFormField<String>(
                  initialValue: _selectedAccountId,
                  decoration: const InputDecoration(
                    labelText: 'Deduct Payment From Account',
                    prefixIcon: Icon(Icons.account_balance_wallet_outlined),
                    border: OutlineInputBorder(),
                    helperText: 'Select Cash Drawer or Bank Account for financial deduction.',
                  ),
                  items: [
                    const DropdownMenuItem<String>(
                      value: null,
                      child: Text('None (No Immediate Cash Outflow / Trade-in)'),
                    ),
                    ...accounts.map((a) {
                      return DropdownMenuItem<String>(
                        value: a.id,
                        child: Text('${a.name} (Balance: Rs. ${a.currentBalance.toStringAsFixed(0)})'),
                      );
                    }),
                  ],
                  onChanged: (val) {
                    setState(() {
                      _selectedAccountId = val;
                      if (val != null) {
                        final matched = accounts.firstWhere((a) => a.id == val);
                        _paymentMethod = matched.type.code.toLowerCase();
                      }
                    });
                  },
                );
              },
              loading: () => const LinearProgressIndicator(),
              error: (err, stack) => const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeclarationCard() {
    return Card(
      elevation: 0,
      color: Colors.amber.withAlpha(15),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.amber.withAlpha(60)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: const [
                Icon(Icons.gavel_rounded, color: Colors.amber, size: 22),
                SizedBox(width: 8),
                Text(
                  '4. Legal Declaration & Undertaking',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 10),
            const Text(
              'Under Pakistan penal code and trade regulations, the seller guarantees legal device ownership and confirms it is not stolen, blacklisted, or tied to illegal activities.',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 10),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'Seller has verified CNIC & signed ownership transfer agreement.',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              value: _declarationAgreed,
              onChanged: (val) => setState(() => _declarationAgreed = val ?? true),
              controlAffinity: ListTileControlAffinity.leading,
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _notesController,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Internal Notes / Inspection Remarks (Optional)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSubmitButton() {
    return SizedBox(
      height: 52,
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: _isSubmitting ? null : _submitForm,
        icon: _isSubmitting
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              )
            : const Icon(Icons.check_circle_rounded),
        label: Text(
          _isSubmitting ? 'Saving Intake...' : 'Complete Buy-In & Add to Inventory',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}
