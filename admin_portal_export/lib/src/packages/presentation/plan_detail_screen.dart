import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../domain/platform_plan.dart';
import 'package_admin_providers.dart';
import 'plan_form_dialog.dart';

class PlanDetailScreen extends ConsumerWidget {
  final String planId;
  const PlanDetailScreen({required this.planId, super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plan = ref.watch(planProvider(planId));
    return ListView(
      padding: const EdgeInsets.all(32),
      children: [
        Row(
          children: [
            IconButton(
              onPressed: () => context.go('/plans'),
              icon: const Icon(Icons.arrow_back),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Plan details',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
            ),
            IconButton(
              onPressed: () => _refresh(ref),
              icon: const Icon(Icons.refresh),
              tooltip: 'Refresh',
            ),
          ],
        ),
        const SizedBox(height: 24),
        plan.when(
          loading: () => const LinearProgressIndicator(),
          error: (error, _) => Text('Could not load plan: $error'),
          data: (value) => _PlanContent(plan: value),
        ),
      ],
    );
  }

  void _refresh(WidgetRef ref) {
    ref.invalidate(planProvider(planId));
    ref.invalidate(planFeaturesProvider(planId));
    ref.invalidate(planLimitsProvider(planId));
  }
}

class _PlanContent extends ConsumerWidget {
  final PlatformPlan plan;
  const _PlanContent({required this.plan});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final busy = ref.watch(packageMutationProvider).isLoading;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        plan.name,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                    ),
                    Chip(label: Text(plan.isActive ? 'Active' : 'Inactive')),
                  ],
                ),
                Text(plan.key),
                const SizedBox(height: 12),
                Text(plan.description ?? 'No description'),
                const SizedBox(height: 12),
                Text(
                  plan.monthlyPrice == null
                      ? 'Monthly price not set'
                      : 'Rs ${plan.monthlyPrice!.toStringAsFixed(0)} per month',
                ),
                const SizedBox(height: 8),
                Text(
                  '${plan.affectedTenantCount} tenants currently use this plan',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 20),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    OutlinedButton.icon(
                      onPressed:
                          busy
                              ? null
                              : () =>
                                  showPlanFormDialog(context, ref, plan: plan),
                      icon: const Icon(Icons.edit),
                      label: const Text('Edit plan'),
                    ),
                    FilledButton.icon(
                      onPressed:
                          busy ? null : () => _changeActive(context, ref),
                      icon: Icon(
                        plan.isActive
                            ? Icons.pause_circle_outline
                            : Icons.play_circle_outline,
                      ),
                      label: Text(
                        plan.isActive ? 'Deactivate plan' : 'Activate plan',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 28),
        Text('Features', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        _FeaturesSection(plan: plan),
        const SizedBox(height: 28),
        Row(
          children: [
            Expanded(
              child: Text(
                'Limits',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            OutlinedButton.icon(
              onPressed:
                  plan.isActive && !busy
                      ? () => _editLimit(context, ref)
                      : null,
              icon: const Icon(Icons.add),
              label: const Text('Add limit'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _LimitsSection(plan: plan),
      ],
    );
  }

  Future<void> _changeActive(BuildContext context, WidgetRef ref) async {
    final activating = !plan.isActive;
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: Text(activating ? 'Activate plan?' : 'Deactivate plan?'),
            content: Text(
              activating
                  ? 'This plan will become available for platform operations.'
                  : '${plan.affectedTenantCount} tenants are affected. Package Patch 6 will reject deactivation while active subscriptions exist.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Confirm'),
              ),
            ],
          ),
    );
    if (confirmed != true) return;
    await ref
        .read(packageMutationProvider.notifier)
        .run<void>(
          (repository) => repository.setPlanActive(plan.id, activating),
          planId: plan.id,
        );
    final failed = ref.read(packageMutationProvider).hasError;
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(failed ? 'Plan update failed.' : 'Plan updated.'),
        ),
      );
    }
  }

  Future<void> _editLimit(
    BuildContext context,
    WidgetRef ref, [
    PlanLimit? limit,
  ]) async {
    final key = TextEditingController(text: limit?.key ?? '');
    final value = TextEditingController(text: limit?.value.toString() ?? '');
    final formKey = GlobalKey<FormState>();
    final save = await showDialog<bool>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: Text(limit == null ? 'Add plan limit' : 'Edit plan limit'),
            content: SizedBox(
              width: 420,
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: key,
                      enabled: limit == null,
                      decoration: const InputDecoration(labelText: 'Limit key'),
                      validator:
                          (v) =>
                              v == null ||
                                      !RegExp(
                                        r'^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$',
                                      ).hasMatch(v)
                                  ? 'Use resource.limit format.'
                                  : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: value,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Value (-1 means unlimited)',
                      ),
                      validator: (v) {
                        final parsed = double.tryParse(v ?? '');
                        return parsed == null || parsed < -1
                            ? 'Enter a value of -1 or greater.'
                            : null;
                      },
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Saving affects ${plan.affectedTenantCount} subscribed tenants.',
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  if (formKey.currentState!.validate()) {
                    Navigator.pop(dialogContext, true);
                  }
                },
                child: const Text('Save'),
              ),
            ],
          ),
    );
    if (save == true) {
      await ref
          .read(packageMutationProvider.notifier)
          .run<void>(
            (repository) => repository.setLimit(
              plan.id,
              key.text.trim(),
              double.parse(value.text),
            ),
            planId: plan.id,
          );
    }
    key.dispose();
    value.dispose();
  }
}

class _FeaturesSection extends ConsumerWidget {
  final PlatformPlan plan;
  const _FeaturesSection({required this.plan});
  @override
  Widget build(BuildContext context, WidgetRef ref) => ref
      .watch(planFeaturesProvider(plan.id))
      .when(
        loading: () => const LinearProgressIndicator(),
        error: (error, _) => Text('Could not load features: $error'),
        data: (features) {
          final modules = <String, List<PlanFeature>>{};
          for (final feature in features) {
            modules.putIfAbsent(feature.module, () => []).add(feature);
          }
          return Column(
            children:
                modules.entries
                    .map(
                      (entry) => Card(
                        child: ExpansionTile(
                          title: Text(entry.key),
                          subtitle: Text(
                            '${entry.value.where((f) => f.enabled).length} enabled',
                          ),
                          children:
                              entry.value
                                  .map(
                                    (feature) => SwitchListTile(
                                      title: Text(feature.name),
                                      subtitle: Text(feature.key),
                                      value: feature.enabled,
                                      onChanged:
                                          !plan.isActive
                                              ? null
                                              : (enabled) async {
                                                final confirmed = await showDialog<
                                                  bool
                                                >(
                                                  context: context,
                                                  builder:
                                                      (
                                                        dialogContext,
                                                      ) => AlertDialog(
                                                        title: Text(
                                                          '${enabled ? 'Enable' : 'Disable'} feature?',
                                                        ),
                                                        content: Text(
                                                          'This change affects ${plan.affectedTenantCount} subscribed tenants.',
                                                        ),
                                                        actions: [
                                                          TextButton(
                                                            onPressed:
                                                                () => Navigator.pop(
                                                                  dialogContext,
                                                                  false,
                                                                ),
                                                            child: const Text(
                                                              'Cancel',
                                                            ),
                                                          ),
                                                          FilledButton(
                                                            onPressed:
                                                                () => Navigator.pop(
                                                                  dialogContext,
                                                                  true,
                                                                ),
                                                            child: const Text(
                                                              'Confirm',
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                );
                                                if (confirmed == true) {
                                                  await ref
                                                      .read(
                                                        packageMutationProvider
                                                            .notifier,
                                                      )
                                                      .run<void>(
                                                        (repository) =>
                                                            repository
                                                                .setFeature(
                                                                  plan.id,
                                                                  feature.id,
                                                                  enabled,
                                                                ),
                                                        planId: plan.id,
                                                      );
                                                }
                                              },
                                    ),
                                  )
                                  .toList(),
                        ),
                      ),
                    )
                    .toList(),
          );
        },
      );
}

class _LimitsSection extends ConsumerWidget {
  final PlatformPlan plan;
  const _LimitsSection({required this.plan});
  @override
  Widget build(BuildContext context, WidgetRef ref) => ref
      .watch(planLimitsProvider(plan.id))
      .when(
        loading: () => const LinearProgressIndicator(),
        error: (error, _) => Text('Could not load limits: $error'),
        data:
            (limits) => Card(
              child: Column(
                children:
                    limits.isEmpty
                        ? [const ListTile(title: Text('No limits configured.'))]
                        : limits
                            .map(
                              (limit) => ListTile(
                                title: Text(limit.key),
                                subtitle: Text(
                                  limit.value == -1
                                      ? 'Unlimited'
                                      : limit.value.toString(),
                                ),
                                trailing: IconButton(
                                  icon: const Icon(Icons.edit),
                                  onPressed:
                                      plan.isActive
                                          ? () => _openEdit(context, ref, limit)
                                          : null,
                                ),
                              ),
                            )
                            .toList(),
              ),
            ),
      );

  Future<void> _openEdit(
    BuildContext context,
    WidgetRef ref,
    PlanLimit limit,
  ) async {
    final host = _PlanContent(plan: plan);
    await host._editLimit(context, ref, limit);
  }
}
