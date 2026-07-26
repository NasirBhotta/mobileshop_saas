import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/authorization/permission_locked_screen.dart';
import '../../../../core/authorization/branch_permission_shadow_provider.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/utils/responsive.dart';
import '../../../../core/extensions/repair_ticket_ext.dart';
import '../../../repairs/data/models/repair_ticket_model.dart';
import '../../../settings/presentation/widgets/account_menu_button.dart';
import '../providers/dashboard_provider.dart';
import '../widgets/quick_action_button.dart';
import '../widgets/stat_card.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final access = ref.watch(
      branchAwarePermissionProvider('dashboard.overview.view'),
    );

    return access.when(
      loading:
          () => const Scaffold(
            backgroundColor: AppColors.background,
            body: Center(child: CircularProgressIndicator()),
          ),
      error:
          (_, _) => const PermissionLockedScreen(
            moduleName: 'Dashboard',
            accountAction: AccountMenuButton(),
          ),
      data:
          (isAllowed) =>
              isAllowed
                  ? Responsive.isDesktop(context)
                      ? const _DesktopDashboard()
                      : const _MobileDashboard()
                  : const PermissionLockedScreen(
                    moduleName: 'Dashboard',
                    accountAction: AccountMenuButton(),
                  ),
    );
  }
}

class _MobileDashboard extends ConsumerWidget {
  const _MobileDashboard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashboardStats = ref.watch(dashboardStatsProvider);
    final stats = dashboardStats.maybeWhen<DashboardStats?>(
      data: (stats) => stats,
      orElse: () => null,
    );
    final isLoading = dashboardStats.maybeWhen(
      loading: () => true,
      orElse: () => false,
    );
    final errorMessage = dashboardStats.maybeWhen<String?>(
      error: (error, _) => error.toString(),
      orElse: () => null,
    );

    return Scaffold(
      backgroundColor: AppColors.background,

      body: SafeArea(
        child: RefreshIndicator(
          color: AppColors.primary,
          onRefresh: () => refreshDashboardData(ref),
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _DashboardHeader(compact: true),
                if (errorMessage != null) ...[
                  const SizedBox(height: 14),
                  _DashboardError(message: errorMessage),
                ],
                const SizedBox(height: 18),
                _TodaySnapshot(stats: stats, isLoading: isLoading),
                const SizedBox(height: 20),
                const _QuickActions(compact: true),
                const SizedBox(height: 20),
                _DashboardAlerts(
                  stats: stats,
                  isLoading: isLoading,
                  compact: true,
                ),
                const SizedBox(height: 20),
                _PriorityRepairsPanel(stats: stats, compact: true),
                const SizedBox(height: 20),
                _StatsGrid(
                  stats: stats,
                  isLoading: isLoading,
                  crossAxisCount: 2,
                  childAspectRatio: 1.18,
                  compact: true,
                ),
                const SizedBox(height: 20),
                _CreditCustomersPanel(stats: stats, compact: true),
                const SizedBox(height: 20),
                _RecentSalesPanel(stats: stats, compact: true),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DesktopDashboard extends ConsumerWidget {
  const _DesktopDashboard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashboardStats = ref.watch(dashboardStatsProvider);
    final stats = dashboardStats.maybeWhen<DashboardStats?>(
      data: (stats) => stats,
      orElse: () => null,
    );
    final isLoading = dashboardStats.maybeWhen(
      loading: () => true,
      orElse: () => false,
    );
    final errorMessage = dashboardStats.maybeWhen<String?>(
      error: (error, _) => error.toString(),
      orElse: () => null,
    );

    return Scaffold(
      backgroundColor: AppColors.background,
      body: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: () => refreshDashboardData(ref),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(28, 24, 28, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _DashboardHeader(),
              if (errorMessage != null) ...[
                const SizedBox(height: 18),
                _DashboardError(message: errorMessage),
              ],
              const SizedBox(height: 22),
              _TodaySnapshot(
                stats: stats,
                isLoading: isLoading,
                compact: false,
              ),
              const SizedBox(height: 22),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Expanded(flex: 5, child: _QuickActions()),
                  const SizedBox(width: 18),
                  Expanded(
                    flex: 4,
                    child: _DashboardAlerts(stats: stats, isLoading: isLoading),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              _PriorityRepairsPanel(stats: stats),
              const SizedBox(height: 22),
              _StatsGrid(
                stats: stats,
                isLoading: isLoading,
                crossAxisCount: 4,
                childAspectRatio: 2.25,
              ),
              const SizedBox(height: 22),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 5, child: _CreditCustomersPanel(stats: stats)),
                  const SizedBox(width: 20),
                  Expanded(flex: 4, child: _RecentSalesPanel(stats: stats)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DashboardHeader extends StatelessWidget {
  final bool compact;

  const _DashboardHeader({this.compact = false});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 6,
                    height: compact ? 14 : 20,
                    decoration: BoxDecoration(
                      color: AppColors.secondary,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    compact
                        ? AppStrings.dashboardWelcome
                        : AppStrings.dashboardTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: compact ? 12.5 : 25,
                      fontWeight: compact ? FontWeight.w600 : FontWeight.w800,
                      letterSpacing: compact ? 0.4 : -0.3,
                      color:
                          compact
                              ? AppColors.textSecondary
                              : AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 5),
              Padding(
                padding: EdgeInsets.only(left: compact ? 14 : 14),
                child: Text(
                  compact
                      ? _weekdayLabel(now)
                      : 'Aaj ka sales, stock aur udhar overview',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: compact ? 21 : 14.5,
                    fontWeight: compact ? FontWeight.w800 : FontWeight.w500,
                    letterSpacing: compact ? -0.4 : 0,
                    color:
                        compact
                            ? AppColors.textPrimary
                            : AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        const AccountMenuButton(),
      ],
    );
  }
}

class _TodaySnapshot extends StatelessWidget {
  final DashboardStats? stats;
  final bool isLoading;
  final bool compact;

  const _TodaySnapshot({
    required this.stats,
    required this.isLoading,
    this.compact = true,
  });

  @override
  Widget build(BuildContext context) {
    final cash = _moneyOrLoading(stats?.todaySalesTotal, isLoading);
    final profit = _moneyOrLoading(stats?.totalProfit, isLoading);
    final outstanding = _moneyOrLoading(stats?.totalOutstanding, isLoading);
    final activeRepairs =
        isLoading ? '...' : (stats?.activeRepairCount ?? 0).toString();

    return Container(
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: AppColors.heroGradient,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryDark.withValues(alpha: 0.28),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Stack(
        children: [
          // Ambient depth — soft glow tucked in the corner.
          Positioned(
            top: -40,
            right: -30,
            child: Container(
              width: 160,
              height: 160,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.06),
              ),
            ),
          ),
          Positioned(
            bottom: -60,
            left: -20,
            child: Container(
              width: 140,
              height: 140,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.secondary.withValues(alpha: 0.10),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.all(compact ? 18 : 22),
            child:
                compact
                    ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _SnapshotMainValue(value: cash),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: _SnapshotPill(
                                icon: Icons.stacked_line_chart_rounded,
                                label: 'Today profit',
                                value: profit,
                                color: AppColors.secondaryLight,
                                compact: true,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _SnapshotPill(
                                icon: Icons.account_balance_wallet_rounded,
                                label: 'Udhar',
                                value: outstanding,
                                color: const Color(0xFFFFB4A8),
                                compact: true,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _SnapshotPill(
                                icon: Icons.build_rounded,
                                label: 'Repairs',
                                value: activeRepairs,
                                color: const Color(0xFF9FD9FF),
                                compact: true,
                              ),
                            ),
                          ],
                        ),
                      ],
                    )
                    : Row(
                      children: [
                        Expanded(child: _SnapshotMainValue(value: cash)),
                        const SizedBox(width: 18),
                        _SnapshotPill(
                          icon: Icons.stacked_line_chart_rounded,
                          label: 'Today gross profit',
                          value: profit,
                          color: AppColors.secondaryLight,
                        ),
                        const SizedBox(width: 10),
                        _SnapshotPill(
                          icon: Icons.account_balance_wallet_rounded,
                          label: 'Total udhar',
                          value: outstanding,
                          color: const Color(0xFFFFB4A8),
                        ),
                        const SizedBox(width: 10),
                        _SnapshotPill(
                          icon: Icons.build_rounded,
                          label: 'Active repairs',
                          value: activeRepairs,
                          color: const Color(0xFF9FD9FF),
                        ),
                      ],
                    ),
          ),
        ],
      ),
    );
  }
}

class _SnapshotMainValue extends StatelessWidget {
  final String value;

  const _SnapshotMainValue({required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(11),
              ),
              child: const Icon(
                Icons.payments_rounded,
                color: Colors.white,
                size: 18,
              ),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'Today cash received',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.2,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 32,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.5,
              height: 1,
            ),
          ),
        ),
      ],
    );
  }
}

class _SnapshotPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final bool compact;

  const _SnapshotPill({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final container = Container(
      constraints: compact ? null : const BoxConstraints(minWidth: 122),
      width: compact ? double.infinity : null,
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 10 : 12,
        vertical: compact ? 10 : 11,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child:
          compact
              ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, color: color, size: 16),
                  const SizedBox(height: 7),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white60,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              )
              : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, color: color, size: 18),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white60,
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        Text(
                          value,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
    );

    return container;
  }
}

class _StatsGrid extends StatelessWidget {
  final DashboardStats? stats;
  final bool isLoading;
  final int crossAxisCount;
  final double childAspectRatio;
  final bool compact;

  const _StatsGrid({
    required this.stats,
    required this.isLoading,
    required this.crossAxisCount,
    required this.childAspectRatio,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: crossAxisCount,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: childAspectRatio,
      children: [
        StatCard(
          title: AppStrings.dashboardTodaySales,
          value: _moneyOrLoading(stats?.todaySalesTotal, isLoading),
          icon: Icons.trending_up_rounded,
          color: AppColors.success,
          isCompact: compact,
        ),
        StatCard(
          title: AppStrings.dashboardOverallSales,
          value: _moneyOrLoading(stats?.totalSalesTotal, isLoading),
          icon: Icons.payments_rounded,
          color: AppColors.primary,
          isCompact: compact,
        ),
        StatCard(
          title: 'Today Gross Profit',
          subtitle: 'Before expenses',
          value: _moneyOrLoading(stats?.totalProfit, isLoading),
          icon: Icons.stacked_line_chart_rounded,
          color: AppColors.secondaryDark,
          isCompact: compact,
        ),
        if (stats?.mobileServicesEnabled == true) ...[
          StatCard(
            title: 'Today Cash Paid',
            subtitle: 'Mobile Services',
            value: _moneyOrLoading(
              stats?.mobileServiceTodayCashPaid,
              isLoading,
            ),
            icon: Icons.money_off_csred_rounded,
            color: AppColors.error,
            isCompact: compact,
          ),
          StatCard(
            title: 'Net Service Cash',
            subtitle: 'Cash received − cash paid',
            value: _moneyOrLoading(stats?.mobileServiceTodayNetCash, isLoading),
            icon: Icons.account_balance_wallet_outlined,
            color: AppColors.info,
            isCompact: compact,
          ),
          StatCard(
            title: 'Wallet In',
            subtitle: 'Today • Easypaisa/JazzCash',
            value: _moneyOrLoading(
              stats?.mobileServiceTodayWalletIn,
              isLoading,
            ),
            icon: Icons.south_west_rounded,
            color: AppColors.success,
            isCompact: compact,
          ),
          StatCard(
            title: 'Wallet Out',
            subtitle: 'Today • Easypaisa/JazzCash',
            value: _moneyOrLoading(
              stats?.mobileServiceTodayWalletOut,
              isLoading,
            ),
            icon: Icons.north_east_rounded,
            color: AppColors.warning,
            isCompact: compact,
          ),
        ],
        StatCard(
          title: AppStrings.dashboardTotalUdhar,
          value: _moneyOrLoading(stats?.totalOutstanding, isLoading),
          icon: Icons.account_balance_wallet_rounded,
          color: AppColors.warning,
          isCompact: compact,
        ),
        StatCard(
          title: AppStrings.dashboardTotalStock,
          value: isLoading ? '...' : (stats?.totalStock ?? 0).toString(),
          icon: Icons.inventory_2_rounded,
          color: AppColors.info,
          isCompact: compact,
        ),
        StatCard(
          title: AppStrings.dashboardActiveRepairs,
          value: isLoading ? '...' : (stats?.activeRepairCount ?? 0).toString(),
          icon: Icons.build_rounded,
          color: AppColors.primary,
          isCompact: compact,
        ),
        StatCard(
          title: AppStrings.dashboardLowStock,
          value: isLoading ? '...' : (stats?.lowStock ?? 0).toString(),
          icon: Icons.warning_amber_rounded,
          color: AppColors.error,
          isCompact: compact,
        ),
      ],
    );
  }
}

class _QuickActions extends StatelessWidget {
  final bool compact;

  const _QuickActions({this.compact = false});

  @override
  Widget build(BuildContext context) {
    final actions = [
      const QuickActionButton(
        label: AppStrings.actionNewSale,
        icon: Icons.add_shopping_cart_rounded,
        route: '/pos',
        color: AppColors.success,
      ),
      const QuickActionButton(
        label: AppStrings.actionAddProduct,
        icon: Icons.add_box_rounded,
        route: '/inventory/add',
        color: AppColors.info,
      ),
      const QuickActionButton(
        label: AppStrings.actionNewRepair,
        icon: Icons.build_circle_rounded,
        route: '/repairs/new',
        color: AppColors.warning,
      ),
      const QuickActionButton(
        label: AppStrings.actionAddExpense,
        icon: Icons.receipt_rounded,
        route: '/expenses/new',
        color: AppColors.error,
      ),
      const QuickActionButton(
        label: 'Customers',
        icon: Icons.people_rounded,
        route: '/customers',
        color: AppColors.secondaryDark,
      ),
      const QuickActionButton(
        label: 'Reports',
        icon: Icons.insights_rounded,
        route: '/reports',
        color: AppColors.primary,
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          AppStrings.dashboardQuickActions,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.1,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 13),
        if (compact) ...[
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 2.9,
            children: actions,
          ),
        ] else
          Wrap(spacing: 10, runSpacing: 10, children: actions),
      ],
    );
  }
}

class _DashboardAlerts extends StatelessWidget {
  final DashboardStats? stats;
  final bool isLoading;
  final bool compact;

  const _DashboardAlerts({
    required this.stats,
    required this.isLoading,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    if (stats == null && isLoading) {
      return const _DashboardPanel(
        title: 'Attention',
        trailing: _StatusBadge(label: 'Loading', color: AppColors.info),
        child: _EmptyPanelMessage(
          icon: Icons.hourglass_empty_rounded,
          message: 'Alerts load ho rahe hain.',
        ),
      );
    }

    if (stats == null) {
      return const _DashboardPanel(
        title: 'Attention',
        trailing: _StatusBadge(label: 'Unavailable', color: AppColors.error),
        child: _EmptyPanelMessage(
          icon: Icons.error_outline_rounded,
          message: 'Alerts load nahi ho sake. Pull down karke retry karein.',
        ),
      );
    }

    final alerts = <_DashboardAlertData>[
      if (stats!.lowStock > 0)
        _DashboardAlertData(
          icon: Icons.warning_amber_rounded,
          title: '${stats!.lowStock} low stock items',
          subtitle: 'Inventory review kar lein',
          route: '/inventory',
          color: AppColors.error,
        ),
      if (stats!.totalOutstanding > 0)
        _DashboardAlertData(
          icon: Icons.account_balance_wallet_rounded,
          title: _money(stats!.totalOutstanding),
          subtitle: 'Udhar follow-up pending',
          route: '/customers',
          color: AppColors.warning,
        ),
      if (stats!.activeRepairCount > 0)
        _DashboardAlertData(
          icon: Icons.build_rounded,
          title: '${stats!.activeRepairCount} active repairs',
          subtitle: 'Repair queue check karein',
          route: '/repairs',
          color: AppColors.info,
        ),
    ];

    return _DashboardPanel(
      title: 'Attention',
      trailing:
          alerts.isEmpty
              ? const _StatusBadge(label: 'All clear', color: AppColors.success)
              : _StatusBadge(
                label: '${alerts.length} items',
                color: AppColors.warning,
              ),
      child:
          alerts.isEmpty
              ? const _EmptyPanelMessage(
                icon: Icons.check_circle_outline_rounded,
                message: 'Aaj ke liye koi urgent alert nahi.',
              )
              : Column(
                children: [
                  for (var i = 0; i < alerts.length; i++) ...[
                    _DashboardAlertTile(data: alerts[i], compact: compact),
                    if (i != alerts.length - 1) const SizedBox(height: 10),
                  ],
                ],
              ),
    );
  }
}

class _PriorityRepairsPanel extends StatelessWidget {
  final DashboardStats? stats;
  final bool compact;

  const _PriorityRepairsPanel({required this.stats, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final tickets = stats?.priorityRepairs ?? const <RepairTicketModel>[];

    return _DashboardPanel(
      title: 'Repair priority',
      trailing: _StatusBadge(
        label: tickets.isEmpty ? 'Clear' : '${tickets.length} pending',
        color: tickets.isEmpty ? AppColors.success : AppColors.warning,
      ),
      child:
          tickets.isEmpty
              ? const _EmptyPanelMessage(
                icon: Icons.build_circle_outlined,
                message: 'Koi priority repair pending nahi.',
              )
              : Column(
                children: [
                  for (var index = 0; index < tickets.length; index++) ...[
                    _PriorityRepairTile(
                      ticket: tickets[index],
                      compact: compact,
                    ),
                    if (index != tickets.length - 1) const Divider(height: 18),
                  ],
                ],
              ),
    );
  }
}

class _PriorityRepairTile extends StatelessWidget {
  final RepairTicketModel ticket;
  final bool compact;

  const _PriorityRepairTile({required this.ticket, required this.compact});

  @override
  Widget build(BuildContext context) {
    final ready = ticket.status == RepairTicketStatus.completed;
    final color = ready ? AppColors.success : _repairDueColor(ticket);

    return InkWell(
      onTap: () => context.go('/repairs'),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 4 : 8,
          vertical: compact ? 6 : 8,
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(
                ready ? Icons.inventory_rounded : Icons.build_rounded,
                color: color,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${ticket.deviceBrand} ${ticket.deviceModel}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${ticket.customerName} • ${_repairPriorityLabel(ticket)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              ticket.ticketNo ?? 'Ticket',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right_rounded, size: 20),
          ],
        ),
      ),
    );
  }
}

String _repairPriorityLabel(RepairTicketModel ticket) {
  if (ticket.status == RepairTicketStatus.completed) {
    return 'Ready for delivery';
  }

  final due = ticket.estimatedCompletionAt;
  if (due == null) return '${ticket.status.label} • No due date';

  final now = DateTime.now();
  final difference = due.difference(now);
  if (difference.isNegative) return 'Overdue';
  if (difference.inHours < 1) return 'Due within 1 hour';
  if (difference.inHours < 24) return 'Due in ${difference.inHours}h';
  if (difference.inDays == 1) return 'Due tomorrow';
  return 'Due in ${difference.inDays} days';
}

Color _repairDueColor(RepairTicketModel ticket) {
  final due = ticket.estimatedCompletionAt;
  if (due == null) return AppColors.info;
  final difference = due.difference(DateTime.now());
  if (difference.isNegative || difference.inHours < 24) {
    return AppColors.error;
  }
  if (difference.inHours < 72) return AppColors.warning;
  return AppColors.info;
}

class _DashboardAlertData {
  final IconData icon;
  final String title;
  final String subtitle;
  final String route;
  final Color color;

  const _DashboardAlertData({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.route,
    required this.color,
  });
}

class _DashboardAlertTile extends StatelessWidget {
  final _DashboardAlertData data;
  final bool compact;

  const _DashboardAlertTile({required this.data, required this.compact});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => context.go(data.route),
        borderRadius: BorderRadius.circular(12),
        child: Ink(
          decoration: BoxDecoration(
            color: data.color.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: data.color.withValues(alpha: 0.14)),
          ),
          child: IntrinsicHeight(
            child: Row(
              children: [
                Container(
                  width: 4,
                  decoration: BoxDecoration(
                    color: data.color,
                    borderRadius: const BorderRadius.horizontal(
                      left: Radius.circular(12),
                    ),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: compact ? 12 : 14,
                      vertical: compact ? 12 : 14,
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 18,
                          backgroundColor: data.color.withValues(alpha: 0.14),
                          foregroundColor: data.color,
                          child: Icon(data.icon, size: 18),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                data.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 14,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              Text(
                                data.subtitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          Icons.chevron_right_rounded,
                          color: data.color.withValues(alpha: 0.7),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CreditCustomersPanel extends StatelessWidget {
  final DashboardStats? stats;
  final bool compact;

  const _CreditCustomersPanel({required this.stats, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final customers = stats?.creditCustomers ?? const [];
    final customerCount = customers.length;

    return _DashboardPanel(
      title: AppStrings.dashboardUdharCustomers,
      trailing:
          stats == null
              ? null
              : _StatusBadge(
                label: '$customerCount log',
                color: AppColors.textSecondary,
              ),
      child: Column(
        children: [
          if (stats != null)
            _DueSummary(
              totalOutstanding: stats!.totalOutstanding,
              totalCreditSales: stats!.totalCreditSales,
            ),
          if (customers.isEmpty)
            const _EmptyPanelMessage(
              icon: Icons.check_circle_outline_rounded,
              message: 'Abhi kisi customer ka udhar pending nahi.',
            )
          else
            ...customers.map(
              (customer) =>
                  _CreditCustomerTile(customer: customer, compact: compact),
            ),
        ],
      ),
    );
  }
}

class _DueSummary extends StatelessWidget {
  final double totalOutstanding;
  final double totalCreditSales;

  const _DueSummary({
    required this.totalOutstanding,
    required this.totalCreditSales,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.16)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: AppColors.warning.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.account_balance_wallet_rounded,
              color: AppColors.warning,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _money(totalOutstanding),
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.3,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Total udhar sales: ${_money(totalCreditSales)}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CreditCustomerTile extends StatelessWidget {
  final DashboardCreditCustomer customer;
  final bool compact;

  const _CreditCustomerTile({required this.customer, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final limit = customer.creditLimit;
    final progress =
        limit == null || limit <= 0
            ? null
            : (customer.outstandingBalance / limit).clamp(0.0, 1.0);
    final amountAndAction = Column(
      crossAxisAlignment:
          compact ? CrossAxisAlignment.start : CrossAxisAlignment.end,
      children: [
        Text(
          _money(customer.outstandingBalance),
          style: const TextStyle(
            fontSize: 14.5,
            fontWeight: FontWeight.w800,
            color: AppColors.error,
          ),
        ),
        const SizedBox(height: 7),
        OutlinedButton.icon(
          onPressed: () => _sendReminder(context, customer),
          icon: const Icon(Icons.chat_bubble_outline_rounded, size: 16),
          label: const Text(AppStrings.dashboardSendReminder),
          style: OutlinedButton.styleFrom(
            visualDensity: VisualDensity.compact,
            foregroundColor: AppColors.success,
            side: const BorderSide(color: AppColors.success),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
      ],
    );

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 19,
                backgroundColor: AppColors.warning.withValues(alpha: 0.14),
                child: Text(
                  customer.fullName.trim().isEmpty
                      ? '?'
                      : customer.fullName.trim()[0].toUpperCase(),
                  style: const TextStyle(
                    color: AppColors.warning,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      customer.fullName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      customer.phone?.trim().isNotEmpty == true
                          ? customer.phone!
                          : 'Phone number missing',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              if (!compact) ...[const SizedBox(width: 10), amountAndAction],
            ],
          ),
          if (compact) ...[const SizedBox(height: 10), amountAndAction],
          if (progress != null) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                minHeight: 6,
                value: progress,
                backgroundColor: AppColors.divider,
                valueColor: AlwaysStoppedAnimation<Color>(
                  progress >= 0.9 ? AppColors.error : AppColors.warning,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Limit ${_money(limit ?? 0)}',
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _RecentSalesPanel extends StatelessWidget {
  final DashboardStats? stats;
  final bool compact;

  const _RecentSalesPanel({required this.stats, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final recentSales = stats?.recentSales ?? const [];
    return _DashboardPanel(
      title: AppStrings.dashboardRecentSales,
      child:
          recentSales.isEmpty
              ? const _EmptyPanelMessage(
                icon: Icons.point_of_sale_rounded,
                message: 'Abhi koi sale nahi hui.',
              )
              : Column(
                children:
                    recentSales
                        .map(
                          (sale) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 9),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  radius: 18,
                                  backgroundColor: AppColors.success.withValues(
                                    alpha: 0.12,
                                  ),
                                  foregroundColor: AppColors.success,
                                  child: const Icon(
                                    Icons.receipt_long_rounded,
                                    size: 17,
                                  ),
                                ),
                                const SizedBox(width: 11),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _saleLabel(sale.id),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700,
                                          color: AppColors.textPrimary,
                                        ),
                                      ),
                                      if (sale.customerName != null)
                                        Text(
                                          '${sale.customerName!} · ${_formatDateTime(sale.createdAt)}',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: AppColors.textSecondary,
                                          ),
                                        ),
                                      if (sale.customerName == null)
                                        Text(
                                          _formatDateTime(sale.createdAt),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: AppColors.textSecondary,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                Text(
                                  _money(sale.total),
                                  style: const TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.success,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                        .toList(),
              ),
    );
  }
}

class _DashboardPanel extends StatelessWidget {
  final String title;
  final Widget child;
  final Widget? trailing;

  const _DashboardPanel({
    required this.title,
    required this.child,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        boxShadow: AppColors.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 4,
                height: 16,
                margin: const EdgeInsets.only(right: 9),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.1,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String label;
  final Color color;

  const _StatusBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyPanelMessage extends StatelessWidget {
  final IconData icon;
  final String message;

  const _EmptyPanelMessage({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 26),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.surface,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.border),
            ),
            child: Icon(icon, color: AppColors.textSecondary, size: 22),
          ),
          const SizedBox(height: 10),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _DashboardError extends StatelessWidget {
  final String message;

  const _DashboardError({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.16)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: AppColors.error,
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.error,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _money(double amount) => 'Rs ${_compactNumber(amount)}';

String _moneyOrLoading(double? amount, bool isLoading) {
  if (isLoading && amount == null) return '...';
  return _money(amount ?? 0);
}

String _compactNumber(double amount) {
  final isNegative = amount < 0;
  final rounded = amount.abs().round().toString();
  final buffer = StringBuffer();

  for (var i = 0; i < rounded.length; i++) {
    final positionFromEnd = rounded.length - i;
    buffer.write(rounded[i]);
    if (positionFromEnd > 1 && positionFromEnd % 3 == 1) {
      buffer.write(',');
    }
  }

  return isNegative ? '-$buffer' : buffer.toString();
}

String _saleLabel(String? id) {
  if (id == null || id.isEmpty) return 'Invoice #SALE';

  final code = id.length <= 8 ? id : id.substring(0, 8);
  return 'Invoice #${code.toUpperCase()}';
}

String _formatDateTime(DateTime? value) {
  if (value == null) return 'No time';

  final now = DateTime.now();
  final isToday =
      value.year == now.year &&
      value.month == now.month &&
      value.day == now.day;

  final hour =
      value.hour == 0
          ? 12
          : value.hour > 12
          ? value.hour - 12
          : value.hour;
  final minute = value.minute.toString().padLeft(2, '0');
  final suffix = value.hour >= 12 ? 'PM' : 'AM';

  if (isToday) return 'Today $hour:$minute $suffix';
  return '${value.day}/${value.month}/${value.year}';
}

String _weekdayLabel(DateTime value) {
  const weekdays = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];
  return '${weekdays[value.weekday - 1]} overview';
}

Future<void> _sendReminder(
  BuildContext context,
  DashboardCreditCustomer customer,
) async {
  final message = _reminderMessage(customer);
  final phone = _normalizeWhatsAppPhone(customer.phone);

  try {
    if (phone.isNotEmpty) {
      final uri = Uri.parse(
        'https://wa.me/$phone?text=${Uri.encodeComponent(message)}',
      );
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (launched) return;
    }

    await _shareReminder(customer, message);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Reminder share karne ke liye ready hai')),
      );
    }
  } catch (_) {
    await _shareReminder(customer, message);
  }
}

Future<void> _shareReminder(DashboardCreditCustomer customer, String message) {
  return SharePlus.instance.share(
    ShareParams(
      text: message,
      subject: 'Payment reminder for ${customer.fullName}',
    ),
  );
}

String _reminderMessage(DashboardCreditCustomer customer) {
  return 'Assalam o Alaikum ${customer.fullName}, '
      'aap ka udhar ${_money(customer.outstandingBalance)} pending hai. '
      'Barah-e-karam payment clear kar dein. Shukriya.';
}

String _normalizeWhatsAppPhone(String? phone) {
  final raw = phone?.trim();
  if (raw == null || raw.isEmpty) return '';

  final digits = raw.replaceAll(RegExp(r'\D'), '');
  if (digits.isEmpty) return '';
  if (digits.startsWith('00')) return digits.substring(2);
  if (digits.startsWith('0')) return '92${digits.substring(1)}';
  return digits;
}
