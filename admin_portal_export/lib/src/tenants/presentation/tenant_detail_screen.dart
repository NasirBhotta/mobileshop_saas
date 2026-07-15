import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../tenant_entitlements/presentation/tenant_entitlement_section.dart';
import '../../billing/presentation/tenant_billing_section.dart';
import '../../addons/presentation/tenant_addons_section.dart';
import '../../support/presentation/tenant_support_section.dart';
import '../domain/platform_tenant.dart';
import 'tenant_admin_providers.dart';

class TenantDetailScreen extends ConsumerWidget {
  final String tenantId;
  const TenantDetailScreen({required this.tenantId, super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tenant = ref.watch(tenantDetailProvider(tenantId));
    return ListView(
      padding: const EdgeInsets.all(32),
      children: [
        Row(
          children: [
            IconButton(
              onPressed: () => context.go('/tenants'),
              icon: const Icon(Icons.arrow_back),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Tenant details',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
            ),
            IconButton(
              onPressed: () => ref.invalidate(tenantDetailProvider(tenantId)),
              icon: const Icon(Icons.refresh),
              tooltip: 'Refresh',
            ),
          ],
        ),
        const SizedBox(height: 24),
        tenant.when(
          loading: () => const LinearProgressIndicator(),
          error: (error, _) => Text('Could not load tenant: $error'),
          data: (value) => _TenantDetails(tenant: value),
        ),
      ],
    );
  }
}

class _TenantDetails extends ConsumerWidget {
  final PlatformTenant tenant;
  const _TenantDetails({required this.tenant});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final changing = ref.watch(tenantStatusControllerProvider).isLoading;
    final isSuspended = tenant.status.toLowerCase() == 'suspended';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Wrap(
              spacing: 48,
              runSpacing: 24,
              children: [
                _Detail('Shop name', tenant.shopName),
                _Detail('Business type', tenant.businessType),
                _Detail('Status', tenant.status),
                _Detail('Current plan', tenant.plan),
                _Detail('Branches', '${tenant.branchCount}'),
                _Detail('Users', '${tenant.userCount}'),
                _Detail('Created', _formatDate(tenant.createdAt)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed:
              changing
                  ? null
                  : () => _confirmStatus(
                    context,
                    ref,
                    isSuspended ? 'active' : 'suspended',
                  ),
          style:
              isSuspended
                  ? null
                  : FilledButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.error,
                  ),
          icon: Icon(
            isSuspended
                ? Icons.play_circle_outline
                : Icons.pause_circle_outline,
          ),
          label: Text(isSuspended ? 'Reactivate tenant' : 'Suspend tenant'),
        ),
        const SizedBox(height: 40),
        TenantBillingSection(tenantId: tenant.id),
        const SizedBox(height: 40),
        TenantAddonsSection(tenantId: tenant.id),
        const SizedBox(height: 40),
        TenantSupportSection(tenantId: tenant.id),
        const SizedBox(height: 40),
        TenantEntitlementSection(tenantId: tenant.id),
      ],
    );
  }

  Future<void> _confirmStatus(
    BuildContext context,
    WidgetRef ref,
    String status,
  ) async {
    final controller = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: Text(
              status == 'active' ? 'Activate tenant?' : 'Suspend tenant?',
            ),
            content: TextField(
              controller: controller,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Reason (optional)'),
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
    if (confirmed != true || !context.mounted) {
      controller.dispose();
      return;
    }
    final success = await ref
        .read(tenantStatusControllerProvider.notifier)
        .change(tenantId: tenant.id, status: status, reason: controller.text);
    controller.dispose();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success ? 'Tenant status updated.' : 'Tenant status update failed.',
        ),
      ),
    );
  }

  String _formatDate(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
}

class _Detail extends StatelessWidget {
  final String label;
  final String value;
  const _Detail(this.label, this.value);
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 210,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 6),
        Text(value, style: Theme.of(context).textTheme.titleMedium),
      ],
    ),
  );
}
