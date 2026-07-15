import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/entitlements/entitlement_provider.dart';

class ReportsHomeScreen extends ConsumerWidget {
  const ReportsHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final salesEnabled =
        ref.watch(reportFeatureEntitlementProvider('reports.sales')).value !=
        false;
    final businessEnabled =
        ref.watch(reportFeatureEntitlementProvider('reports.business')).value !=
        false;
    return Scaffold(
      appBar: AppBar(title: const Text('Reports')),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 900;

            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1180),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Choose Report Type',
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Sales reports are for POS activity. Business reports are for owner-level decisions across profit, inventory, cash flow, credit, and repairs.',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 16),
                        if (isWide)
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (salesEnabled)
                                const Expanded(child: _SalesReportsCard()),
                              if (salesEnabled && businessEnabled)
                                const SizedBox(width: 14),
                              if (businessEnabled)
                                const Expanded(child: _BusinessReportsCard()),
                            ],
                          )
                        else ...[
                          if (salesEnabled) const _SalesReportsCard(),
                          if (salesEnabled && businessEnabled)
                            const SizedBox(height: 14),
                          if (businessEnabled) const _BusinessReportsCard(),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _SalesReportsCard extends ConsumerWidget {
  const _SalesReportsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheduledEnabled =
        ref
            .watch(reportFeatureEntitlementProvider('reports.scheduled'))
            .value !=
        false;
    return _ReportGroupCard(
      icon: Icons.point_of_sale_outlined,
      title: 'Sales Reports',
      subtitle:
          'POS sales, product performance, customer sales, branch revenue, exports, and scheduled sales emails.',
      primaryLabel: 'Open Sales Analytics',
      primaryRoute: '/reports/sales',
      links: [
        const _ReportLink(
          icon: Icons.analytics_outlined,
          label: 'Sales Analytics',
          route: '/reports/sales',
        ),
        if (scheduledEnabled)
          const _ReportLink(
            icon: Icons.schedule_send_outlined,
            label: 'Scheduled Sales Reports',
            route: '/reports/sales/schedules',
          ),
      ],
    );
  }
}

class _BusinessReportsCard extends ConsumerWidget {
  const _BusinessReportsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheduledEnabled =
        ref
            .watch(reportFeatureEntitlementProvider('reports.scheduled'))
            .value !=
        false;
    return _ReportGroupCard(
      icon: Icons.business_center_outlined,
      title: 'Business Reports',
      subtitle:
          'Owner dashboard, profit and loss, inventory analytics, customer credit, cash flow, repairs, exports, and schedules.',
      primaryLabel: 'Open Business Dashboard',
      primaryRoute: '/reports/business',
      links: [
        const _ReportLink(
          icon: Icons.dashboard_outlined,
          label: 'Business Dashboard',
          route: '/reports/business',
        ),
        const _ReportLink(
          icon: Icons.account_balance_outlined,
          label: 'Profit & Loss',
          route: '/reports/business/profit-loss',
        ),
        const _ReportLink(
          icon: Icons.inventory_2_outlined,
          label: 'Inventory',
          route: '/reports/business/inventory',
        ),
        const _ReportLink(
          icon: Icons.credit_score_outlined,
          label: 'Customer Credit',
          route: '/reports/business/customer-credit',
        ),
        const _ReportLink(
          icon: Icons.payments_outlined,
          label: 'Cash Flow',
          route: '/reports/business/cash-flow',
        ),
        const _ReportLink(
          icon: Icons.handyman_outlined,
          label: 'Repairs',
          route: '/reports/business/repairs',
        ),
        if (scheduledEnabled)
          const _ReportLink(
            icon: Icons.schedule_send_outlined,
            label: 'Scheduled Business Reports',
            route: '/reports/business/schedules',
          ),
      ],
    );
  }
}

class _ReportGroupCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String primaryLabel;
  final String primaryRoute;
  final List<_ReportLink> links;

  const _ReportGroupCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.primaryLabel,
    required this.primaryRoute,
    required this.links,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(child: Icon(icon)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(subtitle),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => context.go(primaryRoute),
              icon: const Icon(Icons.open_in_new),
              label: Text(primaryLabel),
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 8),
            for (final link in links) _ReportLinkTile(link: link),
          ],
        ),
      ),
    );
  }
}

class _ReportLink {
  final IconData icon;
  final String label;
  final String route;

  const _ReportLink({
    required this.icon,
    required this.label,
    required this.route,
  });
}

class _ReportLinkTile extends StatelessWidget {
  final _ReportLink link;

  const _ReportLinkTile({required this.link});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: Icon(link.icon),
      title: Text(link.label),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => context.go(link.route),
    );
  }
}
