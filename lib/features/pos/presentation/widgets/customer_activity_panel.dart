import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/entitlements/entitlement_provider.dart';
import '../../../../core/authorization/permission_provider.dart';
import '../../data/models/customer_activity_model.dart';
import '../../data/models/customer_model.dart';
import '../../data/models/sale_model.dart';
import '../../data/services/receipt_service.dart';
import '../../../repairs/data/models/repair_ticket_model.dart';
import '../../../repairs/data/services/thermal_receipt_service.dart';
import '../../../settings/presentation/providers/receipt_settings_provider.dart';
import '../providers/pos_provider.dart';

class CustomerActivityPanel extends ConsumerStatefulWidget {
  final CustomerModel customer;
  const CustomerActivityPanel({super.key, required this.customer});
  @override
  ConsumerState<CustomerActivityPanel> createState() =>
      _CustomerActivityPanelState();
}

class _CustomerActivityPanelState extends ConsumerState<CustomerActivityPanel> {
  late Future<CustomerActivityPage> _page;
  String _period = 'Month';
  DateTime? _from;
  DateTime? _to;
  int _offset = 0;
  bool _printing = false;

  @override
  void initState() {
    super.initState();
    _setDates('Month');
    _load();
  }

  @override
  void didUpdateWidget(CustomerActivityPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.customer != widget.customer) _load();
  }

  void _setDates(String period) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    _to = today.add(const Duration(days: 1));
    _from = switch (period) {
      'Day' => today,
      'Week' => today.subtract(Duration(days: today.weekday - 1)),
      'Month' => DateTime(now.year, now.month),
      _ => null,
    };
    if (period == 'All') _to = null;
  }

  void _load() {
    _page = ref
        .read(posRepositoryProvider)
        .fetchCustomerActivity(
          widget.customer.id!,
          from: _from,
          to: _to,
          offset: _offset,
        );
  }

  Future<void> _changePeriod(String period) async {
    DateTimeRange? range;
    if (period == 'Custom') {
      range = await showDateRangePicker(
        context: context,
        firstDate: DateTime(2000),
        lastDate: DateTime.now().add(const Duration(days: 366)),
      );
      if (!mounted || range == null) return;
    }
    setState(() {
      _period = period;
      _offset = 0;
      if (range != null) {
        _from = range.start;
        _to = DateTime(range.end.year, range.end.month, range.end.day + 1);
      } else {
        _setDates(period);
      }
      _load();
    });
  }

  Future<void> _print(Map<String, dynamic> entry) async {
    setState(() => _printing = true);
    try {
      final repair = entry['kind'] == 'repair';
      await ref
          .read(permissionEvaluatorProvider)
          .require(
            repair ? 'repair.ticket.view' : 'pos.sale.view',
            message: 'Receipt access permission required.',
          );
      final document = await ref
          .read(posRepositoryProvider)
          .customerActivityDocument(
            customerId: widget.customer.id!,
            id: entry['id'] as String,
            repair: repair,
          );
      final config = await ref.read(receiptConfigurationProvider.future);
      bool printed;
      if (repair) {
        final ticket = RepairTicketModel.fromMap(document);
        if (ticket.ticketNo == null) {
          throw StateError('No existing repair receipt.');
        }
        printed = await ThermalReceiptService.printRepairTicket(
          ticket: ticket,
          config: config,
          advancePaid: (entry['paid'] as num).toDouble(),
          isDuplicate: true,
        );
      } else {
        printed = await ReceiptService.printReceipt(
          sale: SaleModel.fromMap(document),
          config: config,
          duplicate: true,
          entitlementEvaluator: ref.read(entitlementEvaluatorProvider),
        );
      }
      if (!printed) throw StateError('Receipt was not printed.');
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Print: $error')));
      }
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text(
                'Customer history & analytics (current branch)',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              DropdownButton<String>(
                value: _period,
                items: [
                  for (final period in [
                    'Day',
                    'Week',
                    'Month',
                    'Custom',
                    'All',
                  ])
                    DropdownMenuItem(value: period, child: Text(period)),
                ],
                onChanged: (value) {
                  if (value != null) _changePeriod(value);
                },
              ),
              IconButton(
                tooltip: 'Refresh history',
                icon: const Icon(Icons.refresh),
                onPressed: () => setState(_load),
              ),
            ],
          ),
          if (_from != null)
            Text(
              '${_from!.toLocal().toString().split(' ').first} – ${_to!.subtract(const Duration(days: 1)).toLocal().toString().split(' ').first}',
            ),
          FutureBuilder<CustomerActivityPage>(
            future: _page,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const LinearProgressIndicator();
              }
              if (snapshot.hasError) {
                return Text('History unavailable: ${snapshot.error}');
              }
              final page = snapshot.data!;
              final salesBalance = widget.customer.outstandingBalance;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (page.cached)
                    const Text(
                      'Cached history only — totals may be incomplete, including pending sync.',
                    ),
                  Text(
                    'Purchases: ${page.amount('purchases').toInt()}  •  Repairs: ${page.amount('repairs').toInt()}  •  Visits: ${page.amount('visits').toInt()}',
                  ),
                  Text(
                    'Purchase amount: Rs ${page.amount('purchase_amount').toStringAsFixed(2)}  •  Repair charges: Rs ${page.amount('repair_amount').toStringAsFixed(2)}',
                  ),
                  Text(
                    'Payments received (net repair refunds): Rs ${page.amount('payments').toStringAsFixed(2)}',
                  ),
                  Text(
                    'Sales account balance (all branches): Rs ${salesBalance.toStringAsFixed(2)}  •  Current repair balance: Rs ${page.amount('repair_balance').toStringAsFixed(2)}',
                  ),
                  const Text(
                    'Visits count each original sale or repair once; edits and payments add no visits.',
                    style: TextStyle(fontSize: 12),
                  ),
                  const Divider(),
                  if (page.entries.isEmpty)
                    const Text('No transactions in this range.'),
                  for (final entry in page.entries)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      isThreeLine: true,
                      leading: Icon(
                        entry['kind'] == 'repair'
                            ? Icons.build_outlined
                            : Icons.receipt_long_outlined,
                      ),
                      title: Text(
                        '${entry['kind'] == 'repair' ? 'Repair' : 'Invoice'} ${entry['reference'] ?? entry['id']} • ${entry['status']}',
                      ),
                      subtitle: Text(
                        '${entry['description'] ?? ''}\n${DateTime.tryParse(entry['created_at']?.toString() ?? '')?.toLocal() ?? ''}\nRs ${entry['amount']} • Paid Rs ${entry['paid']} • ${entry['kind'] == 'sale' ? 'Balance at checkout' : 'Balance'} Rs ${((entry['active'] == true || entry['active'] == 1) ? ((entry['amount'] as num) - (entry['paid'] as num)).clamp(0, double.infinity) : 0).toStringAsFixed(2)}',
                      ),
                      trailing:
                          (entry['printable'] == true ||
                                  entry['printable'] == 1)
                              ? IconButton(
                                tooltip: 'Print Receipt',
                                icon: const Icon(Icons.print_outlined),
                                onPressed:
                                    _printing ? null : () => _print(entry),
                              )
                              : null,
                    ),
                  Row(
                    children: [
                      TextButton(
                        onPressed:
                            _offset == 0
                                ? null
                                : () => setState(() {
                                  _offset -= 25;
                                  _load();
                                }),
                        child: const Text('Previous'),
                      ),
                      Text(
                        '${_offset + (page.entries.isEmpty ? 0 : 1)}–${_offset + page.entries.length} / ${page.count}',
                      ),
                      TextButton(
                        onPressed:
                            _offset + 25 >= page.count
                                ? null
                                : () => setState(() {
                                  _offset += 25;
                                  _load();
                                }),
                        child: const Text('Next'),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ],
      ),
    ),
  );
}
