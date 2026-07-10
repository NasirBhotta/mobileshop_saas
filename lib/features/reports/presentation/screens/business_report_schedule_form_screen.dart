import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobileshop_saas/features/reports/presentation/providers/business_report_provider.dart';
import 'package:mobileshop_saas/features/reports/presentation/widgets/reports_back_button.dart';

import '../../data/models/business_report_models.dart';

class BusinessReportScheduleFormScreen extends ConsumerStatefulWidget {
  const BusinessReportScheduleFormScreen({super.key});

  @override
  ConsumerState<BusinessReportScheduleFormScreen> createState() =>
      _BusinessReportScheduleFormScreenState();
}

class _BusinessReportScheduleFormScreenState
    extends ConsumerState<BusinessReportScheduleFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();

  BusinessReportType _reportType = BusinessReportType.dashboard;
  String _cadence = 'daily';
  String _reportScope = 'branch';
  String _exportFormat = 'csv';

  DateTime _nextRunDate = DateTime.now().add(const Duration(days: 1));
  TimeOfDay _nextRunTime = const TimeOfDay(hour: 9, minute: 0);

  @override
  void initState() {
    super.initState();
    _nameController.text = 'Daily Business Dashboard';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controllerState = ref.watch(businessReportScheduleControllerProvider);

    return Scaffold(
      appBar: AppBar(
        leading: const ReportsBackButton(
          route: '/reports/business/schedules',
          tooltip: 'Back to Scheduled Business Reports',
        ),
        title: const Text('New Scheduled Report'),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820),
            child: Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  const _InfoBanner(),
                  const SizedBox(height: 14),
                  _SectionCard(
                    title: 'Report Details',
                    icon: Icons.analytics_outlined,
                    child: Column(
                      children: [
                        TextFormField(
                          controller: _nameController,
                          decoration: const InputDecoration(
                            labelText: 'Schedule Name',
                            hintText: 'Example: Daily Business Dashboard',
                            border: OutlineInputBorder(),
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Enter schedule name';
                            }

                            if (value.trim().length < 3) {
                              return 'Name is too short';
                            }

                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<BusinessReportType>(
                          initialValue: _reportType,
                          decoration: const InputDecoration(
                            labelText: 'Report Type',
                            border: OutlineInputBorder(),
                          ),
                          items:
                              BusinessReportType.values.map((type) {
                                return DropdownMenuItem(
                                  value: type,
                                  child: Text(type.label),
                                );
                              }).toList(),
                          onChanged: (value) {
                            if (value == null) return;

                            setState(() {
                              _reportType = value;
                              _nameController.text =
                                  '${_title(_cadence)} ${value.label}';
                            });
                          },
                        ),
                        const SizedBox(height: 12),
                        _ResponsiveWrap(
                          children: [
                            DropdownButtonFormField<String>(
                              initialValue: _cadence,
                              decoration: const InputDecoration(
                                labelText: 'Cadence',
                                border: OutlineInputBorder(),
                              ),
                              items: const [
                                DropdownMenuItem(
                                  value: 'daily',
                                  child: Text('Daily'),
                                ),
                                DropdownMenuItem(
                                  value: 'weekly',
                                  child: Text('Weekly'),
                                ),
                                DropdownMenuItem(
                                  value: 'monthly',
                                  child: Text('Monthly'),
                                ),
                              ],
                              onChanged: (value) {
                                if (value == null) return;

                                setState(() {
                                  _cadence = value;
                                  _nameController.text =
                                      '${_title(value)} ${_reportType.label}';
                                });
                              },
                            ),
                            DropdownButtonFormField<String>(
                              initialValue: _reportScope,
                              decoration: const InputDecoration(
                                labelText: 'Scope',
                                border: OutlineInputBorder(),
                              ),
                              items: const [
                                DropdownMenuItem(
                                  value: 'branch',
                                  child: Text('Current Branch'),
                                ),
                                DropdownMenuItem(
                                  value: 'all_branches',
                                  child: Text('All Branches'),
                                ),
                              ],
                              onChanged: (value) {
                                if (value == null) return;
                                setState(() => _reportScope = value);
                              },
                            ),
                            DropdownButtonFormField<String>(
                              initialValue: _exportFormat,
                              decoration: const InputDecoration(
                                labelText: 'Export Format',
                                border: OutlineInputBorder(),
                              ),
                              items: const [
                                DropdownMenuItem(
                                  value: 'csv',
                                  child: Text('CSV'),
                                ),
                                DropdownMenuItem(
                                  value: 'pdf',
                                  child: Text('PDF'),
                                ),
                              ],
                              onChanged: (value) {
                                if (value == null) return;
                                setState(() => _exportFormat = value);
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  _SectionCard(
                    title: 'Delivery',
                    icon: Icons.email_outlined,
                    child: Column(
                      children: [
                        TextFormField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          decoration: const InputDecoration(
                            labelText: 'Send To Email',
                            hintText: 'owner@example.com',
                            border: OutlineInputBorder(),
                          ),
                          validator: (value) {
                            final trimmed = value?.trim() ?? '';

                            if (trimmed.isEmpty) {
                              return 'Enter email address';
                            }

                            final valid = RegExp(
                              r'^[^@\s]+@[^@\s]+\.[^@\s]+$',
                            ).hasMatch(trimmed);

                            if (!valid) {
                              return 'Enter a valid email';
                            }

                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        _ResponsiveWrap(
                          children: [
                            _DateBox(
                              label: 'First Run Date',
                              value: _dateText(_nextRunDate),
                              icon: Icons.date_range,
                              onTap: _pickDate,
                            ),
                            _DateBox(
                              label: 'First Run Time',
                              value: _nextRunTime.format(context),
                              icon: Icons.schedule,
                              onTap: _pickTime,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  FilledButton.icon(
                    onPressed: controllerState.isLoading ? null : _submit,
                    icon:
                        controllerState.isLoading
                            ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                            : const Icon(Icons.schedule_send_outlined),
                    label: Text(
                      controllerState.isLoading
                          ? 'Creating...'
                          : 'Create Schedule',
                    ),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton(
                    onPressed:
                        controllerState.isLoading
                            ? null
                            : () => context.go('/reports/business/schedules'),
                    child: const Text('Cancel'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
      initialDate: _nextRunDate,
    );

    if (picked == null) return;

    setState(() {
      _nextRunDate = DateTime(picked.year, picked.month, picked.day);
    });
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _nextRunTime,
    );

    if (picked == null) return;

    setState(() {
      _nextRunTime = picked;
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final nextRunAt = DateTime(
      _nextRunDate.year,
      _nextRunDate.month,
      _nextRunDate.day,
      _nextRunTime.hour,
      _nextRunTime.minute,
    );

    if (nextRunAt.isBefore(DateTime.now())) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('First run time must be in the future.')),
      );
      return;
    }

    final schedule = await ref
        .read(businessReportScheduleControllerProvider.notifier)
        .createSchedule(
          name: _nameController.text.trim(),
          reportType: _reportType,
          cadence: _cadence,
          reportScope: _reportScope,
          exportFormat: _exportFormat,
          sendToEmail: _emailController.text.trim(),
          nextRunAt: nextRunAt,
        );

    if (!mounted) return;

    final error = ref.read(businessReportScheduleControllerProvider).asError;

    if (error != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.error.toString())));
      return;
    }

    if (schedule == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not create schedule')),
      );
      return;
    }

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Schedule created')));

    context.go('/reports/business/schedules');
  }
}

class _InfoBanner extends StatelessWidget {
  const _InfoBanner();

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: const Padding(
        padding: EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Scheduled reports and CSV/PDF exports are available only for Business and Enterprise tenants. The database queues delivery jobs; an Edge Function or backend worker will send the emails.',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;

  const _SectionCard({
    required this.title,
    required this.icon,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icon),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
  }
}

class _ResponsiveWrap extends StatelessWidget {
  final List<Widget> children;

  const _ResponsiveWrap({required this.children});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (_, constraints) {
        final isWide = constraints.maxWidth >= 680;

        if (!isWide) {
          return Column(
            children: [
              for (int i = 0; i < children.length; i++) ...[
                children[i],
                if (i != children.length - 1) const SizedBox(height: 12),
              ],
            ],
          );
        }

        return Row(
          children: [
            for (int i = 0; i < children.length; i++) ...[
              Expanded(child: children[i]),
              if (i != children.length - 1) const SizedBox(width: 12),
            ],
          ],
        );
      },
    );
  }
}

class _DateBox extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final VoidCallback onTap;

  const _DateBox({
    required this.label,
    required this.value,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          isDense: true,
          suffixIcon: Icon(icon),
        ),
        child: Text(value),
      ),
    );
  }
}

String _title(String value) {
  return value
      .replaceAll('_', ' ')
      .split(' ')
      .where((part) => part.trim().isNotEmpty)
      .map((part) {
        final lower = part.toLowerCase();
        return '${lower[0].toUpperCase()}${lower.substring(1)}';
      })
      .join(' ');
}

String _dateText(DateTime date) {
  final day = date.day.toString().padLeft(2, '0');
  final month = date.month.toString().padLeft(2, '0');
  final year = date.year.toString();

  return '$day-$month-$year';
}
