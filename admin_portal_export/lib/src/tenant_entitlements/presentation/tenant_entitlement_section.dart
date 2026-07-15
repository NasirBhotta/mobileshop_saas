import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../packages/presentation/package_admin_providers.dart';
import '../data/tenant_entitlement_repository.dart';
import '../domain/tenant_entitlement.dart';
import 'tenant_entitlement_providers.dart';

class TenantEntitlementSection extends ConsumerWidget {
  final String tenantId;
  const TenantEntitlementSection({required this.tenantId, super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subscription = ref.watch(tenantSubscriptionProvider(tenantId));
    final busy = ref.watch(tenantEntitlementMutationProvider).isLoading;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Subscription & overrides',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
            IconButton(
              onPressed: () => _refresh(ref),
              icon: const Icon(Icons.refresh),
              tooltip: 'Refresh entitlements',
            ),
          ],
        ),
        const SizedBox(height: 16),
        subscription.when(
          loading: () => const LinearProgressIndicator(),
          error: (error, _) => Text('Could not load subscription: $error'),
          data:
              (value) => Card(
                child: ListTile(
                  leading: const CircleAvatar(
                    child: Icon(Icons.workspace_premium_outlined),
                  ),
                  title: Text(value?.planName ?? 'No active subscription'),
                  subtitle: Text(
                    value == null
                        ? 'Assign an active plan to this tenant.'
                        : '${value.planKey} • ${value.status}',
                  ),
                  trailing: FilledButton.icon(
                    onPressed:
                        busy
                            ? null
                            : () => _changePlan(context, ref, value?.planId),
                    icon: const Icon(Icons.swap_horiz),
                    label: Text(value == null ? 'Assign plan' : 'Change plan'),
                  ),
                ),
              ),
        ),
        const SizedBox(height: 28),
        Text(
          'Effective features',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 12),
        _FeatureOverrides(tenantId: tenantId),
        const SizedBox(height: 28),
        Row(
          children: [
            Expanded(
              child: Text(
                'Effective limits',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            OutlinedButton.icon(
              onPressed:
                  busy ? null : () => _showLimitDialog(context, ref, null),
              icon: const Icon(Icons.add),
              label: const Text('Add override'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _LimitOverrides(tenantId: tenantId),
      ],
    );
  }

  void _refresh(WidgetRef ref) {
    ref.invalidate(tenantSubscriptionProvider(tenantId));
    ref.invalidate(tenantEffectiveFeaturesProvider(tenantId));
    ref.invalidate(tenantEffectiveLimitsProvider(tenantId));
  }

  Future<void> _changePlan(
    BuildContext context,
    WidgetRef ref,
    String? currentPlanId,
  ) async {
    final plans = await ref.read(plansProvider.future);
    if (!context.mounted) return;
    final activePlans = plans.where((plan) => plan.isActive).toList();
    String? selected = currentPlanId;
    final reason = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (dialogContext) => StatefulBuilder(
            builder:
                (context, setState) => AlertDialog(
                  title: const Text('Change tenant plan'),
                  content: SizedBox(
                    width: 440,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        DropdownButtonFormField<String>(
                          initialValue:
                              activePlans.any((plan) => plan.id == selected)
                                  ? selected
                                  : null,
                          decoration: const InputDecoration(labelText: 'Plan'),
                          items:
                              activePlans
                                  .map(
                                    (plan) => DropdownMenuItem(
                                      value: plan.id,
                                      child: Text(plan.name),
                                    ),
                                  )
                                  .toList(),
                          onChanged:
                              (value) => setState(() => selected = value),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: reason,
                          maxLines: 2,
                          decoration: const InputDecoration(
                            labelText: 'Reason (optional)',
                          ),
                        ),
                      ],
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext, false),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      onPressed:
                          selected == null
                              ? null
                              : () => Navigator.pop(dialogContext, true),
                      child: const Text('Change plan'),
                    ),
                  ],
                ),
          ),
    );
    if (confirmed == true && selected != null) {
      if (!context.mounted) return;
      await _mutate(
        context,
        ref,
        (repository) => repository.changePlan(
          tenantId: tenantId,
          planId: selected!,
          reason: _optional(reason.text),
        ),
      );
    }
    reason.dispose();
  }

  Future<void> _showLimitDialog(
    BuildContext context,
    WidgetRef ref,
    TenantLimitEntitlement? limit,
  ) async {
    final key = TextEditingController(text: limit?.key ?? '');
    final value = TextEditingController(
      text:
          limit?.overrideValue?.toString() ??
          limit?.effectiveValue?.toString() ??
          '',
    );
    final reason = TextEditingController(text: limit?.overrideReason ?? '');
    DateTime? expiry = limit?.overrideExpiresAt?.toLocal();
    final formKey = GlobalKey<FormState>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (dialogContext) => StatefulBuilder(
            builder:
                (context, setState) => AlertDialog(
                  title: Text(
                    limit == null
                        ? 'Add limit override'
                        : 'Edit limit override',
                  ),
                  content: SizedBox(
                    width: 460,
                    child: Form(
                      key: formKey,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TextFormField(
                            controller: key,
                            enabled: limit == null,
                            decoration: const InputDecoration(
                              labelText: 'Limit key',
                            ),
                            validator:
                                (input) =>
                                    input == null ||
                                            !RegExp(
                                              r'^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$',
                                            ).hasMatch(input)
                                        ? 'Use resource.limit format.'
                                        : null,
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: value,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Override value (-1 = unlimited)',
                            ),
                            validator: (input) {
                              final parsed = double.tryParse(input ?? '');
                              return parsed == null || parsed < -1
                                  ? 'Enter -1 or a positive value.'
                                  : null;
                            },
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: reason,
                            decoration: const InputDecoration(
                              labelText: 'Reason (optional)',
                            ),
                          ),
                          const SizedBox(height: 12),
                          _ExpiryPicker(
                            expiry: expiry,
                            onChanged: (date) => setState(() => expiry = date),
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
                      child: const Text('Save override'),
                    ),
                  ],
                ),
          ),
    );
    if (confirmed == true) {
      if (!context.mounted) return;
      await _mutate(
        context,
        ref,
        (repository) => repository.setLimitOverride(
          tenantId: tenantId,
          key: key.text.trim(),
          value: double.parse(value.text),
          reason: _optional(reason.text),
          expiresAt: _endOfDay(expiry),
        ),
      );
    }
    key.dispose();
    value.dispose();
    reason.dispose();
  }

  Future<void> _mutate(
    BuildContext context,
    WidgetRef ref,
    Future<void> Function(TenantEntitlementRepository repository) operation,
  ) async {
    final success = await ref
        .read(tenantEntitlementMutationProvider.notifier)
        .run(tenantId, operation);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success ? 'Entitlements updated.' : 'Entitlement update failed.',
        ),
      ),
    );
  }
}

class _FeatureOverrides extends ConsumerWidget {
  final String tenantId;
  const _FeatureOverrides({required this.tenantId});
  @override
  Widget build(BuildContext context, WidgetRef ref) => ref
      .watch(tenantEffectiveFeaturesProvider(tenantId))
      .when(
        loading: () => const LinearProgressIndicator(),
        error: (error, _) => Text('Could not load effective features: $error'),
        data: (features) {
          final grouped = <String, List<TenantFeatureEntitlement>>{};
          for (final feature in features) {
            grouped.putIfAbsent(feature.module, () => []).add(feature);
          }
          return Column(
            children:
                grouped.entries
                    .map(
                      (entry) => Card(
                        child: ExpansionTile(
                          title: Text(entry.key),
                          children:
                              entry.value
                                  .map(
                                    (feature) => ListTile(
                                      title: Text(feature.name),
                                      subtitle: Text(_featureSubtitle(feature)),
                                      leading: Icon(
                                        feature.effectiveEnabled
                                            ? Icons.check_circle
                                            : Icons.cancel,
                                        color:
                                            feature.effectiveEnabled
                                                ? Colors.green
                                                : Colors.grey,
                                      ),
                                      trailing: Wrap(
                                        spacing: 4,
                                        children: [
                                          IconButton(
                                            tooltip: 'Set override',
                                            icon: const Icon(Icons.tune),
                                            onPressed:
                                                () => _editFeature(
                                                  context,
                                                  ref,
                                                  feature,
                                                ),
                                          ),
                                          if (feature.hasOverride)
                                            IconButton(
                                              tooltip: 'Remove override',
                                              icon: const Icon(Icons.restore),
                                              onPressed:
                                                  () => _removeFeature(
                                                    context,
                                                    ref,
                                                    feature,
                                                  ),
                                            ),
                                        ],
                                      ),
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

  String _featureSubtitle(TenantFeatureEntitlement feature) {
    if (!feature.hasOverride) return '${feature.key} • Plan default';
    final state =
        feature.overrideIsEffective
            ? 'Override effective'
            : 'Override expired/inactive';
    return '${feature.key} • $state${feature.overrideExpiresAt == null ? '' : ' • expires ${_dateLabel(feature.overrideExpiresAt!)}'}';
  }

  Future<void> _editFeature(
    BuildContext context,
    WidgetRef ref,
    TenantFeatureEntitlement feature,
  ) async {
    bool enabled = feature.overrideEnabled ?? feature.effectiveEnabled;
    DateTime? expiry = feature.overrideExpiresAt?.toLocal();
    final reason = TextEditingController(text: feature.overrideReason ?? '');
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (dialogContext) => StatefulBuilder(
            builder:
                (context, setState) => AlertDialog(
                  title: Text('Override ${feature.name}'),
                  content: SizedBox(
                    width: 440,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Feature enabled'),
                          value: enabled,
                          onChanged: (value) => setState(() => enabled = value),
                        ),
                        TextField(
                          controller: reason,
                          decoration: const InputDecoration(
                            labelText: 'Reason (optional)',
                          ),
                        ),
                        const SizedBox(height: 12),
                        _ExpiryPicker(
                          expiry: expiry,
                          onChanged: (date) => setState(() => expiry = date),
                        ),
                      ],
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext, false),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(dialogContext, true),
                      child: const Text('Save override'),
                    ),
                  ],
                ),
          ),
    );
    if (confirmed == true) {
      if (!context.mounted) return;
      await _run(
        context,
        ref,
        (repository) => repository.setFeatureOverride(
          tenantId: tenantId,
          featureId: feature.featureId,
          enabled: enabled,
          reason: _optional(reason.text),
          expiresAt: _endOfDay(expiry),
        ),
      );
    }
    reason.dispose();
  }

  Future<void> _removeFeature(
    BuildContext context,
    WidgetRef ref,
    TenantFeatureEntitlement feature,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: const Text('Remove feature override?'),
            content: const Text(
              'The plan default will become effective again.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Remove'),
              ),
            ],
          ),
    );
    if (confirmed == true) {
      if (!context.mounted) return;
      await _run(
        context,
        ref,
        (repository) => repository.removeFeatureOverride(
          tenantId: tenantId,
          featureId: feature.featureId,
          reason: 'Removed from platform admin portal',
        ),
      );
    }
  }

  Future<void> _run(
    BuildContext context,
    WidgetRef ref,
    Future<void> Function(TenantEntitlementRepository repository) operation,
  ) async {
    final success = await ref
        .read(tenantEntitlementMutationProvider.notifier)
        .run(tenantId, operation);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            success ? 'Feature override updated.' : 'Feature override failed.',
          ),
        ),
      );
    }
  }
}

class _LimitOverrides extends ConsumerWidget {
  final String tenantId;
  const _LimitOverrides({required this.tenantId});
  @override
  Widget build(BuildContext context, WidgetRef ref) => ref
      .watch(tenantEffectiveLimitsProvider(tenantId))
      .when(
        loading: () => const LinearProgressIndicator(),
        error: (error, _) => Text('Could not load effective limits: $error'),
        data:
            (limits) => Card(
              child: Column(
                children:
                    limits.isEmpty
                        ? [
                          const ListTile(
                            title: Text('No plan limits or overrides.'),
                          ),
                        ]
                        : limits
                            .map(
                              (limit) => ListTile(
                                title: Text(limit.key),
                                subtitle: Text(_limitSubtitle(limit)),
                                leading: CircleAvatar(
                                  child: Text(_value(limit.effectiveValue)),
                                ),
                                trailing: Wrap(
                                  spacing: 4,
                                  children: [
                                    IconButton(
                                      tooltip: 'Edit override',
                                      icon: const Icon(Icons.edit),
                                      onPressed:
                                          () => TenantEntitlementSection(
                                            tenantId: tenantId,
                                          )._showLimitDialog(
                                            context,
                                            ref,
                                            limit,
                                          ),
                                    ),
                                    if (limit.hasOverride)
                                      IconButton(
                                        tooltip: 'Remove override',
                                        icon: const Icon(Icons.restore),
                                        onPressed:
                                            () => _remove(context, ref, limit),
                                      ),
                                  ],
                                ),
                              ),
                            )
                            .toList(),
              ),
            ),
      );

  String _limitSubtitle(TenantLimitEntitlement limit) =>
      limit.hasOverride
          ? 'Plan: ${_value(limit.planValue)} • Override ${limit.overrideIsEffective ? 'effective' : 'expired/inactive'}${limit.overrideExpiresAt == null ? '' : ' • expires ${_dateLabel(limit.overrideExpiresAt!)}'}'
          : 'Plan default: ${_value(limit.planValue)}';

  Future<void> _remove(
    BuildContext context,
    WidgetRef ref,
    TenantLimitEntitlement limit,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: const Text('Remove limit override?'),
            content: const Text('The plan limit will become effective again.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Remove'),
              ),
            ],
          ),
    );
    if (confirmed == true) {
      final success = await ref
          .read(tenantEntitlementMutationProvider.notifier)
          .run(
            tenantId,
            (repository) => repository.removeLimitOverride(
              tenantId: tenantId,
              key: limit.key,
              reason: 'Removed from platform admin portal',
            ),
          );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              success
                  ? 'Limit override removed.'
                  : 'Limit override removal failed.',
            ),
          ),
        );
      }
    }
  }
}

class _ExpiryPicker extends StatelessWidget {
  final DateTime? expiry;
  final ValueChanged<DateTime?> onChanged;
  const _ExpiryPicker({required this.expiry, required this.onChanged});
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(
          expiry == null ? 'No expiry' : 'Expires ${_dateLabel(expiry!)}',
        ),
      ),
      if (expiry != null)
        IconButton(
          onPressed: () => onChanged(null),
          icon: const Icon(Icons.clear),
          tooltip: 'Clear expiry',
        ),
      OutlinedButton.icon(
        onPressed: () async {
          final date = await showDatePicker(
            context: context,
            initialDate: expiry ?? DateTime.now().add(const Duration(days: 30)),
            firstDate: DateTime.now(),
            lastDate: DateTime.now().add(const Duration(days: 3650)),
          );
          if (date != null) onChanged(date);
        },
        icon: const Icon(Icons.event),
        label: const Text('Choose expiry'),
      ),
    ],
  );
}

String? _optional(String value) => value.trim().isEmpty ? null : value.trim();
DateTime? _endOfDay(DateTime? date) =>
    date == null ? null : DateTime(date.year, date.month, date.day, 23, 59, 59);
String _dateLabel(DateTime date) =>
    '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
String _value(double? value) =>
    value == null
        ? '—'
        : value == -1
        ? '∞'
        : value.toStringAsFixed(value % 1 == 0 ? 0 : 2);
