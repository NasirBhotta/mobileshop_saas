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

class DesktopNav extends ConsumerWidget {
  final Widget child;
  final int currentIndex;

  const DesktopNav({
    super.key,
    required this.child,
    required this.currentIndex,
  });

  static const _items = [
    (
      icon: Icons.grid_view_rounded,
      label: AppStrings.navDashboard,
      path: '/dashboard',
      feature: 'dashboard.access',
    ),
    (
      icon: Icons.point_of_sale_rounded,
      label: AppStrings.navPos,
      path: '/pos',
      feature: 'pos.access',
    ),
    (
      icon: Icons.inventory_2_rounded,
      label: AppStrings.navInventory,
      path: '/inventory',
      feature: 'inventory.access',
    ),
    (
      icon: Icons.people_rounded,
      label: AppStrings.navCustomers,
      path: '/customers',
      feature: 'customers.access',
    ),
    (
      icon: Icons.build_rounded,
      label: AppStrings.navRepairs,
      path: '/repairs',
      feature: 'repairs.access',
    ),
    (
      icon: Icons.assignment_turned_in_rounded,
      label: 'Used Buy-In',
      path: '/buyin',
      feature: 'inventory.access',
    ),
    (
      icon: Icons.local_shipping_rounded,
      label: AppStrings.navSuppliers,
      path: '/suppliers',
      feature: 'suppliers.access',
    ),
    (
      icon: Icons.receipt_long_rounded,
      label: AppStrings.navExpenses,
      path: '/expenses',
      feature: 'expenses.access',
    ),
    (
      icon: Icons.account_balance_wallet_rounded,
      label: AppStrings.navAccounts,
      path: '/accounts',
      feature: 'accounts.access',
    ),
    (
      icon: Icons.swap_horiz_rounded,
      label: AppStrings.navMobileServices,
      path: '/mobile-services',
      feature: 'mobile_services.access',
    ),
    (
      icon: Icons.insights_rounded,
      label: AppStrings.navReports,
      path: '/reports',
      feature: 'reports.access',
    ),
    (
      icon: Icons.settings_rounded,
      label: AppStrings.navSettings,
      path: '/settings',
      feature: 'settings.access',
    ),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final setupStatus = ref.watch(setupFlowStatusProvider);
    final hasMultipleBranches = setupStatus.maybeWhen(
      data: (status) => status.branches.length >= 2,
      orElse: () => false,
    );
    final visibleItems =
        <
          ({
            int originalIndex,
            IconData icon,
            String label,
            String path,
            String feature,
            bool enabled,
          })
        >[];
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
    for (var index = 0; index < _items.length; index++) {
      final item = _items[index];
      final access = ref.watch(
        compatibleFeatureEntitlementProvider(item.feature),
      );
      if (item.path == '/mobile-services' &&
          mobileServicePermissionResolved &&
          !mobileServicePermissionAllowed) {
        continue;
      }
      visibleItems.add((
        originalIndex: index,
        icon: item.icon,
        label: item.label,
        path: item.path,
        feature: item.feature,
        enabled:
            access.value != false &&
            !(item.path == '/dashboard' && dashboardLockedByPermission) &&
            !(item.path == '/inventory' && inventoryLockedByPermission),
      ));
    }

    return Scaffold(
      body: Row(
        children: [
          // ── Side Navigation ──
          Container(
            width: 220,
            color: AppColors.surface,
            child: Column(
              children: [
                // Logo/App Name
                Container(
                  padding: const EdgeInsets.all(24),
                  child: Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.storefront_rounded,
                          color: Colors.white,
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Text(
                        AppStrings.appName,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),

                const Divider(height: 1),
                const SizedBox(height: 8),

                // Nav Items
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: visibleItems.length,
                    itemBuilder: (context, index) {
                      final item = visibleItems[index];
                      final isSelected = currentIndex == item.originalIndex;

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Material(
                          color:
                              isSelected
                                  ? AppColors.primary.withValues(alpha: 0.1)
                                  : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                          clipBehavior: Clip.antiAlias,
                          child: ListTile(
                            dense: true,
                            leading: Icon(
                              item.icon,
                              size: 20,
                              color:
                                  isSelected
                                      ? AppColors.primary
                                      : AppColors.textSecondary,
                            ),
                            title: Text(
                              item.label,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight:
                                    isSelected
                                        ? FontWeight.w600
                                        : FontWeight.normal,
                                color:
                                    !item.enabled
                                        ? AppColors.textSecondary.withValues(
                                          alpha: 0.55,
                                        )
                                        : isSelected
                                        ? AppColors.primary
                                        : AppColors.textSecondary,
                              ),
                            ),
                            trailing:
                                item.enabled
                                    ? null
                                    : const Icon(
                                      Icons.lock_outline_rounded,
                                      size: 17,
                                    ),
                            onTap:
                                isSelected
                                    ? null
                                    : () {
                                      ref
                                          .read(
                                            navigationLoadingProvider.notifier,
                                          )
                                          .showFor();
                                      context.go(item.path);
                                    },
                          ),
                        ),
                      );
                    },
                  ),
                ),

                const Divider(height: 1),

                // Shop name at bottom
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 16,
                            backgroundColor: AppColors.primary.withValues(
                              alpha: 0.1,
                            ),
                            child: const Icon(
                              Icons.store_rounded,
                              size: 16,
                              color: AppColors.primary,
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'Meri Dukaan', // baad mein Supabase se aayega
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (hasMultipleBranches) ...[
                        SizedBox(
                          width: double.infinity,
                          child: TextButton.icon(
                            onPressed: () {
                              ref
                                  .read(navigationLoadingProvider.notifier)
                                  .showFor();
                              context.go('/select-branch');
                            },
                            icon: const Icon(
                              Icons.storefront_rounded,
                              size: 18,
                            ),
                            label: const Text('Switch Branch'),
                            style: TextButton.styleFrom(
                              foregroundColor: AppColors.primary,
                              alignment: Alignment.centerLeft,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 10,
                              ),
                              textStyle: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ── Vertical Divider ──
          const VerticalDivider(width: 1),

          // ── Main Content ──
          Expanded(child: child),
        ],
      ),
    );
  }
}
