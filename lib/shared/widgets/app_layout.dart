import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/responsive.dart';
import '../providers/navigation_loading_provider.dart';
import 'desktop_nav.dart';
import 'loading_overlay.dart';
import 'mobile_nav.dart';

class AppLayout extends ConsumerWidget {
  final Widget child;
  final int currentIndex;

  const AppLayout({super.key, required this.child, required this.currentIndex});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isNavigating = ref.watch(navigationLoadingProvider);
    final layout =
        Responsive.isDesktop(context)
            ? DesktopNav(currentIndex: currentIndex, child: child)
            : MobileNav(
              currentIndex: _mobileIndexForDesktopIndex(currentIndex),
              child: child,
            );

    return LoadingOverlay(isLoading: isNavigating, child: layout);
  }

  int _mobileIndexForDesktopIndex(int index) {
    return switch (index) {
      1 => 2, // POS
      2 => 1, // Inventory
      3 => 4, // Customers live under More on mobile
      4 => 3, // Repairs
      5 => 4, // Suppliers live under More on mobile
      6 => 4, // Expenses live under More on mobile
      7 => 4, // Accounts live under More on mobile
      8 => 4, // Reports live under More on mobile
      9 => 4, // Settings live under More on mobile
      _ => index,
    };
  }
}
