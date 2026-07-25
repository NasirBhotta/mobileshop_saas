import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../reports/presentation/widgets/reports_back_button.dart';
import '../../data/models/mobile_service_models.dart';
import '../providers/mobile_services_provider.dart';

class MobileServiceReportScreen extends ConsumerWidget {
  const MobileServiceReportScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(mobileServiceReportFilterProvider);
    final providers = ref.watch(mobileServiceProvidersProvider);
    final report = ref.watch(mobileServiceReportProvider);

    return Scaffold(
      appBar: AppBar(
        leading: const ReportsBackButton(),
        title: const Text('Mobile Services Report'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Wrap(
                spacing: 12,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => _pickDates(context, ref, filter),
                    icon: const Icon(Icons.date_range_outlined),
                    label: Text(
                      '${DateFormat('dd MMM yyyy').format(filter.from)} — '
                      '${DateFormat('dd MMM yyyy').format(filter.to)}',
                    ),
                  ),
                  SizedBox(
                    width: 240,
                    child: providers.when(
                      loading:
                          () => const LinearProgressIndicator(minHeight: 2),
                      error: (_, _) => const Text('Providers unavailable'),
                      data:
                          (items) => DropdownButtonFormField<String?>(
                            initialValue: filter.providerId,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Provider',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            items: [
                              const DropdownMenuItem<String?>(
                                value: null,
                                child: Text('All providers'),
                              ),
                              for (final provider in items)
                                DropdownMenuItem<String?>(
                                  value: provider.id,
                                  child: Text(provider.name),
                                ),
                            ],
                            onChanged: (value) {
                              ref
                                  .read(
                                    mobileServiceReportFilterProvider.notifier,
                                  )
                                  .state = filter.copyWith(
                                providerId: value,
                                clearProvider: value == null,
                              );
                            },
                          ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: report.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error:
                    (error, _) => _ReportError(
                      error: error,
                      onRetry:
                          () => ref.invalidate(mobileServiceReportProvider),
                    ),
                data:
                    (summary) => RefreshIndicator(
                      onRefresh: () async {
                        ref.invalidate(mobileServiceReportProvider);
                        await ref.read(mobileServiceReportProvider.future);
                      },
                      child: _ReportBody(summary: summary),
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickDates(
    BuildContext context,
    WidgetRef ref,
    MobileServiceReportFilter filter,
  ) async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: DateTimeRange(start: filter.from, end: filter.to),
    );
    if (picked == null) return;
    ref
        .read(mobileServiceReportFilterProvider.notifier)
        .state = filter.copyWith(
      from: DateTime(picked.start.year, picked.start.month, picked.start.day),
      to: DateTime(picked.end.year, picked.end.month, picked.end.day),
    );
  }
}

class _ReportBody extends StatelessWidget {
  final MobileServiceReportSummary summary;

  const _ReportBody({required this.summary});

  @override
  Widget build(BuildContext context) {
    final money = NumberFormat.currency(symbol: 'Rs. ', decimalDigits: 0);
    final cards = [
      ('Transactions', '${summary.transactionCount}', Icons.receipt_long),
      ('Send', '${summary.sendCount}', Icons.north_east),
      ('Receive', '${summary.receiveCount}', Icons.south_west),
      ('Sent amount', money.format(summary.sentAmount), Icons.upload),
      ('Received amount', money.format(summary.receivedAmount), Icons.download),
      ('Cash received', money.format(summary.customerCashIn), Icons.add_card),
      ('Cash paid', money.format(summary.customerCashOut), Icons.payments),
      ('Profit', money.format(summary.profit), Icons.trending_up),
    ];
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1100),
            child: GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: MediaQuery.sizeOf(context).width >= 850 ? 4 : 2,
                mainAxisExtent: 130,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              itemCount: cards.length,
              itemBuilder: (_, index) {
                final card = cards[index];
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(card.$3),
                        const Spacer(),
                        Text(card.$1),
                        Text(
                          card.$2,
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _ReportError extends StatelessWidget {
  final Object error;
  final VoidCallback onRetry;

  const _ReportError({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 42),
            const SizedBox(height: 12),
            Text(error.toString(), textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
