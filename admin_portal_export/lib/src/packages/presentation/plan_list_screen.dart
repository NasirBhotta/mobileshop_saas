import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../domain/platform_plan.dart';
import 'package_admin_providers.dart';
import 'plan_form_dialog.dart';

class PlanListScreen extends ConsumerWidget {
  const PlanListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plans = ref.watch(plansProvider);
    return ListView(
      padding: const EdgeInsets.all(32),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Plans',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
            ),
            IconButton(
              onPressed: () => ref.invalidate(plansProvider),
              icon: const Icon(Icons.refresh),
              tooltip: 'Refresh',
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: () => showPlanFormDialog(context, ref),
              icon: const Icon(Icons.add),
              label: const Text('Create plan'),
            ),
          ],
        ),
        const SizedBox(height: 24),
        plans.when(
          loading: () => const LinearProgressIndicator(),
          error: (error, _) => Text('Could not load plans: $error'),
          data:
              (items) => Wrap(
                spacing: 16,
                runSpacing: 16,
                children: items.map((plan) => _PlanCard(plan)).toList(),
              ),
        ),
      ],
    );
  }
}

class _PlanCard extends StatelessWidget {
  final PlatformPlan plan;
  const _PlanCard(this.plan);
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 330,
    child: Card(
      child: InkWell(
        onTap: () => context.go('/plans/${plan.id}'),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      plan.name,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  Chip(label: Text(plan.isActive ? 'Active' : 'Inactive')),
                ],
              ),
              Text(plan.key, style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 16),
              Text(
                plan.monthlyPrice == null
                    ? 'Price not set'
                    : 'Rs ${plan.monthlyPrice!.toStringAsFixed(0)} / month',
              ),
              const SizedBox(height: 8),
              Text('${plan.affectedTenantCount} affected tenants'),
            ],
          ),
        ),
      ),
    ),
  );
}
