import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_strings.dart';
import '../../features/onboarding/data/repositories/setup_flow_repository.dart';
import '../providers/navigation_loading_provider.dart';

class MobileNav extends ConsumerWidget {
  final Widget child;
  final int currentIndex;

  const MobileNav({super.key, required this.child, required this.currentIndex});

  static const _tabs = [
    '/dashboard',
    '/inventory',
    '/pos',
    '/repairs',
    '/more',
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final setupStatus = ref.watch(setupFlowStatusProvider);
    final hasMultipleBranches = setupStatus.maybeWhen(
      data: (status) => status.branches.length >= 2,
      orElse: () => false,
    );

    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: currentIndex,
        backgroundColor: AppColors.surface,
        indicatorColor: AppColors.primary.withValues(alpha: 0.12),
        onDestinationSelected: (index) {
          if (index == 4) {
            _showMoreSheet(
              context,
              ref,
              hasMultipleBranches: hasMultipleBranches,
            );
            return;
          }

          if (index == currentIndex) return;

          ref.read(navigationLoadingProvider.notifier).showFor();
          context.go(_tabs[index]);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.grid_view_rounded),
            label: AppStrings.navDashboard,
          ),
          NavigationDestination(
            icon: Icon(Icons.inventory_2_outlined),
            selectedIcon: Icon(Icons.inventory_2_rounded),
            label: AppStrings.navInventory,
          ),
          NavigationDestination(
            icon: Icon(Icons.point_of_sale_outlined),
            selectedIcon: Icon(Icons.point_of_sale_rounded),
            label: AppStrings.navPos,
          ),
          NavigationDestination(
            icon: Icon(Icons.build_outlined),
            selectedIcon: Icon(Icons.build_rounded),
            label: AppStrings.navRepairs,
          ),
          NavigationDestination(
            icon: Icon(Icons.more_horiz_rounded),
            label: AppStrings.navMore,
          ),
        ],
      ),
    );
  }

  Future<void> _showMoreSheet(
    BuildContext context,
    WidgetRef ref, {
    required bool hasMultipleBranches,
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
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      ref.read(navigationLoadingProvider.notifier).showFor();
                      context.go('/accounts');
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
