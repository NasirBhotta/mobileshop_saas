import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobileshop_saas/features/reports/presentation/providers/sales_report_provider.dart';
import 'package:mobileshop_saas/features/reports/presentation/widgets/reports_back_button.dart';

import '../../data/models/sales_report_models.dart';

class SalesReportScheduleFormScreen extends ConsumerStatefulWidget {
  const SalesReportScheduleFormScreen({super.key});

  @override
  ConsumerState<SalesReportScheduleFormScreen> createState() =>
      _SalesReportScheduleFormScreenState();
}

class _SalesReportScheduleFormScreenState
    extends ConsumerState<SalesReportScheduleFormScreen> {
  final _formKey = GlobalKey<FormState>();

  final _nameController = TextEditingController();
  final _emailController = TextEditingController();

  SalesReportCadence _cadence = SalesReportCadence.daily;
  SalesReportScope _scope = SalesReportScope.branch;
  SalesReportExportFormat _format = SalesReportExportFormat.csv;

  DateTime _nextRunDate = DateTime.now().add(const Duration(days: 1));
  TimeOfDay _nextRunTime = const TimeOfDay(hour: 8, minute: 0);

  @override
  void initState() {
    super.initState();

    _nameController.text = 'Daily Sales Report';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controllerState = ref.watch(salesReportScheduleControllerProvider);
    final saving = controllerState.isLoading;

    return Scaffold(
      appBar: AppBar(
        leading: const ReportsBackButton(
          route: '/reports/sales/schedules',
          tooltip: 'Back to Scheduled Sales Reports',
        ),
        title: const Text('Create Report Schedule'),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _InfoBanner(
                    text:
                        'Scheduled reports are available only for Business and Enterprise plans. Reports will be queued for email delivery by your backend worker or Supabase Edge Function.',
                  ),
                  const SizedBox(height: 12),
                  _SectionCard(
                    title: 'Schedule Details',
                    child: Column(
                      children: [
                        TextFormField(
                          controller: _nameController,
                          decoration: const InputDecoration(
                            labelText: 'Schedule Name',
                            hintText: 'Daily Sales Report',
                            border: OutlineInputBorder(),
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Schedule name is required';
                            }

                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        _ResponsiveWrap(
                          children: [
                            DropdownButtonFormField<SalesReportCadence>(
                              initialValue: _cadence,
                              decoration: const InputDecoration(
                                labelText: 'Cadence',
                                border: OutlineInputBorder(),
                              ),
                              items:
                                  SalesReportCadence.values.map((cadence) {
                                    return DropdownMenuItem(
                                      value: cadence,
                                      child: Text(cadence.label),
                                    );
                                  }).toList(),
                              onChanged:
                                  saving
                                      ? null
                                      : (value) {
                                        if (value == null) return;

                                        setState(() {
                                          _cadence = value;
                                          _nameController.text =
                                              '${value.label} Sales Report';
                                        });
                                      },
                            ),
                            DropdownButtonFormField<SalesReportScope>(
                              initialValue: _scope,
                              decoration: const InputDecoration(
                                labelText: 'Report Scope',
                                border: OutlineInputBorder(),
                              ),
                              items:
                                  SalesReportScope.values.map((scope) {
                                    return DropdownMenuItem(
                                      value: scope,
                                      child: Text(scope.label),
                                    );
                                  }).toList(),
                              onChanged:
                                  saving
                                      ? null
                                      : (value) {
                                        if (value == null) return;
                                        setState(() => _scope = value);
                                      },
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _ResponsiveWrap(
                          children: [
                            DropdownButtonFormField<SalesReportExportFormat>(
                              initialValue: _format,
                              decoration: const InputDecoration(
                                labelText: 'Export Format',
                                border: OutlineInputBorder(),
                              ),
                              items:
                                  SalesReportExportFormat.values.map((format) {
                                    return DropdownMenuItem(
                                      value: format,
                                      child: Text(format.label),
                                    );
                                  }).toList(),
                              onChanged:
                                  saving
                                      ? null
                                      : (value) {
                                        if (value == null) return;
                                        setState(() => _format = value);
                                      },
                            ),
                            TextFormField(
                              controller: _emailController,
                              keyboardType: TextInputType.emailAddress,
                              decoration: const InputDecoration(
                                labelText: 'Send To Email',
                                hintText: 'owner@example.com',
                                border: OutlineInputBorder(),
                              ),
                              validator: (value) {
                                final email = value?.trim() ?? '';

                                if (email.isEmpty) {
                                  return 'Email is required';
                                }

                                final valid = RegExp(
                                  r'^[^@\s]+@[^@\s]+\.[^@\s]+$',
                                ).hasMatch(email);

                                if (!valid) {
                                  return 'Enter valid email';
                                }

                                return null;
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  _SectionCard(
                    title: 'First Delivery Time',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _ResponsiveWrap(
                          children: [
                            _DateBox(
                              label: 'First Run Date',
                              value: _dateText(_nextRunDate),
                              icon: Icons.calendar_today_outlined,
                              onTap: saving ? null : _pickDate,
                            ),
                            _DateBox(
                              label: 'First Run Time',
                              value: _nextRunTime.format(context),
                              icon: Icons.access_time,
                              onTap: saving ? null : _pickTime,
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          _cadenceHelpText(_cadence),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: saving ? null : _submit,
                    icon:
                        saving
                            ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                            : const Icon(Icons.schedule_send_outlined),
                    label: Text(saving ? 'Creating...' : 'Create Schedule'),
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
      initialDate: _nextRunDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
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
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final nextRunAt = DateTime(
      _nextRunDate.year,
      _nextRunDate.month,
      _nextRunDate.day,
      _nextRunTime.hour,
      _nextRunTime.minute,
    );

    if (nextRunAt.isBefore(DateTime.now())) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('First run time must be in the future')),
      );
      return;
    }

    final schedule = await ref
        .read(salesReportScheduleControllerProvider.notifier)
        .createSchedule(
          name: _nameController.text,
          cadence: _cadence,
          reportScope: _scope,
          exportFormat: _format,
          sendToEmail: _emailController.text,
          nextRunAt: nextRunAt,
        );

    if (!mounted) return;

    if (schedule == null) {
      final error = ref.read(salesReportScheduleControllerProvider).asError;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error?.error.toString() ?? 'Schedule not created'),
        ),
      );

      return;
    }

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Report schedule created')));

    context.go('/reports/sales/schedules');
  }

  String _cadenceHelpText(SalesReportCadence cadence) {
    switch (cadence) {
      case SalesReportCadence.daily:
        return 'Daily schedule sends previous day sales report.';
      case SalesReportCadence.weekly:
        return 'Weekly schedule sends previous 7 days sales report.';
      case SalesReportCadence.monthly:
        return 'Monthly schedule sends previous month sales report.';
    }
  }
}

class _InfoBanner extends StatelessWidget {
  final String text;

  const _InfoBanner({required this.text});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.info_outline),
            const SizedBox(width: 10),
            Expanded(child: Text(text)),
          ],
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;

  const _SectionCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
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
        final itemWidth =
            constraints.maxWidth >= 700
                ? (constraints.maxWidth - 12) / 2
                : constraints.maxWidth;

        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children:
              children
                  .map((child) => SizedBox(width: itemWidth, child: child))
                  .toList(),
        );
      },
    );
  }
}

class _DateBox extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final VoidCallback? onTap;

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
          suffixIcon: Icon(icon),
        ),
        child: Text(value),
      ),
    );
  }
}

String _dateText(DateTime date) {
  final day = date.day.toString().padLeft(2, '0');
  final month = date.month.toString().padLeft(2, '0');
  final year = date.year.toString();

  return '$day-$month-$year';
}
