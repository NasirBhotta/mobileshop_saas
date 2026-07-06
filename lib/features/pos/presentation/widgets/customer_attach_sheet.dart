import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_strings.dart';
import '../providers/pos_provider.dart';

void showCustomerSheet(BuildContext context, WidgetRef ref) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => CustomerAttachSheet(ref: ref),
  );
}

class CustomerAttachSheet extends ConsumerStatefulWidget {
  final WidgetRef ref;

  const CustomerAttachSheet({super.key, required this.ref});

  @override
  ConsumerState<CustomerAttachSheet> createState() =>
      _CustomerAttachSheetState();
}

class _CustomerAttachSheetState extends ConsumerState<CustomerAttachSheet> {
  final _searchCtrl = TextEditingController();
  String _query = '';
  bool _showAddForm = false;

  // Add form controllers
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        16,
        20,
        MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),

          // Title
          Row(
            children: [
              const Text(
                AppStrings.attachCustomer,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              const Spacer(),
              // Remove customer button
              if (ref.read(cartProvider).customer != null)
                TextButton(
                  onPressed: () {
                    ref.read(cartProvider.notifier).detachCustomer();
                    Navigator.pop(context);
                  },
                  child: const Text(
                    'Remove',
                    style: TextStyle(color: AppColors.error),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),

          if (!_showAddForm) ...[
            // Search field
            TextField(
              controller: _searchCtrl,
              onChanged: (val) => setState(() => _query = val),
              decoration: InputDecoration(
                hintText: AppStrings.customerSearch,
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
              ),
            ),
            const SizedBox(height: 12),

            // Search results
            if (_query.length >= 2)
              _CustomerSearchResults(
                query: _query,
                onSelected: (customer) {
                  ref.read(cartProvider.notifier).attachCustomer(customer);
                  Navigator.pop(context);
                },
              ),

            const SizedBox(height: 8),

            // Quick add button
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => setState(() => _showAddForm = true),
                icon: const Icon(Icons.person_add_outlined, size: 18),
                label: const Text(AppStrings.quickAddCustomer),
              ),
            ),
          ] else ...[
            // Add form
            TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                labelText: AppStrings.fieldCustomerName,
                hintText: AppStrings.hintCustomerName,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _phoneCtrl,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: AppStrings.fieldCustomerPhone,
                hintText: '03XX-XXXXXXX',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _emailCtrl,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: AppStrings.fieldCustomerEmail,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => setState(() => _showAddForm = false),
                    child: const Text('Back'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () => _addCustomer(context),
                    child: const Text('Add & Attach'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _addCustomer(BuildContext context) async {
    if (_nameCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(AppStrings.errorCustomerNameRequired),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    final customer = await ref
        .read(customerControllerProvider.notifier)
        .addCustomer(
          fullName: _nameCtrl.text.trim(),
          phone: _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim(),
          email: _emailCtrl.text.trim().isEmpty ? null : _emailCtrl.text.trim(),
        );

    if (customer != null && context.mounted) {
      ref.read(cartProvider.notifier).attachCustomer(customer);
      Navigator.pop(context);
    }
  }
}

// Search Results Widget
class _CustomerSearchResults extends ConsumerWidget {
  final String query;
  final ValueChanged<dynamic> onSelected;

  const _CustomerSearchResults({required this.query, required this.onSelected});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resultsAsync = ref.watch(customerSearchProvider(query));

    return resultsAsync.when(
      loading:
          () => const Center(
            child: Padding(
              padding: EdgeInsets.all(8),
              child: CircularProgressIndicator(),
            ),
          ),
      error: (e, _) => const SizedBox.shrink(),
      data: (customers) {
        if (customers.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text(
              AppStrings.customerNotFound,
              style: TextStyle(color: AppColors.textSecondary),
            ),
          );
        }

        return Column(
          children:
              customers.map((customer) {
                return ListTile(
                  dense: true,
                  leading: CircleAvatar(
                    backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                    child: Text(
                      customer.fullName[0].toUpperCase(),
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  title: Text(customer.fullName),
                  subtitle:
                      customer.phone != null ? Text(customer.phone!) : null,
                  onTap: () => onSelected(customer),
                );
              }).toList(),
        );
      },
    );
  }
}
