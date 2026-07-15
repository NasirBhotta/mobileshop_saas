import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_strings.dart';
import '../../core/entitlements/entitlement_provider.dart';
import '../../features/onboarding/data/repositories/setup_flow_repository.dart';
import '../providers/navigation_loading_provider.dart';

class MobileNav extends ConsumerWidget {
  final Widget child;
  final int currentIndex;

  const MobileNav({super.key, required this.child, required this.currentIndex});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final setupStatus = ref.watch(setupFlowStatusProvider);
    final hasMultipleBranches = setupStatus.maybeWhen(
      data: (status) => status.branches.length >= 2,
      orElse: () => false,
    );
    final enabled = <String, bool>{};
    for (final key in routeFeatureEntitlements.values.toSet()) {
      enabled[key] = ref.watch(featureEntitlementProvider(key)).value != false;
    }
    for (final key in const [
      'repairs.tickets',
      'procurement.suppliers',
      'expenses.core',
      'accounts.core',
    ]) {
      enabled[key] =
          ref.watch(compatibleFeatureEntitlementProvider(key)).value != false;
    }
    final items = <({int originalIndex, String? path, Widget destination})>[
      if (enabled['dashboard.access']!)
        (
          originalIndex: 0,
          path: '/dashboard',
          destination: const NavigationDestination(
            icon: Icon(Icons.grid_view_rounded),
            label: AppStrings.navDashboard,
          ),
        ),
      if (enabled['inventory.access']!)
        (
          originalIndex: 1,
          path: '/inventory',
          destination: const NavigationDestination(
            icon: Icon(Icons.inventory_2_outlined),
            selectedIcon: Icon(Icons.inventory_2_rounded),
            label: AppStrings.navInventory,
          ),
        ),
      if (enabled['pos.access']!)
        (
          originalIndex: 2,
          path: '/pos',
          destination: const NavigationDestination(
            icon: Icon(Icons.point_of_sale_outlined),
            selectedIcon: Icon(Icons.point_of_sale_rounded),
            label: AppStrings.navPos,
          ),
        ),
      if (enabled['repairs.tickets']!)
        (
          originalIndex: 3,
          path: '/repairs',
          destination: const NavigationDestination(
            icon: Icon(Icons.build_outlined),
            selectedIcon: Icon(Icons.build_rounded),
            label: AppStrings.navRepairs,
          ),
        ),
      (
        originalIndex: 4,
        path: null,
        destination: const NavigationDestination(
          icon: Icon(Icons.more_horiz_rounded),
          label: AppStrings.navMore,
        ),
      ),
    ];
    final selected = items.indexWhere(
      (item) => item.originalIndex == currentIndex,
    );

    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: selected < 0 ? items.length - 1 : selected,
        backgroundColor: AppColors.surface,
        indicatorColor: AppColors.primary.withValues(alpha: 0.12),
        onDestinationSelected: (index) {
          final item = items[index];
          if (item.path == null) {
            _showMoreSheet(
              context,
              ref,
              hasMultipleBranches: hasMultipleBranches,
              enabled: enabled,
            );
            return;
          }

          if (item.originalIndex == currentIndex) return;

          ref.read(navigationLoadingProvider.notifier).showFor();
          context.go(item.path!);
        },
        destinations: items.map((item) => item.destination).toList(),
      ),
    );
  }

  Future<void> _showMoreSheet(
    BuildContext context,
    WidgetRef ref, {
    required bool hasMultipleBranches,
    required Map<String, bool> enabled,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder:
          (sheetContext) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (enabled['customers.access']!)
                    ListTile(
                      leading: const Icon(
                        Icons.people_rounded,
                        color: AppColors.primary,
                      ),
                      title: const Text(
                        AppStrings.navCustomers,
                        style: TextStyle(color: AppColors.primary),
                      ),
                      onTap: () {
                        Navigator.of(sheetContext).pop();
                        ref.read(navigationLoadingProvider.notifier).showFor();
                        context.go('/customers');
                      },
                    ),
                  if (enabled['procurement.suppliers']!)
                    ListTile(
                      leading: const Icon(
                        Icons.local_shipping_rounded,
                        color: AppColors.primary,
                      ),
                      title: const Text(
                        AppStrings.navSuppliers,
                        style: TextStyle(color: AppColors.primary),
                      ),
                      onTap: () {
                        Navigator.of(sheetContext).pop();
                        ref.read(navigationLoadingProvider.notifier).showFor();
                        context.go('/suppliers');
                      },
                    ),
                  if (enabled['expenses.core']!)
                    ListTile(
                      leading: const Icon(
                        Icons.receipt_long_rounded,
                        color: AppColors.primary,
                      ),
                      title: const Text(
                        AppStrings.navExpenses,
                        style: TextStyle(color: AppColors.primary),
                      ),
                      onTap: () {
                        Navigator.of(sheetContext).pop();
                        ref.read(navigationLoadingProvider.notifier).showFor();
                        context.go('/expenses');
                      },
                    ),
                  if (enabled['accounts.core']!)
                    ListTile(
                      leading: const Icon(
                        Icons.account_balance_wallet_rounded,
                        color: AppColors.primary,
                      ),
                      title: const Text(
                        AppStrings.navAccounts,
                        style: TextStyle(color: AppColors.primary),
                      ),
                      onTap: () {
                        Navigator.of(sheetContext).pop();
                        ref.read(navigationLoadingProvider.notifier).showFor();
                        context.go('/accounts');
                      },
                    ),
                  if (enabled['reports.access']!)
                    ListTile(
                      leading: const Icon(
                        Icons.insights_rounded,
                        color: AppColors.primary,
                      ),
                      title: const Text(
                        AppStrings.navReports,
                        style: TextStyle(color: AppColors.primary),
                      ),
                      onTap: () {
                        Navigator.of(sheetContext).pop();
                        ref.read(navigationLoadingProvider.notifier).showFor();
                        context.go('/reports');
                      },
                    ),
                  if (enabled['settings.access']!)
                    ListTile(
                      leading: const Icon(
                        Icons.settings_rounded,
                        color: AppColors.primary,
                      ),
                      title: const Text(
                        AppStrings.navSettings,
                        style: TextStyle(color: AppColors.primary),
                      ),
                      onTap: () {
                        Navigator.of(sheetContext).pop();
                        ref.read(navigationLoadingProvider.notifier).showFor();
                        context.go('/settings');
                      },
                    ),
                  if (hasMultipleBranches)
                    ListTile(
                      leading: const Icon(
                        Icons.storefront_rounded,
                        color: AppColors.primary,
                      ),
                      title: const Text(
                        'Switch Branch',
                        style: TextStyle(color: AppColors.primary),
                      ),
                      onTap: () {
                        Navigator.of(sheetContext).pop();
                        ref.read(navigationLoadingProvider.notifier).showFor();
                        context.go('/select-branch');
                      },
                    ),
                ],
              ),
            ),
          ),
    );
  }
}
