import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/platform_analytics.dart';
import 'platform_providers.dart';

class PlatformSettingsScreen extends ConsumerWidget {
  const PlatformSettingsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(platformSettingsProvider);
    return ListView(
      padding: const EdgeInsets.all(32),
      children: [
        Text(
          'Global platform settings',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 24),
        data.when(
          loading: () => const LinearProgressIndicator(),
          error: (e, _) => Text('Could not load settings: $e'),
          data: (s) => _SettingsForm(initial: s),
        ),
      ],
    );
  }
}

class _SettingsForm extends ConsumerStatefulWidget {
  final PlatformSettings initial;
  const _SettingsForm({required this.initial});
  @override
  ConsumerState<_SettingsForm> createState() => _SettingsFormState();
}

class _SettingsFormState extends ConsumerState<_SettingsForm> {
  late final TextEditingController trial,
      grace,
      currency,
      email,
      phone,
      message;
  late String cycle;
  late bool maintenance;
  @override
  void initState() {
    super.initState();
    final s = widget.initial;
    trial = TextEditingController(text: '${s.trialDays}');
    grace = TextEditingController(text: '${s.graceDays}');
    currency = TextEditingController(text: s.currency);
    email = TextEditingController(text: s.email);
    phone = TextEditingController(text: s.phone);
    message = TextEditingController(text: s.message);
    cycle = s.cycle;
    maintenance = s.maintenance;
  }

  @override
  void dispose() {
    for (final c in [trial, grace, currency, email, phone, message]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final busy = ref.watch(settingsMutationProvider).isLoading;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            TextField(
              controller: trial,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Default trial duration (days)',
              ),
            ),
            TextField(
              controller: grace,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Default grace period (days)',
              ),
            ),
            DropdownButtonFormField(
              initialValue: cycle,
              items:
                  ['monthly', 'annual']
                      .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                      .toList(),
              onChanged: (v) => setState(() => cycle = v!),
              decoration: const InputDecoration(
                labelText: 'Default billing cycle',
              ),
            ),
            TextField(
              controller: currency,
              maxLength: 3,
              decoration: const InputDecoration(labelText: 'Default currency'),
            ),
            TextField(
              controller: email,
              decoration: const InputDecoration(labelText: 'Support email'),
            ),
            TextField(
              controller: phone,
              decoration: const InputDecoration(labelText: 'Support phone'),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Maintenance mode'),
              value: maintenance,
              onChanged: (v) => setState(() => maintenance = v),
            ),
            TextField(
              controller: message,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Maintenance message',
              ),
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: busy ? null : _save,
                icon: const Icon(Icons.save),
                label: const Text('Save settings'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    final value = PlatformSettings(
      trialDays: int.tryParse(trial.text) ?? -1,
      graceDays: int.tryParse(grace.text) ?? -1,
      cycle: cycle,
      currency: currency.text.trim().toUpperCase(),
      maintenance: maintenance,
      email: _optional(email.text),
      phone: _optional(phone.text),
      message: _optional(message.text),
    );
    final ok = await ref.read(settingsMutationProvider.notifier).save(value);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ok ? 'Settings saved.' : 'Could not save settings.'),
        ),
      );
    }
  }
}

String? _optional(String value) => value.trim().isEmpty ? null : value.trim();
