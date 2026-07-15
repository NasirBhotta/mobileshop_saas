import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'tenant_admin_providers.dart';

class TenantListScreen extends ConsumerStatefulWidget {
  const TenantListScreen({super.key});
  @override
  ConsumerState<TenantListScreen> createState() => _TenantListScreenState();
}

class _TenantListScreenState extends ConsumerState<TenantListScreen> {
  Timer? _debounce;
  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filters = ref.watch(tenantFiltersProvider);
    final tenants = ref.watch(tenantListProvider);
    return ListView(
      padding: const EdgeInsets.all(32),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Tenants',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
            ),
            IconButton(
              onPressed: () => ref.invalidate(tenantListProvider),
              icon: const Icon(Icons.refresh),
              tooltip: 'Refresh',
            ),
          ],
        ),
        const SizedBox(height: 20),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            SizedBox(
              width: 320,
              child: TextField(
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Search shop name',
                ),
                onChanged: (value) {
                  _debounce?.cancel();
                  _debounce = Timer(const Duration(milliseconds: 350), () {
                    ref
                        .read(tenantFiltersProvider.notifier)
                        .update(filters.copyWith(search: value));
                  });
                },
              ),
            ),
            _FilterDropdown(
              label: 'Status',
              value: filters.status,
              values: const ['active', 'suspended'],
              onChanged: (value) {
                ref
                    .read(tenantFiltersProvider.notifier)
                    .update(
                      filters.copyWith(
                        status: value,
                        clearStatus: value == null,
                      ),
                    );
              },
            ),
            _FilterDropdown(
              label: 'Plan',
              value: filters.plan,
              values: const ['starter', 'business', 'enterprise'],
              onChanged: (value) {
                ref
                    .read(tenantFiltersProvider.notifier)
                    .update(
                      filters.copyWith(plan: value, clearPlan: value == null),
                    );
              },
            ),
          ],
        ),
        const SizedBox(height: 20),
        tenants.when(
          loading: () => const LinearProgressIndicator(),
          error: (error, _) => Text('Could not load tenants: $error'),
          data:
              (items) => Card(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columns: const [
                      DataColumn(label: Text('Shop')),
                      DataColumn(label: Text('Plan')),
                      DataColumn(label: Text('Status')),
                      DataColumn(label: Text('Branches')),
                      DataColumn(label: Text('Users')),
                      DataColumn(label: Text('')),
                    ],
                    rows:
                        items
                            .map(
                              (tenant) => DataRow(
                                cells: [
                                  DataCell(Text(tenant.shopName)),
                                  DataCell(Text(tenant.plan)),
                                  DataCell(_StatusChip(tenant.status)),
                                  DataCell(Text('${tenant.branchCount}')),
                                  DataCell(Text('${tenant.userCount}')),
                                  DataCell(
                                    IconButton(
                                      icon: const Icon(Icons.chevron_right),
                                      onPressed:
                                          () => context.go(
                                            '/tenants/${tenant.id}',
                                          ),
                                    ),
                                  ),
                                ],
                              ),
                            )
                            .toList(),
                  ),
                ),
              ),
        ),
      ],
    );
  }
}

class _FilterDropdown extends StatelessWidget {
  final String label;
  final String? value;
  final List<String> values;
  final ValueChanged<String?> onChanged;
  const _FilterDropdown({
    required this.label,
    required this.value,
    required this.values,
    required this.onChanged,
  });
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 180,
    child: DropdownButtonFormField<String>(
      initialValue: value,
      decoration: InputDecoration(labelText: label),
      items: [
        const DropdownMenuItem(value: null, child: Text('All')),
        ...values.map(
          (item) => DropdownMenuItem(value: item, child: Text(item)),
        ),
      ],
      onChanged: onChanged,
    ),
  );
}

class _StatusChip extends StatelessWidget {
  final String status;
  const _StatusChip(this.status);
  @override
  Widget build(BuildContext context) => Chip(
    label: Text(status),
    avatar: Icon(
      status == 'active' ? Icons.check_circle : Icons.pause_circle,
      size: 18,
    ),
  );
}
