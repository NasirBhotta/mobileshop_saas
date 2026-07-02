import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_strings.dart';
import '../../features/auth/presentation/providers/auth_provider.dart';

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

    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: currentIndex,
        backgroundColor: AppColors.surface,
        indicatorColor: AppColors.primary.withValues(alpha: 0.12),
        onDestinationSelected: (index) {
          if (index == 4) {
            _showMoreSheet(context, ref, isLoggingOut);
            return;
          }

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
    WidgetRef ref,
    bool isLoggingOut,
  ) async {
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
                    enabled: !isLoggingOut,
                    leading:
                        isLoggingOut
                            ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(strokeWidth: 2),
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
                      await _confirmLogout(context, ref);
                    },
                  ),
                ],
              ),
            ),
          ),
    );
  }

  Future<void> _confirmLogout(BuildContext context, WidgetRef ref) async {
    final shouldLogout = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text(AppStrings.logoutTitle),
            content: const Text(AppStrings.logoutMessage),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text(AppStrings.cancel),
              ),
              FilledButton.icon(
                onPressed: () => Navigator.of(context).pop(true),
                icon: const Icon(Icons.logout_rounded, size: 18),
                label: const Text(AppStrings.logout),
              ),
            ],
          ),
    );

    if (shouldLogout != true || !context.mounted) return;

    final loggedOut = await ref.read(authControllerProvider.notifier).logout();
    if (!context.mounted) return;

    if (loggedOut) {
      context.go('/login');
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(AppStrings.somethingWentWrong)),
      );
    }
  }
}
