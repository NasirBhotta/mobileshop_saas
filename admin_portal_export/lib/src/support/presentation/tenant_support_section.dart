import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'support_providers.dart';

class TenantSupportSection extends ConsumerWidget {
  final String tenantId;
  const TenantSupportSection({required this.tenantId, super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activity = ref.watch(tenantActivityProvider(tenantId)),
        notes = ref.watch(supportNotesProvider(tenantId));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Activity & account support',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
            FilledButton.icon(
              onPressed: () => _note(context, ref),
              icon: const Icon(Icons.note_add),
              label: const Text('Add support note'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text('Tenant activity', style: Theme.of(context).textTheme.titleLarge),
        activity.when(
          loading: () => const LinearProgressIndicator(),
          error: (e, _) => Text('Could not load activity: $e'),
          data:
              (items) => Card(
                child: Column(
                  children:
                      items.isEmpty
                          ? [const ListTile(title: Text('No activity.'))]
                          : items
                              .take(20)
                              .map(
                                (e) => ListTile(
                                  leading: const Icon(Icons.timeline),
                                  title: Text(e.action),
                                  subtitle: Text(
                                    '${e.entityType} • ${e.createdAt.toLocal()}',
                                  ),
                                ),
                              )
                              .toList(),
                ),
              ),
        ),
        const SizedBox(height: 20),
        Text('Support notes', style: Theme.of(context).textTheme.titleLarge),
        notes.when(
          loading: () => const LinearProgressIndicator(),
          error: (e, _) => Text('Could not load support notes: $e'),
          data:
              (items) => Card(
                child: Column(
                  children:
                      items.isEmpty
                          ? [const ListTile(title: Text('No support notes.'))]
                          : items
                              .map(
                                (n) => ListTile(
                                  title: Text(n.category.replaceAll('_', ' ')),
                                  subtitle: Text(
                                    '${n.note}\nCreated by ${n.createdBy}',
                                  ),
                                  trailing:
                                      n.status == 'open'
                                          ? TextButton(
                                            onPressed:
                                                () => ref
                                                    .read(
                                                      supportMutationProvider
                                                          .notifier,
                                                    )
                                                    .run(
                                                      (r) =>
                                                          r.resolveNote(n.id),
                                                      tenantId: tenantId,
                                                    ),
                                            child: const Text('Resolve'),
                                          )
                                          : const Chip(label: Text('Resolved')),
                                ),
                              )
                              .toList(),
                ),
              ),
        ),
      ],
    );
  }

  Future<void> _note(BuildContext context, WidgetRef ref) async {
    final note = TextEditingController(), user = TextEditingController();
    String category = 'support';
    final ok = await showDialog<bool>(
      context: context,
      builder:
          (c) => StatefulBuilder(
            builder:
                (c, setState) => AlertDialog(
                  title: const Text('Add support note'),
                  content: SizedBox(
                    width: 440,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        DropdownButtonFormField(
                          initialValue: category,
                          items:
                              ['support', 'account_recovery']
                                  .map(
                                    (v) => DropdownMenuItem(
                                      value: v,
                                      child: Text(v.replaceAll('_', ' ')),
                                    ),
                                  )
                                  .toList(),
                          onChanged: (v) => setState(() => category = v!),
                          decoration: const InputDecoration(
                            labelText: 'Category',
                          ),
                        ),
                        TextField(
                          controller: user,
                          decoration: const InputDecoration(
                            labelText: 'Subject user UUID (optional)',
                          ),
                        ),
                        TextField(
                          controller: note,
                          maxLength: 2000,
                          maxLines: 4,
                          decoration: const InputDecoration(labelText: 'Note'),
                        ),
                      ],
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(c, false),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      onPressed:
                          () => Navigator.pop(c, note.text.trim().isNotEmpty),
                      child: const Text('Add'),
                    ),
                  ],
                ),
          ),
    );
    if (ok == true) {
      await ref
          .read(supportMutationProvider.notifier)
          .run(
            (r) => r.addNote(
              tenantId,
              user.text.trim().isEmpty ? null : user.text.trim(),
              category,
              note.text.trim(),
            ),
            tenantId: tenantId,
          );
    }
    note.dispose();
    user.dispose();
  }
}
