import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/platform_addon.dart';
import 'addon_providers.dart';

class AddonListScreen extends ConsumerWidget {
  const AddonListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(addonsProvider);
    return ListView(
      padding: const EdgeInsets.all(32),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Add-ons',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
            ),
            FilledButton.icon(
              onPressed: () => _edit(context, ref, null),
              icon: const Icon(Icons.add),
              label: const Text('Create add-on'),
            ),
          ],
        ),
        const SizedBox(height: 24),
        data.when(
          loading: () => const LinearProgressIndicator(),
          error: (error, _) => Text('Could not load add-ons: $error'),
          data:
              (items) => Card(
                child: Column(
                  children:
                      items.isEmpty
                          ? [
                            const ListTile(
                              title: Text('No add-ons configured.'),
                            ),
                          ]
                          : items
                              .map((addon) => _tile(context, ref, addon))
                              .toList(),
                ),
              ),
        ),
      ],
    );
  }

  Widget _tile(BuildContext context, WidgetRef ref, PlatformAddon addon) {
    return ListTile(
      title: Text(addon.name),
      subtitle: Text(
        '${addon.key} • ${addon.billingType} • '
        '${addon.featureKey ?? addon.limitKey ?? 'No entitlement'}',
      ),
      leading: Chip(label: Text(addon.isActive ? 'Active' : 'Inactive')),
      trailing: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text('PKR ${addon.price.toStringAsFixed(2)}  '),
          IconButton(
            onPressed: () => _edit(context, ref, addon),
            icon: const Icon(Icons.edit),
          ),
          if (addon.isActive)
            IconButton(
              tooltip: 'Deactivate',
              onPressed:
                  () => ref
                      .read(addonMutationProvider.notifier)
                      .run((repository) => repository.deactivate(addon.id)),
              icon: const Icon(Icons.block),
            ),
        ],
      ),
    );
  }

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref,
    PlatformAddon? addon,
  ) async {
    final key = TextEditingController(text: addon?.key);
    final name = TextEditingController(text: addon?.name);
    final description = TextEditingController(text: addon?.description);
    final price = TextEditingController(text: addon?.price.toString() ?? '0');
    final feature = TextEditingController(text: addon?.featureId);
    final limit = TextEditingController(text: addon?.limitKey);
    final increase = TextEditingController(
      text: addon?.limitIncrease?.toString(),
    );
    var billing = addon?.billingType ?? 'monthly';
    final form = GlobalKey<FormState>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (dialogContext) => StatefulBuilder(
            builder:
                (context, setState) => AlertDialog(
                  title: Text(addon == null ? 'Create add-on' : 'Edit add-on'),
                  content: SizedBox(
                    width: 480,
                    child: Form(
                      key: form,
                      child: SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            TextFormField(
                              controller: key,
                              decoration: const InputDecoration(
                                labelText: 'Key',
                              ),
                              validator:
                                  (value) =>
                                      RegExp(
                                            r'^[a-z][a-z0-9_]*$',
                                          ).hasMatch(value ?? '')
                                          ? null
                                          : 'Use lowercase_key',
                            ),
                            TextFormField(
                              controller: name,
                              decoration: const InputDecoration(
                                labelText: 'Name',
                              ),
                              validator:
                                  (value) =>
                                      (value ?? '').trim().isEmpty
                                          ? 'Required'
                                          : null,
                            ),
                            TextFormField(
                              controller: description,
                              decoration: const InputDecoration(
                                labelText: 'Description',
                              ),
                            ),
                            TextFormField(
                              controller: price,
                              decoration: const InputDecoration(
                                labelText: 'Price',
                              ),
                              validator:
                                  (value) =>
                                      (double.tryParse(value ?? '') ?? -1) >= 0
                                          ? null
                                          : 'Enter zero or more',
                            ),
                            DropdownButtonFormField<String>(
                              initialValue: billing,
                              decoration: const InputDecoration(
                                labelText: 'Billing type',
                              ),
                              items:
                                  ['one_time', 'monthly', 'annual', 'per_unit']
                                      .map(
                                        (value) => DropdownMenuItem(
                                          value: value,
                                          child: Text(value),
                                        ),
                                      )
                                      .toList(),
                              onChanged:
                                  (value) => setState(() => billing = value!),
                            ),
                            TextFormField(
                              controller: feature,
                              decoration: const InputDecoration(
                                labelText: 'Included feature UUID (optional)',
                              ),
                            ),
                            TextFormField(
                              controller: limit,
                              decoration: const InputDecoration(
                                labelText: 'Limit key (optional)',
                              ),
                            ),
                            TextFormField(
                              controller: increase,
                              decoration: const InputDecoration(
                                labelText: 'Limit increase (optional)',
                              ),
                            ),
                          ],
                        ),
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
                        if (form.currentState!.validate()) {
                          Navigator.pop(dialogContext, true);
                        }
                      },
                      child: const Text('Save'),
                    ),
                  ],
                ),
          ),
    );
    if (confirmed == true) {
      await ref
          .read(addonMutationProvider.notifier)
          .run(
            (repository) => repository.save(
              id: addon?.id,
              key: key.text.trim(),
              name: name.text.trim(),
              description: _optional(description.text),
              price: double.parse(price.text),
              billingType: billing,
              featureId: _optional(feature.text),
              limitKey: _optional(limit.text),
              limitIncrease: double.tryParse(increase.text),
              active: addon?.isActive ?? true,
            ),
          );
    }
    for (final controller in [
      key,
      name,
      description,
      price,
      feature,
      limit,
      increase,
    ]) {
      controller.dispose();
    }
  }
}

String? _optional(String value) => value.trim().isEmpty ? null : value.trim();
