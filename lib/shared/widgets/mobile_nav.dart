import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_strings.dart';
import '../../core/entitlements/entitlement_provider.dart';
import '../../core/authorization/permission_provider.dart';
import '../../core/authorization/branch_permission_shadow_provider.dart';
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
    final mobileServiceViewAccess = ref.watch(
      permissionAccessProvider('mobile_service.transaction.view'),
    );
    final mobileServiceCreateAccess = ref.watch(
      permissionAccessProvider('mobile_service.transaction.create'),
    );
    final mobileServicePermissionResolved =
        mobileServiceViewAccess.hasValue && mobileServiceCreateAccess.hasValue;
    final mobileServicePermissionAllowed =
        mobileServiceViewAccess.value?.isAllowed == true ||
        mobileServiceCreateAccess.value?.isAllowed == true;
    final dashboardAccess = ref.watch(
      branchAwarePermissionProvider('dashboard.overview.view'),
    );
    final dashboardLockedByPermission =
        dashboardAccess.hasValue && dashboardAccess.value != true;
    final inventoryAccess = ref.watch(
      branchAwarePermissionProvider('inventory.product.view'),
    );
    final inventoryLockedByPermission =
        inventoryAccess.hasValue && inventoryAccess.value != true;
    final items = <
      ({int originalIndex, String? path, Widget destination, bool enabled})
    >[
      (
        originalIndex: 0,
        path: '/dashboard',
        enabled: enabled['dashboard.access']! && !dashboardLockedByPermission,
        destination: NavigationDestination(
          icon: _LockedNavIcon(
            icon: Icons.grid_view_rounded,
            locked:
                !enabled['dashboard.access']! || dashboardLockedByPermission,
          ),
          label: AppStrings.navDashboard,
        ),
      ),
      (
        originalIndex: 1,
        path: '/inventory',
        enabled: enabled['inventory.access']! && !inventoryLockedByPermission,
        destination: NavigationDestination(
          icon: _LockedNavIcon(
            icon: Icons.inventory_2_outlined,
            locked:
                !enabled['inventory.access']! || inventoryLockedByPermission,
          ),
          selectedIcon: const Icon(Icons.inventory_2_rounded),
          label: AppStrings.navInventory,
        ),
      ),
      (
        originalIndex: 2,
        path: '/pos',
        enabled: enabled['pos.access']!,
        destination: NavigationDestination(
          icon: _LockedNavIcon(
            icon: Icons.point_of_sale_outlined,
            locked: !enabled['pos.access']!,
          ),
          selectedIcon: const Icon(Icons.point_of_sale_rounded),
          label: AppStrings.navPos,
        ),
      ),
      (
        originalIndex: 3,
        path: '/repairs',
        enabled: enabled['repairs.access']!,
        destination: NavigationDestination(
          icon: _LockedNavIcon(
            icon: Icons.build_outlined,
            locked: !enabled['repairs.access']!,
          ),
          selectedIcon: const Icon(Icons.build_rounded),
          label: AppStrings.navRepairs,
        ),
      ),
      (
        originalIndex: 4,
        path: null,
        enabled: true,
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
              showMobileServices:
                  !mobileServicePermissionResolved ||
                  mobileServicePermissionAllowed,
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
    required bool showMobileServices,
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
                  ListTile(
                    leading: const Icon(
                      Icons.people_rounded,
                      color: AppColors.primary,
                    ),
                    title: const Text(
                      AppStrings.navCustomers,
                      style: TextStyle(color: AppColors.primary),
                    ),
                    trailing:
                        enabled['customers.access']!
                            ? null
                            : const Icon(Icons.lock_outline_rounded),
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      ref.read(navigationLoadingProvider.notifier).showFor();
                      context.go('/customers');
                    },
                  ),
                  ListTile(
                    leading: const Icon(
                      Icons.local_shipping_rounded,
                      color: AppColors.primary,
                    ),
                    title: const Text(
                      AppStrings.navSuppliers,
                      style: TextStyle(color: AppColors.primary),
                    ),
                    trailing:
                        enabled['suppliers.access']!
                            ? null
                            : const Icon(Icons.lock_outline_rounded),
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      ref.read(navigationLoadingProvider.notifier).showFor();
                      context.go('/suppliers');
                    },
                  ),
                  ListTile(
                    leading: const Icon(
                      Icons.receipt_long_rounded,
                      color: AppColors.primary,
                    ),
                    title: const Text(
                      AppStrings.navExpenses,
                      style: TextStyle(color: AppColors.primary),
                    ),
                    trailing:
                        enabled['expenses.access']!
                            ? null
                            : const Icon(Icons.lock_outline_rounded),
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      ref.read(navigationLoadingProvider.notifier).showFor();
                      context.go('/expenses');
                    },
                  ),
                  ListTile(
                    leading: const Icon(
                      Icons.account_balance_wallet_rounded,
                      color: AppColors.primary,
                    ),
                    title: const Text(
                      AppStrings.navAccounts,
                      style: TextStyle(color: AppColors.primary),
                    ),
                    trailing:
                        enabled['accounts.access']!
                            ? null
                            : const Icon(Icons.lock_outline_rounded),
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      ref.read(navigationLoadingProvider.notifier).showFor();
                      context.go('/accounts');
                    },
                  ),
                  if (showMobileServices)
                    ListTile(
                      leading: const Icon(
                        Icons.swap_horiz_rounded,
                        color: AppColors.primary,
                      ),
                      title: const Text(
                        AppStrings.navMobileServices,
                        style: TextStyle(color: AppColors.primary),
                      ),
                      trailing:
                          enabled['mobile_services.access']!
                              ? null
                              : const Icon(Icons.lock_outline_rounded),
                      onTap: () {
                        Navigator.of(sheetContext).pop();
                        ref.read(navigationLoadingProvider.notifier).showFor();
                        context.go('/mobile-services');
                      },
                    ),
                  ListTile(
                    leading: const Icon(
                      Icons.insights_rounded,
                      color: AppColors.primary,
                    ),
                    title: const Text(
                      AppStrings.navReports,
                      style: TextStyle(color: AppColors.primary),
                    ),
                    trailing:
                        enabled['reports.access']!
                            ? null
                            : const Icon(Icons.lock_outline_rounded),
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      ref.read(navigationLoadingProvider.notifier).showFor();
                      context.go('/reports');
                    },
                  ),
                  ListTile(
                    leading: const Icon(
                      Icons.settings_rounded,
                      color: AppColors.primary,
                    ),
                    title: const Text(
                      AppStrings.navSettings,
                      style: TextStyle(color: AppColors.primary),
                    ),
                    trailing:
                        enabled['settings.access']!
                            ? null
                            : const Icon(Icons.lock_outline_rounded),
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

class _LockedNavIcon extends StatelessWidget {
  final IconData icon;
  final bool locked;

  const _LockedNavIcon({required this.icon, required this.locked});

  @override
  Widget build(BuildContext context) {
    if (!locked) return Icon(icon);
    return Badge(
      label: const Icon(Icons.lock, size: 9, color: Colors.white),
      child: Icon(icon, color: Theme.of(context).disabledColor),
    );
  }
}
