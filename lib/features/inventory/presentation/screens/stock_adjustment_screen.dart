import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobileshop_saas/core/utils/adjustment_extention.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/utils/responsive.dart';
import '../../data/models/product_model.dart';
import '../../data/models/stock_adjustment_model.dart';
import '../providers/inventory_provider.dart';

class StockAdjustmentScreen extends ConsumerStatefulWidget {
  final ProductModel product;

  const StockAdjustmentScreen({super.key, required this.product});

  @override
  ConsumerState<StockAdjustmentScreen> createState() =>
      _StockAdjustmentScreenState();
}

class _StockAdjustmentScreenState extends ConsumerState<StockAdjustmentScreen> {
  // Form
  final _formKey = GlobalKey<FormState>();
  final _quantityController = TextEditingController();
  final _noteController = TextEditingController();

  // State
  AdjustmentType _type = AdjustmentType.stockIn; // default: Stock In
  AdjustmentReason _reason = AdjustmentReason.damaged; // default: Damage

  // Computed
  int get _currentStock => widget.product.stock;

  int get _enteredQty => int.tryParse(_quantityController.text) ?? 0;

  // Naya stock preview — live calculate hota hai
  int get _newStock {
    if (_type == AdjustmentType.stockIn) {
      return _currentStock + _enteredQty;
    }
    return _currentStock - _enteredQty;
  }

  // Negative hoga?
  bool get _willGoNegative => _newStock < 0;

  @override
  void dispose() {
    _quantityController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  // ── Submit Handle ─────────────────────────────
  Future<void> _handleSubmit() async {
    if (!_formKey.currentState!.validate()) return;

    // Other reason → note zaroori hai
    if (_reason == AdjustmentReason.other &&
        _noteController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(AppStrings.errorReasonNoteRequired),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    // Negative hoga → owner override confirm karo
    if (_willGoNegative) {
      final confirmed = await _showOverrideDialog();
      if (!confirmed) return; // user ne cancel kiya
    }

    // Adjust karo
    final success = await ref
        .read(stockAdjustmentControllerProvider.notifier)
        .adjust(
          productId: widget.product.id,
          type: _type,
          quantity: _enteredQty,
          reason: _reason,
          reasonNote:
              _noteController.text.trim().isEmpty
                  ? null
                  : _noteController.text.trim(),
          isOverride: _willGoNegative,
          product: widget.product, // agar negative tha toh override = true
        );

    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(AppStrings.stockAdjustSuccess),
          backgroundColor: AppColors.success,
        ),
      );
      ref.watch(productControllerProvider.notifier); // product list refresh
      context.pop(); // wapas product list pe
    }
  }

  // ── Override Dialog ───────────────────────────
  Future<bool> _showOverrideDialog() async {
    return await showDialog<bool>(
          context: context,
          builder:
              (_) => AlertDialog(
                title: const Text('⚠️ Stock Negative Hoga'),
                content: Text(
                  'Yeh adjustment ke baad stock $_newStock ho jaye ga.\n\n'
                  'Kya aap bahi Owner permission se override karna chahte hain?',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.error,
                    ),
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Override Karein'),
                  ),
                ],
              ),
        ) ??
        false;
  }

  @override
  Widget build(BuildContext context) {
    final isLoading = ref.watch(stockAdjustmentControllerProvider).isLoading;
    final isDesktop = Responsive.isDesktop(context);

    // Error sun'na
    ref.listen(stockAdjustmentControllerProvider, (_, next) {
      if (next.hasError) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(next.error.toString()),
            backgroundColor: AppColors.error,
          ),
        );
      }
    });

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text(AppStrings.stockAdjust)),
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: isDesktop ? 560 : double.infinity,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Product Info Card ──────────────────
                  _ProductInfoCard(product: widget.product),
                  const SizedBox(height: 24),

                  // ── Type Toggle (Stock In / Stock Out) ─
                  const _SectionLabel(AppStrings.fieldAdjustmentType),
                  const SizedBox(height: 8),
                  _TypeToggle(
                    selected: _type,
                    onChanged: (type) => setState(() => _type = type),
                  ),
                  const SizedBox(height: 20),

                  // ── Quantity ───────────────────────────
                  const _SectionLabel(AppStrings.fieldQuantity),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _quantityController,
                    keyboardType: TextInputType.number,
                    onChanged: (_) => setState(() {}), // preview update
                    decoration: const InputDecoration(hintText: '0'),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return AppStrings.errorQuantityRequired;
                      }
                      final qty = int.tryParse(value);
                      if (qty == null || qty <= 0) {
                        return AppStrings.errorQuantityInvalid;
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 20),

                  // ── Reason Dropdown ────────────────────
                  const _SectionLabel(AppStrings.fieldReason),
                  const SizedBox(height: 8),
                  _ReasonDropdown(
                    selected: _reason,
                    onChanged: (reason) => setState(() => _reason = reason),
                  ),
                  const SizedBox(height: 20),

                  // ── Note (sirf Other pe) ───────────────
                  if (_reason == AdjustmentReason.other) ...[
                    const _SectionLabel(AppStrings.fieldReasonNote),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _noteController,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        hintText: AppStrings.hintReasonNote,
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],

                  // ── New Stock Preview ──────────────────
                  if (_enteredQty > 0) ...[
                    _StockPreviewCard(
                      currentStock: _currentStock,
                      newStock: _newStock,
                      type: _type,
                    ),
                    const SizedBox(height: 24),
                  ],

                  // ── Submit Button ──────────────────────
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: isLoading ? null : _handleSubmit,
                      child:
                          isLoading
                              ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                              : const Text(AppStrings.stockAdjustButton),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════
// WIDGETS
// ════════════════════════════════════════

// Product Info Card — top pe dikhta hai
class _ProductInfoCard extends StatelessWidget {
  final ProductModel product;

  const _ProductInfoCard({required this.product});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          // Product icon
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.phone_android_rounded,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: 14),

          // Name + current stock
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product.name,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                if (product.sku != null && product.sku!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    'SKU: ${product.sku}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),

          // Current stock badge
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Text(
                AppStrings.currentStock,
                style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
              ),
              Text(
                '${product.stock}',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// Type Toggle — Stock In / Stock Out
class _TypeToggle extends StatelessWidget {
  final AdjustmentType selected;
  final ValueChanged<AdjustmentType> onChanged;

  const _TypeToggle({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      children:
          AdjustmentType.values.map((type) {
            final isSelected = selected == type;
            final color =
                type == AdjustmentType.stockIn
                    ? AppColors.success
                    : AppColors.error;

            return Expanded(
              child: GestureDetector(
                onTap: () => onChanged(type),
                child: Container(
                  margin: EdgeInsets.only(
                    right: type == AdjustmentType.stockIn ? 8 : 0,
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    color:
                        isSelected
                            ? color.withValues(alpha: 0.1)
                            : AppColors.surfaceVariant,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isSelected ? color : AppColors.border,
                      width: isSelected ? 2 : 1,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        type == AdjustmentType.stockIn
                            ? Icons.add_circle_outline_rounded
                            : Icons.remove_circle_outline_rounded,
                        color: isSelected ? color : AppColors.textSecondary,
                        size: 18,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        type.label,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: isSelected ? color : AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
    );
  }
}

// Reason Dropdown
class _ReasonDropdown extends StatelessWidget {
  final AdjustmentReason selected;
  final ValueChanged<AdjustmentReason> onChanged;

  const _ReasonDropdown({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<AdjustmentReason>(
      initialValue: selected,
      decoration: const InputDecoration(),
      items:
          AdjustmentReason.values.map((reason) {
            return DropdownMenuItem(value: reason, child: Text(reason.label));
          }).toList(),
      onChanged: (val) {
        if (val != null) onChanged(val);
      },
    );
  }
}

// Stock Preview Card
class _StockPreviewCard extends StatelessWidget {
  final int currentStock;
  final int newStock;
  final AdjustmentType type;

  const _StockPreviewCard({
    required this.currentStock,
    required this.newStock,
    required this.type,
  });

  @override
  Widget build(BuildContext context) {
    final isNegative = newStock < 0;
    final color =
        isNegative
            ? AppColors.error
            : type == AdjustmentType.stockIn
            ? AppColors.success
            : AppColors.warning;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Current
          _StockNum(
            label: 'Current',
            value: currentStock,
            color: AppColors.textSecondary,
          ),

          // Arrow
          Icon(Icons.arrow_forward_rounded, color: color),

          // New
          _StockNum(label: 'New Stock', value: newStock, color: color),

          // Warning agar negative
          if (isNegative)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text(
                '⚠️ Override',
                style: TextStyle(
                  fontSize: 11,
                  color: AppColors.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _StockNum extends StatelessWidget {
  final String label;
  final int value;
  final Color color;

  const _StockNum({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 4),
        Text(
          '$value',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }
}

// Section Label — consistent styling
class _SectionLabel extends StatelessWidget {
  final String text;

  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
      ),
    );
  }
}
