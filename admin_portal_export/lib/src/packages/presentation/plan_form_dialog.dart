import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/platform_plan.dart';
import 'package_admin_providers.dart';

Future<String?> showPlanFormDialog(
  BuildContext context,
  WidgetRef ref, {
  PlatformPlan? plan,
}) async {
  final key = TextEditingController(text: plan?.key ?? '');
  final name = TextEditingController(text: plan?.name ?? '');
  final description = TextEditingController(text: plan?.description ?? '');
  final price = TextEditingController(
    text: plan?.monthlyPrice?.toString() ?? '',
  );
  final formKey = GlobalKey<FormState>();
  final result = await showDialog<String>(
    context: context,
    builder:
        (dialogContext) => AlertDialog(
          title: Text(plan == null ? 'Create plan' : 'Edit plan'),
          content: SizedBox(
            width: 480,
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: key,
                    enabled: plan == null,
                    decoration: const InputDecoration(labelText: 'Stable key'),
                    validator:
                        (v) =>
                            v == null ||
                                    !RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(v)
                                ? 'Use lowercase letters, numbers and underscores.'
                                : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: name,
                    decoration: const InputDecoration(labelText: 'Name'),
                    validator:
                        (v) =>
                            v == null || v.trim().isEmpty
                                ? 'Name is required.'
                                : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: description,
                    maxLines: 2,
                    decoration: const InputDecoration(labelText: 'Description'),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: price,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Monthly price',
                      prefixText: 'Rs ',
                    ),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return null;
                      final value = double.tryParse(v);
                      return value == null || value < 0
                          ? 'Enter a valid non-negative price.'
                          : null;
                    },
                  ),
                  if (plan != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      'Saving changes affects ${plan.affectedTenantCount} subscribed tenants.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;
                final savedId = await ref
                    .read(packageMutationProvider.notifier)
                    .run<String>(
                      (repository) => repository.savePlan(
                        id: plan?.id,
                        key: key.text.trim(),
                        name: name.text.trim(),
                        description:
                            description.text.trim().isEmpty
                                ? null
                                : description.text.trim(),
                        monthlyPrice:
                            price.text.trim().isEmpty
                                ? null
                                : double.parse(price.text),
                      ),
                      planId: plan?.id,
                    );
                if (savedId != null && dialogContext.mounted) {
                  Navigator.pop(dialogContext, savedId);
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
  );
  key.dispose();
  name.dispose();
  description.dispose();
  price.dispose();
  return result;
}
