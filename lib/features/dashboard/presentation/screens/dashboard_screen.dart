import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/utils/responsive.dart';
import '../providers/dashboard_provider.dart';
import '../widgets/quick_action_button.dart';
import '../widgets/stat_card.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Responsive.isDesktop(context)
        ? const _DesktopDashboard()
        : const _MobileDashboard();
  }
}

// ════════════════════════════════════════
// MOBILE DASHBOARD
// ════════════════════════════════════════
class _MobileDashboard extends ConsumerWidget {
  const _MobileDashboard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashboardStats = ref.watch(dashboardStatsProvider);
    final totalStock = dashboardStats.maybeWhen(
      data: (stats) => stats.totalStock.toString(),
      loading: () => '...',
      orElse: () => '0',
    );
    final lowStock = dashboardStats.maybeWhen(
      data: (stats) => stats.lowStock.toString(),
      loading: () => '...',
      orElse: () => '0',
    );
    final activeRepairs = dashboardStats.maybeWhen(
      data: (stats) => stats.activeRepairCount.toString(),
      loading: () => '...',
      orElse: () => '0',
    );
    final todaySales = dashboardStats.maybeWhen(
      data: (stats) => 'Rs ${stats.todaySalesTotal.toStringAsFixed(0)}',
      loading: () => '...',
      orElse: () => 'Rs 0',
    );

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header ──
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text(
                        AppStrings.dashboardWelcome,
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      Text(
                        'Ali Mobile Center', // Supabase se aayega baad mein
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                  CircleAvatar(
                    backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                    child: const Icon(
                      Icons.notifications_outlined,
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // ── Stats Grid (2x2) ──
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 1.4,
                children: [
                  StatCard(
                    title: AppStrings.dashboardTodaySales,
                    value: todaySales,
                    icon: Icons.trending_up_rounded,
                    color: AppColors.success,
                    isCompact: true,
                  ),
                  StatCard(
                    title: AppStrings.dashboardTotalStock,
                    value: totalStock,
                    icon: Icons.inventory_2_rounded,
                    color: AppColors.primary,
                    isCompact: true,
                  ),
                  StatCard(
                    title: AppStrings.dashboardActiveRepairs,
                    value: activeRepairs,
                    icon: Icons.build_rounded,
                    color: AppColors.warning,
                    isCompact: true,
                  ),
                  StatCard(
                    title: AppStrings.dashboardLowStock,
                    value: lowStock,
                    icon: Icons.warning_amber_rounded,
                    color: AppColors.error,
                    isCompact: true,
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // ── Quick Actions ──
              const Text(
                AppStrings.dashboardQuickActions,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 12),

              Row(
                children: const [
                  Expanded(
                    child: QuickActionButton(
                      label: AppStrings.actionNewSale,
                      icon: Icons.add_shopping_cart_rounded,
                      route: '/pos',
                    ),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: QuickActionButton(
                      label: AppStrings.actionAddProduct,
                      icon: Icons.add_box_rounded,
                      route: '/inventory/add',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: const [
                  Expanded(
                    child: QuickActionButton(
                      label: AppStrings.actionNewRepair,
                      icon: Icons.build_circle_rounded,
                      route: '/repairs/new',
                    ),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: QuickActionButton(
                      label: AppStrings.actionAddExpense,
                      icon: Icons.receipt_rounded,
                      route: '/expenses/add',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════
// DESKTOP DASHBOARD
// ════════════════════════════════════════
class _DesktopDashboard extends ConsumerWidget {
  const _DesktopDashboard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashboardStats = ref.watch(dashboardStatsProvider);
    final totalStock = dashboardStats.maybeWhen(
      data: (stats) => stats.totalStock.toString(),
      loading: () => '...',
      orElse: () => '0',
    );
    final lowStock = dashboardStats.maybeWhen(
      data: (stats) => stats.lowStock.toString(),
      loading: () => '...',
      orElse: () => '0',
    );
    final activeRepairs = dashboardStats.maybeWhen(
      data: (stats) => stats.activeRepairCount.toString(),
      loading: () => '...',
      orElse: () => '0',
    );
    final todaySales = dashboardStats.maybeWhen(
      data: (stats) => 'Rs ${stats.todaySalesTotal.toStringAsFixed(0)}',
      loading: () => '...',
      orElse: () => 'Rs 0',
    );
    final recentSales = dashboardStats.maybeWhen(
      data: (stats) => stats.recentSales,
      orElse: () => const [],
    );

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ──
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text(
                      AppStrings.dashboardTitle,
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Aaj ka overview dekhen',
                      style: TextStyle(
                        fontSize: 14,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
                // Notification + Profile
                Row(
                  children: [
                    IconButton(
                      onPressed: () {},
                      icon: const Icon(
                        Icons.notifications_outlined,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    CircleAvatar(
                      backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                      child: const Icon(
                        Icons.person_rounded,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 28),

            // ── Stats Row (4 cards, horizontal) ──
            Row(
              children: [
                Expanded(
                  child: StatCard(
                    title: AppStrings.dashboardTodaySales,
                    value: todaySales,
                    icon: Icons.trending_up_rounded,
                    color: AppColors.success,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: StatCard(
                    title: AppStrings.dashboardTotalStock,
                    value: totalStock,
                    icon: Icons.inventory_2_rounded,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: StatCard(
                    title: AppStrings.dashboardActiveRepairs,
                    value: activeRepairs,
                    icon: Icons.build_rounded,
                    color: AppColors.warning,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: StatCard(
                    title: AppStrings.dashboardLowStock,
                    value: lowStock,
                    icon: Icons.warning_amber_rounded,
                    color: AppColors.error,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 28),

            // ── Quick Actions ──
            const Text(
              AppStrings.dashboardQuickActions,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: const [
                QuickActionButton(
                  label: AppStrings.actionNewSale,
                  icon: Icons.add_shopping_cart_rounded,
                  route: '/pos',
                ),
                SizedBox(width: 12),
                QuickActionButton(
                  label: AppStrings.actionAddProduct,
                  icon: Icons.add_box_rounded,
                  route: '/inventory/add',
                ),
                SizedBox(width: 12),
                QuickActionButton(
                  label: AppStrings.actionNewRepair,
                  icon: Icons.build_circle_rounded,
                  route: '/repairs/new',
                ),
                SizedBox(width: 12),
                QuickActionButton(
                  label: AppStrings.actionAddExpense,
                  icon: Icons.receipt_rounded,
                  route: '/expenses/add',
                ),
              ],
            ),
            const SizedBox(height: 28),

            // ── Recent Sales Table (Desktop only) ──
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    AppStrings.dashboardRecentSales,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Placeholder — baad mein Supabase se data aayega
                  if (recentSales.isEmpty)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 32),
                        child: Text(
                          'Abhi koi sale nahi hui',
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                      ),
                    )
                  else
                    ...recentSales.map(
                      (sale) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Invoice #${sale.id?.substring(0, 8).toUpperCase() ?? 'SALE'}',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                            ),
                            Text(
                              'Rs ${sale.total.toStringAsFixed(0)}',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: AppColors.success,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
