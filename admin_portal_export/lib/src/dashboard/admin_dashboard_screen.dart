import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../platform/domain/platform_analytics.dart';
import '../platform/presentation/platform_providers.dart';

class AdminDashboardScreen extends ConsumerWidget {
  const AdminDashboardScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(platformAnalyticsProvider);
    return ListView(
      padding: const EdgeInsets.all(32),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Platform analytics',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
            ),
            IconButton(
              onPressed: () => ref.invalidate(platformAnalyticsProvider),
              icon: const Icon(Icons.refresh),
            ),
            FilledButton.icon(
              onPressed: () => context.go('/settings'),
              icon: const Icon(Icons.settings),
              label: const Text('Global settings'),
            ),
          ],
        ),
        const SizedBox(height: 24),
        data.when(
          loading: () => const LinearProgressIndicator(),
          error:
              (e, _) => Card(
                child: ListTile(title: Text('Could not load analytics: $e')),
              ),
          data: (a) => _Analytics(analytics: a),
        ),
      ],
    );
  }
}

class _Analytics extends StatelessWidget {
  final PlatformAnalytics analytics;
  const _Analytics({required this.analytics});
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          _Card('Total tenants', '${analytics.total}', Icons.store),
          _Card('Active', '${analytics.active}', Icons.check_circle),
          _Card('Suspended', '${analytics.suspended}', Icons.pause_circle),
          _Card(
            'Monthly revenue',
            '${analytics.currency} ${analytics.revenue.toStringAsFixed(2)}',
            Icons.payments,
          ),
          _Card(
            'Unpaid invoices',
            '${analytics.unpaidInvoices} • ${analytics.currency} ${analytics.unpaidAmount.toStringAsFixed(2)}',
            Icons.receipt_long,
          ),
          _Card('Active trials', '${analytics.trials}', Icons.hourglass_top),
          _Card(
            'Renewals in 30 days',
            '${analytics.renewals}',
            Icons.autorenew,
          ),
        ],
      ),
      const SizedBox(height: 28),
      Wrap(
        spacing: 16,
        runSpacing: 16,
        children: [
          _Breakdown('Tenant growth', analytics.growth),
          _Breakdown('Plan distribution', analytics.plans),
          _Breakdown('Feature usage', analytics.features),
          _Breakdown('Add-on usage', analytics.addons),
        ],
      ),
    ],
  );
}

class _Card extends StatelessWidget {
  final String title, value;
  final IconData icon;
  const _Card(this.title, this.value, this.icon);
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 230,
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            CircleAvatar(child: Icon(icon)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(value, style: Theme.of(context).textTheme.titleLarge),
                  Text(title),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _Breakdown extends StatelessWidget {
  final String title;
  final List<MetricPoint> points;
  const _Breakdown(this.title, this.points);
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 360,
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 10),
            if (points.isEmpty)
              const Text('No data')
            else
              ...points
                  .take(12)
                  .map(
                    (p) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Expanded(child: Text(p.name)),
                          Text('${p.count}'),
                        ],
                      ),
                    ),
                  ),
          ],
        ),
      ),
    ),
  );
}
