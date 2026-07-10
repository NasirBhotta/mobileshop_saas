import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_strings.dart';
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

  static const _tabs = [
    '/dashboard',
    '/pos',
    '/inventory',
    '/customers',
    '/repairs',
    '/suppliers',
    '/expenses',
    '/reports',
    '/settings',
  ];

  static const _items = [
    (icon: Icons.grid_view_rounded, label: AppStrings.navDashboard),
    (icon: Icons.point_of_sale_rounded, label: AppStrings.navPos),
    (icon: Icons.inventory_2_rounded, label: AppStrings.navInventory),
    (icon: Icons.people_rounded, label: AppStrings.navCustomers),
    (icon: Icons.build_rounded, label: AppStrings.navRepairs),
    (icon: Icons.local_shipping_rounded, label: AppStrings.navSuppliers),
    (icon: Icons.receipt_long_rounded, label: AppStrings.navExpenses),
    (icon: Icons.insights_rounded, label: AppStrings.navReports),
    (icon: Icons.settings_rounded, label: AppStrings.navSettings),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final setupStatus = ref.watch(setupFlowStatusProvider);
    final hasMultipleBranches = setupStatus.maybeWhen(
      data: (status) => status.branches.length >= 2,
      orElse: () => false,
    );

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
                    itemCount: _items.length,
                    itemBuilder: (context, index) {
                      final item = _items[index];
                      final isSelected = currentIndex == index;

                      return Container(
                        margin: const EdgeInsets.only(bottom: 4),
                        decoration: BoxDecoration(
                          color:
                              isSelected
                                  ? AppColors.primary.withValues(alpha: 0.1)
                                  : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                        ),
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
                                  isSelected
                                      ? AppColors.primary
                                      : AppColors.textSecondary,
                            ),
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
                                    context.go(_tabs[index]);
                                  },
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
