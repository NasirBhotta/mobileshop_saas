import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/support_models.dart';
import 'support_providers.dart';

class AuditSupportScreen extends ConsumerStatefulWidget {
  const AuditSupportScreen({super.key});
  @override
  ConsumerState<AuditSupportScreen> createState() => _AuditSupportScreenState();
}

class _AuditSupportScreenState extends ConsumerState<AuditSupportScreen> {
  final tenant = TextEditingController(),
      action = TextEditingController(),
      admin = TextEditingController();
  @override
  void dispose() {
    tenant.dispose();
    action.dispose();
    admin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(32, 24, 32, 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Audit & support',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                ),
                IconButton(
                  onPressed: () => _refresh(),
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
          ),
          const TabBar(
            tabs: [
              Tab(text: 'Audit log'),
              Tab(text: 'Failed reports'),
              Tab(text: 'Offline failures'),
            ],
          ),
          Expanded(
            child: TabBarView(children: [_audits(), _jobs(), _failures()]),
          ),
        ],
      ),
    );
  }

  Widget _audits() {
    final data = ref.watch(auditLogsProvider);
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            SizedBox(
              width: 260,
              child: TextField(
                controller: tenant,
                decoration: const InputDecoration(labelText: 'Tenant UUID'),
              ),
            ),
            SizedBox(
              width: 220,
              child: TextField(
                controller: action,
                decoration: const InputDecoration(labelText: 'Action contains'),
              ),
            ),
            SizedBox(
              width: 260,
              child: TextField(
                controller: admin,
                decoration: const InputDecoration(labelText: 'Admin UUID'),
              ),
            ),
            OutlinedButton.icon(
              onPressed: _dates,
              icon: const Icon(Icons.date_range),
              label: const Text('Date range'),
            ),
            FilledButton(onPressed: _apply, child: const Text('Apply filters')),
          ],
        ),
        const SizedBox(height: 16),
        data.when(
          loading: () => const LinearProgressIndicator(),
          error: (e, _) => Text('Could not load audit log: $e'),
          data:
              (items) => Card(
                child: Column(
                  children:
                      items.isEmpty
                          ? [const ListTile(title: Text('No audit entries.'))]
                          : items
                              .map(
                                (e) => ListTile(
                                  leading: const Icon(Icons.history),
                                  title: Text(e.action),
                                  subtitle: Text(
                                    '${e.tenantName ?? e.tenantId ?? 'Platform'} • ${e.entityType} • ${_date(e.createdAt)}',
                                  ),
                                  trailing: Tooltip(
                                    message:
                                        'Admin: ${e.adminId ?? 'system'}\nEntity: ${e.entityId ?? 'none'}',
                                    child: const Icon(Icons.info_outline),
                                  ),
                                ),
                              )
                              .toList(),
                ),
              ),
        ),
      ],
    );
  }

  Widget _jobs() => _async(
    ref.watch(failedJobsProvider),
    (FailedJob j) => ListTile(
      title: Text('${j.type} report • ${j.errorCode ?? 'FAILED'}'),
      subtitle: Text(
        'Job ${j.id}\nTenant ${j.tenantId} • ${_date(j.createdAt)}',
      ),
      trailing: FilledButton(
        onPressed:
            () => ref
                .read(supportMutationProvider.notifier)
                .run((r) => r.retryJob(j)),
        child: const Text('Retry'),
      ),
    ),
  );
  Widget _failures() => _async(
    ref.watch(offlineFailuresProvider),
    (OfflineFailure f) => ListTile(
      title: Text('${f.type} • ${f.code ?? 'UNCLASSIFIED'}'),
      subtitle: Text(
        'Failure ${f.id}\nTenant ${f.tenantId} • attempts ${f.attempts}',
      ),
      trailing: Wrap(
        children: [
          TextButton(
            onPressed: () => _failure(f, 'retry'),
            child: const Text('Retry'),
          ),
          TextButton(
            onPressed: () => _failure(f, 'resolve'),
            child: const Text('Resolve'),
          ),
        ],
      ),
    ),
  );
  Widget _async<T>(AsyncValue<List<T>> value, Widget Function(T) row) =>
      ListView(
        padding: const EdgeInsets.all(24),
        children: [
          value.when(
            loading: () => const LinearProgressIndicator(),
            error: (e, _) => Text('Could not load diagnostics: $e'),
            data:
                (items) => Card(
                  child: Column(
                    children:
                        items.isEmpty
                            ? [const ListTile(title: Text('No failures.'))]
                            : items.map(row).toList(),
                  ),
                ),
          ),
        ],
      );
  DateTime? from, to;
  Future<void> _dates() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (range != null) {
      setState(() {
        from = range.start;
        to = range.end.add(const Duration(days: 1));
      });
    }
  }

  void _apply() {
    ref
        .read(auditFiltersProvider.notifier)
        .update(
          AuditFilters(
            tenantId: _optional(tenant.text),
            action: _optional(action.text),
            adminId: _optional(admin.text),
            from: from,
            to: to,
          ),
        );
  }

  void _refresh() {
    ref.invalidate(auditLogsProvider);
    ref.invalidate(failedJobsProvider);
    ref.invalidate(offlineFailuresProvider);
  }

  Future<void> _failure(OfflineFailure f, String a) => ref
      .read(supportMutationProvider.notifier)
      .run((r) => r.updateFailure(f.id, a));
}

String? _optional(String v) => v.trim().isEmpty ? null : v.trim();
String _date(DateTime d) => d.toLocal().toString().substring(0, 16);
