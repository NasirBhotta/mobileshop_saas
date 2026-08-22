import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:mobileshop_saas/core/constants/app_colors.dart';
import 'package:mobileshop_saas/core/utils/responsive.dart';
import 'package:mobileshop_saas/features/buyin/data/models/customer_purchase_model.dart';
import 'package:mobileshop_saas/features/buyin/data/services/buyin_thermal_receipt_service.dart';
import 'package:mobileshop_saas/features/buyin/presentation/providers/customer_purchase_provider.dart';
import 'package:mobileshop_saas/features/settings/presentation/providers/receipt_settings_provider.dart';

class CustomerPurchasesListScreen extends ConsumerStatefulWidget {
  const CustomerPurchasesListScreen({super.key});

  @override
  ConsumerState<CustomerPurchasesListScreen> createState() => _CustomerPurchasesListScreenState();
}

class _CustomerPurchasesListScreenState extends ConsumerState<CustomerPurchasesListScreen> {
  final _searchController = TextEditingController();
  String _selectedStatusFilter = 'all';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final purchasesAsync = ref.watch(customerPurchasesProvider);
    final isDesktop = Responsive.isDesktop(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Second-Hand Buy-In & Legal Records'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
            onPressed: () => ref.invalidate(customerPurchasesProvider),
          ),
          if (isDesktop) ...[
            const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsets.only(right: 16.0),
              child: FilledButton.icon(
                onPressed: () => context.go('/buyin/new'),
                icon: const Icon(Icons.add_rounded),
                label: const Text('New Buy-In Intake'),
              ),
            ),
          ],
        ],
      ),
      floatingActionButton: isDesktop
          ? null
          : FloatingActionButton.extended(
              onPressed: () => context.go('/buyin/new'),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Buy-In Phone'),
            ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async => ref.invalidate(customerPurchasesProvider),
          child: ListView(
            padding: EdgeInsets.symmetric(
              horizontal: isDesktop ? 32.0 : 16.0,
              vertical: 16.0,
            ),
            children: [
              _buildSearchBar(),
              const SizedBox(height: 12),
              purchasesAsync.when(
                data: (purchases) {
                  return Column(
                    children: [
                      _buildSummaryCards(purchases),
                      const SizedBox(height: 16),
                      _buildFilterChips(),
                      const SizedBox(height: 12),
                      _buildPurchasesList(purchases),
                    ],
                  );
                },
                loading: () => const Center(
                  child: Padding(
                    padding: EdgeInsets.all(48.0),
                    child: CircularProgressIndicator(),
                  ),
                ),
                error: (e, _) => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32.0),
                    child: Column(
                      children: [
                        const Icon(Icons.error_outline_rounded, color: AppColors.error, size: 40),
                        const SizedBox(height: 8),
                        Text('Error loading purchase records: $e'),
                        const SizedBox(height: 8),
                        OutlinedButton(
                          onPressed: () => ref.invalidate(customerPurchasesProvider),
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return TextField(
      controller: _searchController,
      decoration: InputDecoration(
        hintText: 'Search by IMEI, Seller CNIC, Phone, or Device Model...',
        prefixIcon: const Icon(Icons.search_rounded),
        suffixIcon: _searchController.text.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.clear_rounded),
                onPressed: () {
                  _searchController.clear();
                  ref.read(customerPurchasesQueryProvider.notifier).state = '';
                },
              )
            : null,
        filled: true,
        fillColor: Theme.of(context).cardColor,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.withAlpha(50)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.withAlpha(50)),
        ),
      ),
      onChanged: (val) {
        ref.read(customerPurchasesQueryProvider.notifier).state = val.trim();
      },
    );
  }

  Widget _buildSummaryCards(List<CustomerPurchaseModel> purchases) {
    final currencyFormat = NumberFormat('#,##0', 'en_US');
    final totalSpent = purchases.fold<double>(0.0, (acc, p) => acc + p.purchasePrice);
    final inStockCount = purchases.where((p) => p.status == 'in_stock').length;
    final soldCount = purchases.where((p) => p.status == 'sold').length;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 600;
        final cardWidth = isNarrow ? (constraints.maxWidth - 10) / 2 : (constraints.maxWidth - 30) / 4;

        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _buildStatTile(
              title: 'Total Buy-Ins',
              value: '${purchases.length}',
              icon: Icons.inventory_2_rounded,
              color: AppColors.primary,
              width: cardWidth,
            ),
            _buildStatTile(
              title: 'Total Investment',
              value: 'Rs. ${currencyFormat.format(totalSpent)}',
              icon: Icons.account_balance_wallet_rounded,
              color: Colors.teal,
              width: cardWidth,
            ),
            _buildStatTile(
              title: 'Available In Stock',
              value: '$inStockCount',
              icon: Icons.check_circle_outline_rounded,
              color: Colors.green,
              width: cardWidth,
            ),
            _buildStatTile(
              title: 'Sold via POS',
              value: '$soldCount',
              icon: Icons.sell_rounded,
              color: Colors.blueGrey,
              width: cardWidth,
            ),
          ],
        );
      },
    );
  }

  Widget _buildStatTile({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    required double width,
  }) {
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color.withAlpha(15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withAlpha(40)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChips() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          ChoiceChip(
            label: const Text('All Purchases'),
            selected: _selectedStatusFilter == 'all',
            onSelected: (_) => setState(() => _selectedStatusFilter = 'all'),
          ),
          const SizedBox(width: 8),
          ChoiceChip(
            label: const Text('In Stock'),
            selected: _selectedStatusFilter == 'in_stock',
            onSelected: (_) => setState(() => _selectedStatusFilter = 'in_stock'),
          ),
          const SizedBox(width: 8),
          ChoiceChip(
            label: const Text('Sold via POS'),
            selected: _selectedStatusFilter == 'sold',
            onSelected: (_) => setState(() => _selectedStatusFilter = 'sold'),
          ),
        ],
      ),
    );
  }

  Widget _buildPurchasesList(List<CustomerPurchaseModel> purchases) {
    final filtered = purchases.where((p) {
      if (_selectedStatusFilter == 'in_stock') return p.status == 'in_stock';
      if (_selectedStatusFilter == 'sold') return p.status == 'sold';
      return true;
    }).toList();

    if (filtered.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(40.0),
          child: Column(
            children: const [
              Icon(Icons.receipt_long_outlined, size: 48, color: Colors.grey),
              SizedBox(height: 12),
              Text(
                'No buy-in purchase records found.',
                style: TextStyle(fontSize: 15, color: AppColors.textSecondary),
              ),
              SizedBox(height: 4),
              Text(
                'Click "New Buy-In Intake" to purchase a used mobile from customer.',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    final currencyFormat = NumberFormat('#,##0.00', 'en_US');
    final dateFormat = DateFormat('dd MMM yyyy, hh:mm a');

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: filtered.length,
      separatorBuilder: (context, index) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final item = filtered[index];
        final isSold = item.status == 'sold';

        return Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: Colors.grey.withAlpha(50)),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            leading: CircleAvatar(
              backgroundColor: isSold ? Colors.blueGrey.withAlpha(30) : AppColors.primary.withAlpha(30),
              child: Icon(
                Icons.phone_iphone_rounded,
                color: isSold ? Colors.blueGrey : AppColors.primary,
              ),
            ),
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    item.productName,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: isSold ? Colors.blueGrey.withAlpha(30) : Colors.green.withAlpha(30),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    isSold ? 'SOLD' : 'IN STOCK',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: isSold ? Colors.blueGrey : Colors.green,
                    ),
                  ),
                ),
              ],
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Text(
                  'IMEI: ${item.imei1} • CNIC: ${item.sellerCnic}',
                  style: const TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 2),
                Text(
                  'Seller: ${item.sellerName} (${item.sellerPhone}) • ${dateFormat.format(item.createdAt.toLocal())}',
                  style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 4),
                Text(
                  'Cost Paid: Rs. ${currencyFormat.format(item.purchasePrice)}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
            trailing: PopupMenuButton<String>(
              onSelected: (action) async {
                if (action == 'print') {
                  final config = await ref.read(receiptConfigurationProvider.future);
                  await BuyInThermalReceiptService.printBuyInAgreement(
                    purchase: item,
                    config: config,
                  );
                } else if (action == 'share') {
                  await BuyInThermalReceiptService.shareBuyInText(item);
                } else if (action == 'details') {
                  _showDetailsDialog(item);
                } else if (action == 'delete') {
                  _confirmDeletePurchase(item);
                }
              },
              itemBuilder: (ctx) => [
                const PopupMenuItem(
                  value: 'details',
                  child: ListTile(
                    leading: Icon(Icons.info_outline_rounded),
                    title: Text('View Details'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                const PopupMenuItem(
                  value: 'print',
                  child: ListTile(
                    leading: Icon(Icons.print_rounded),
                    title: Text('Print Agreement'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                const PopupMenuItem(
                  value: 'share',
                  child: ListTile(
                    leading: Icon(Icons.share_rounded),
                    title: Text('Share Agreement'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                const PopupMenuDivider(),
                const PopupMenuItem(
                  value: 'delete',
                  child: ListTile(
                    leading: Icon(Icons.delete_outline_rounded, color: Colors.red),
                    title: Text('Delete Log', style: TextStyle(color: Colors.red)),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),
            onTap: () => _showDetailsDialog(item),
          ),
        );
      },
    );
  }

  void _showDetailsDialog(CustomerPurchaseModel purchase) {
    final currencyFormat = NumberFormat('#,##0.00', 'en_US');
    final dateFormat = DateFormat('dd-MMM-yyyy hh:mm a');

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              const Icon(Icons.verified_rounded, color: AppColors.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  purchase.productName,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _detailRow('Seller Name', purchase.sellerName, isBold: true),
                  _detailRow('CNIC Number', purchase.sellerCnic, isBold: true),
                  _detailRow('Phone Number', purchase.sellerPhone),
                  const Divider(height: 20),
                  const Text('DEVICE DETAILS', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 4),
                  _detailRow('IMEI 1', purchase.imei1, isBold: true),
                  if (purchase.imei2 != null) _detailRow('IMEI 2', purchase.imei2!),
                  if (purchase.color != null) _detailRow('Color', purchase.color!),
                  if (purchase.storage != null) _detailRow('Storage', purchase.storage!),
                  if (purchase.deviceCondition != null) _detailRow('Condition', purchase.deviceCondition!),
                  if (purchase.accessories != null) _detailRow('Accessories', purchase.accessories!),
                  const Divider(height: 20),
                  const Text('FINANCIALS', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 4),
                  _detailRow('Cost Paid', 'Rs. ${currencyFormat.format(purchase.purchasePrice)}', isBold: true),
                  if (purchase.expectedSalePrice > 0)
                    _detailRow('Expected Sale', 'Rs. ${currencyFormat.format(purchase.expectedSalePrice)}'),
                  if (purchase.paymentMethod != null) _detailRow('Payment Mode', purchase.paymentMethod!.toUpperCase()),
                  _detailRow('Date Intake', dateFormat.format(purchase.createdAt.toLocal())),
                  if (purchase.notes != null) ...[
                    const SizedBox(height: 8),
                    _detailRow('Remarks', purchase.notes!),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton.icon(
              onPressed: () {
                Navigator.of(ctx).pop();
                _confirmDeletePurchase(purchase);
              },
              icon: const Icon(Icons.delete_outline_rounded, color: Colors.red, size: 18),
              label: const Text('Delete Log', style: TextStyle(color: Colors.red)),
            ),
            const Spacer(),
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
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  void _confirmDeletePurchase(CustomerPurchaseModel purchase) {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red),
            SizedBox(width: 8),
            Text('Delete Buy-In Log?'),
          ],
        ),
        content: Text(
          'Are you sure you want to delete the buy-in intake log for "${purchase.productName}" (IMEI: ${purchase.imei1})?\n\n'
          'Note: The device and stock in your inventory will remain safe and intact.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              Navigator.of(dialogCtx).pop();
              final success = await ref
                  .read(customerPurchaseControllerProvider.notifier)
                  .deletePurchase(purchase.id);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      success
                          ? 'Buy-in log deleted successfully (Inventory retained).'
                          : 'Failed to delete buy-in log.',
                    ),
                    backgroundColor: success ? Colors.green : Colors.red,
                  ),
                );
              }
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value, {bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const Text(': '),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
