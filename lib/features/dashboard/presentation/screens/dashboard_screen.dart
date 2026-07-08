import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

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
          onRefresh: () async => ref.invalidate(dashboardStatsProvider),
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _DashboardHeader(compact: true),
                if (errorMessage != null) ...[
                  const SizedBox(height: 14),
                  _DashboardError(message: errorMessage),
                ],
                const SizedBox(height: 20),
                _StatsGrid(
                  stats: stats,
                  isLoading: isLoading,
                  crossAxisCount: 2,
                  childAspectRatio: 1.32,
                  compact: true,
                ),
                const SizedBox(height: 20),
                const _QuickActions(compact: true),
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
        onRefresh: () async => ref.invalidate(dashboardStatsProvider),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _DashboardHeader(),
              if (errorMessage != null) ...[
                const SizedBox(height: 18),
                _DashboardError(message: errorMessage),
              ],
              const SizedBox(height: 28),
              _StatsGrid(
                stats: stats,
                isLoading: isLoading,
                crossAxisCount: 3,
                childAspectRatio: 3.3,
              ),
              const SizedBox(height: 28),
              const _QuickActions(),
              const SizedBox(height: 28),
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
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              compact ? AppStrings.dashboardWelcome : AppStrings.dashboardTitle,
              style: TextStyle(
                fontSize: compact ? 13 : 24,
                fontWeight: compact ? FontWeight.normal : FontWeight.bold,
                color:
                    compact ? AppColors.textSecondary : AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              compact ? 'Ali Mobile Center' : 'Aaj ka overview dekhen',
              style: TextStyle(
                fontSize: compact ? 20 : 14,
                fontWeight: compact ? FontWeight.bold : FontWeight.normal,
                color:
                    compact ? AppColors.textPrimary : AppColors.textSecondary,
              ),
            ),
          ],
        ),
        CircleAvatar(
          backgroundColor: AppColors.primary.withValues(alpha: 0.1),
          child: Icon(
            compact ? Icons.notifications_outlined : Icons.person_rounded,
            color: AppColors.primary,
          ),
        ),
      ],
    );
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
          title: AppStrings.dashboardOverallProfit,
          value: _moneyOrLoading(stats?.totalProfit, isLoading),
          icon: Icons.stacked_line_chart_rounded,
          color: AppColors.secondary,
          isCompact: compact,
        ),
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
      ),
      const QuickActionButton(
        label: AppStrings.actionAddProduct,
        icon: Icons.add_box_rounded,
        route: '/inventory/add',
      ),
      const QuickActionButton(
        label: AppStrings.actionNewRepair,
        icon: Icons.build_circle_rounded,
        route: '/repairs/new',
      ),
      const QuickActionButton(
        label: AppStrings.actionAddExpense,
        icon: Icons.receipt_rounded,
        route: '/expenses/add',
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          AppStrings.dashboardQuickActions,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        if (compact) ...[
          Row(
            children: [
              Expanded(child: actions[0]),
              const SizedBox(width: 12),
              Expanded(child: actions[1]),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: actions[2]),
              const SizedBox(width: 12),
              Expanded(child: actions[3]),
            ],
          ),
        ] else
          Row(
            children: [
              actions[0],
              const SizedBox(width: 12),
              actions[1],
              const SizedBox(width: 12),
              actions[2],
              const SizedBox(width: 12),
              actions[3],
            ],
          ),
      ],
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
              : Text(
                '$customerCount log',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
      child: Column(
        children: [
          if (stats != null)
            _DueSummary(
              totalOutstanding: stats!.totalOutstanding,
              totalCreditSales: stats!.totalCreditSales,
            ),
          if (customers.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 28),
              child: Text(
                'Abhi kisi customer ka udhar pending nahi',
                style: TextStyle(color: AppColors.textSecondary),
              ),
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
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.account_balance_wallet_rounded,
            color: AppColors.warning,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _money(totalOutstanding),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
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

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
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
                radius: 18,
                backgroundColor: AppColors.warning.withValues(alpha: 0.12),
                child: Text(
                  customer.fullName.trim().isEmpty
                      ? '?'
                      : customer.fullName.trim()[0].toUpperCase(),
                  style: const TextStyle(
                    color: AppColors.warning,
                    fontWeight: FontWeight.bold,
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
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _money(customer.outstandingBalance),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: AppColors.error,
                    ),
                  ),
                  const SizedBox(height: 6),
                  OutlinedButton.icon(
                    onPressed: () => _sendReminder(context, customer),
                    icon: const Icon(Icons.chat_bubble_outline_rounded),
                    label: const Text(AppStrings.dashboardSendReminder),
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      foregroundColor: AppColors.success,
                      side: const BorderSide(color: AppColors.success),
                    ),
                  ),
                ],
              ),
            ],
          ),
          if (progress != null) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                minHeight: 5,
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
              ? const Padding(
                padding: EdgeInsets.symmetric(vertical: 28),
                child: Center(
                  child: Text(
                    'Abhi koi sale nahi hui',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                ),
              )
              : Column(
                children:
                    recentSales
                        .map(
                          (sale) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Invoice #${sale.id?.substring(0, 8).toUpperCase() ?? 'SALE'}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: AppColors.textPrimary,
                                        ),
                                      ),
                                      if (sale.customerName != null)
                                        Text(
                                          sale.customerName!,
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
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
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
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 14),
          child,
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
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        message,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: AppColors.error),
      ),
    );
  }
}

String _money(double amount) => 'Rs ${amount.toStringAsFixed(0)}';

String _moneyOrLoading(double? amount, bool isLoading) {
  if (isLoading && amount == null) return '...';
  return _money(amount ?? 0);
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
