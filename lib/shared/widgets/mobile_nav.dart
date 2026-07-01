import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_strings.dart';

class MobileNav extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: currentIndex,
        backgroundColor: AppColors.surface,
        indicatorColor: AppColors.primary.withValues(alpha: 0.12),
        onDestinationSelected: (index) {
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
}
