import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_strings.dart';
import '../../features/auth/presentation/providers/auth_provider.dart';
import '../../features/onboarding/data/repositories/setup_flow_repository.dart';
import '../providers/navigation_loading_provider.dart';
import 'logout_action.dart';

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
    final isLoggingOut = ref.watch(authControllerProvider).isLoading;
    final setupStatus = ref.watch(setupFlowStatusProvider);
    final hasMultipleBranches = setupStatus.maybeWhen(
      data: (status) => status.branches.length >= 2,
      orElse: () => false,
    );
    final showLogout = setupStatus.maybeWhen(
      data: (status) => status.branches.length < 2,
      error: (_, _) => true,
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
              isLoggingOut: isLoggingOut,
              hasMultipleBranches: hasMultipleBranches,
              showLogout: showLogout,
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
    required bool isLoggingOut,
    required bool hasMultipleBranches,
    required bool showLogout,
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
                  if (showLogout)
                    ListTile(
                      enabled: !isLoggingOut,
                      leading:
                          isLoggingOut
                              ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                              : const Icon(
                                Icons.logout_rounded,
                                color: AppColors.error,
                              ),
                      title: const Text(
                        AppStrings.logout,
                        style: TextStyle(color: AppColors.error),
                      ),
                      onTap: () async {
                        Navigator.of(sheetContext).pop();
                        await confirmLogout(context, ref);
                      },
                    ),
                ],
              ),
            ),
          ),
    );
  }
}
