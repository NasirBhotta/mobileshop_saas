import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/responsive.dart';
import '../../data/models/customer_model.dart';
import '../providers/pos_provider.dart';

class CustomersScreen extends ConsumerWidget {
  const CustomersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const _CustomersBody();
  }
}

class _CustomersBody extends ConsumerStatefulWidget {
  const _CustomersBody();

  @override
  ConsumerState<_CustomersBody> createState() => _CustomersBodyState();
}

class _CustomersBodyState extends ConsumerState<_CustomersBody> {
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final customers = ref.watch(customersProvider);
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Customers',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: () => _showAddCustomerSheet(context),
                    icon: const Icon(Icons.person_add_rounded, size: 18),
                    label: const Text('Add'),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: TextField(
                controller: _searchCtrl,
                onChanged:
                    (value) =>
                        ref.read(customerListQueryProvider.notifier).state =
                            value,
                decoration: const InputDecoration(
                  hintText: 'Search name, phone, email...',
                  prefixIcon: Icon(Icons.search_rounded),
                ),
              ),
            ),
            Expanded(
              child: customers.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error:
                    (error, _) => Center(
                      child: Text(
                        error.toString(),
                        style: const TextStyle(color: AppColors.error),
                      ),
                    ),
                data: (items) {
                  if (items.isEmpty) {
                    return const Center(
                      child: Text(
                        'No customers yet',
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                    );
                  }
                  return RefreshIndicator(
                    onRefresh: () async => ref.invalidate(customersProvider),
                    child: ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: items.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final customer = items[index];
                        return _CustomerTile(customer: customer);
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddCustomerSheet(BuildContext context) {
    if (Responsive.isDesktop(context)) {
      showDialog<void>(
        context: context,
        builder:
            (_) => Dialog(
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 32,
                vertical: 24,
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: const _CustomerFormSheet(showHandle: false),
              ),
            ),
      );
      return;
    }

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _CustomerFormSheet(),
    );
  }
}

class _CustomerTile extends StatelessWidget {
  final CustomerModel customer;

  const _CustomerTile({required this.customer});

  @override
  Widget build(BuildContext context) {
    final due = customer.outstandingBalance;
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: AppColors.primary.withValues(alpha: 0.1),
          child: Text(
            customer.fullName.isEmpty
                ? '?'
                : customer.fullName[0].toUpperCase(),
            style: const TextStyle(
              color: AppColors.primary,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        title: Text(
          customer.fullName,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          [
            if (customer.phone != null) customer.phone,
            if (customer.email != null) customer.email,
            'Due Rs ${due.toStringAsFixed(0)}',
          ].join(' • '),
        ),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () => context.push('/customers/detail', extra: customer),
      ),
    );
  }
}

class CustomerDetailScreen extends ConsumerWidget {
  final CustomerModel customer;

  const CustomerDetailScreen({super.key, required this.customer});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashboard = ref.watch(customerDashboardProvider(customer.id!));
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(customer.fullName),
        actions: [
          IconButton(
            onPressed:
                () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  showDragHandle: true,
                  builder: (_) => _CreditLimitSheet(customerId: customer.id!),
                ),
            icon: const Icon(Icons.account_balance_wallet_rounded),
            tooltip: 'Credit limit',
          ),
        ],
      ),
      body: dashboard.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error:
            (error, _) => Center(
              child: Text(
                error.toString(),
                style: const TextStyle(color: AppColors.error),
              ),
            ),
        data: (data) {
          final limit = data.customer.creditLimit;
          return RefreshIndicator(
            onRefresh:
                () async =>
                    ref.invalidate(customerDashboardProvider(customer.id!)),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _MetricCard(
                      label: 'Lifetime Value',
                      value: 'Rs ${data.lifetimeValue.toStringAsFixed(0)}',
                      icon: Icons.trending_up_rounded,
                    ),
                    _MetricCard(
                      label: 'Outstanding',
                      value: 'Rs ${data.outstandingDues.toStringAsFixed(0)}',
                      icon: Icons.payments_rounded,
                      color:
                          data.outstandingDues > 0
                              ? AppColors.warning
                              : AppColors.success,
                    ),
                    _MetricCard(
                      label: 'Credit Limit',
                      value:
                          limit == null
                              ? 'Not set'
                              : 'Rs ${limit.toStringAsFixed(0)}',
                      icon: Icons.speed_rounded,
                    ),
                    _MetricCard(
                      label: 'Active Repairs',
                      value: data.activeRepairTickets.toString(),
                      icon: Icons.build_rounded,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.info.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: AppColors.info.withValues(alpha: 0.2),
                    ),
                  ),
                  child: const Text(
                    'Credit limit max khata allowance hai. Khata sale checkout par outstanding mein add hoti hai; Settle Dues se customer ki payment record hoti hai aur outstanding kam hota hai.',
                    style: TextStyle(
                      color: AppColors.info,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed:
                        data.outstandingDues <= 0
                            ? null
                            : () => showModalBottomSheet<void>(
                              context: context,
                              isScrollControlled: true,
                              showDragHandle: true,
                              builder:
                                  (_) => _SettleDuesSheet(
                                    customerId: customer.id!,
                                    outstanding: data.outstandingDues,
                                  ),
                            ),
                    icon: const Icon(Icons.task_alt_rounded, size: 18),
                    label: const Text('Settle Dues'),
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Purchase History',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                if (data.purchases.isEmpty)
                  const Text(
                    'No purchases found',
                    style: TextStyle(color: AppColors.textSecondary),
                  )
                else
                  ...data.purchases.map(
                    (sale) => Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        title: Text('Invoice ${sale.id ?? ''}'),
                        subtitle: Text(
                          sale.createdAt
                                  ?.toLocal()
                                  .toString()
                                  .split('.')
                                  .first ??
                              '',
                        ),
                        trailing: Text(
                          'Rs ${sale.total.toStringAsFixed(0)}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 20),
                const Text(
                  'Settlements',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                if (data.settlements.isEmpty)
                  const Text(
                    'No settlements yet',
                    style: TextStyle(color: AppColors.textSecondary),
                  )
                else
                  ...data.settlements.map(
                    (settlement) => Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: const Icon(Icons.receipt_long_rounded),
                        title: Text(
                          'Rs ${settlement.amount.toStringAsFixed(0)}',
                        ),
                        subtitle: Text(
                          '${settlement.method} • ${settlement.createdAt.toLocal().toString().split('.').first}',
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _MetricCard({
    required this.label,
    required this.value,
    required this.icon,
    this.color = AppColors.primary,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 190,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: color),
              const SizedBox(height: 10),
              Text(
                label,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CustomerFormSheet extends ConsumerStatefulWidget {
  final bool showHandle;

  const _CustomerFormSheet({this.showHandle = true});

  @override
  ConsumerState<_CustomerFormSheet> createState() => _CustomerFormSheetState();
}

class _CustomerFormSheetState extends ConsumerState<_CustomerFormSheet> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _notes = TextEditingController();
  final _creditLimit = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _email.dispose();
    _notes.dispose();
    _creditLimit.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(customerControllerProvider);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        widget.showHandle ? 0 : 16,
        16,
        MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Add Customer',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                ),
                if (!widget.showHandle)
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                    tooltip: 'Close',
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Full name'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Phone'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Email'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _creditLimit,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Credit limit',
                prefixText: 'Rs ',
                helperText: 'Owner set kare. Blank ka matlab fixed limit nahi.',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _notes,
              minLines: 2,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Notes'),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: state.isLoading ? null : _submit,
                child:
                    state.isLoading
                        ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                        : const Text('Save Customer'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (_name.text.trim().isEmpty) return;
    final customer = await ref
        .read(customerControllerProvider.notifier)
        .addCustomer(
          fullName: _name.text.trim(),
          phone: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
          email: _email.text.trim().isEmpty ? null : _email.text.trim(),
          notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
          creditLimit: double.tryParse(_creditLimit.text.trim()),
        );
    if (!mounted) return;
    if (customer == null) {
      final error = ref.read(customerControllerProvider).error;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error?.toString() ?? 'Customer save nahi hua'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }
    Navigator.pop(context);
  }
}

class _CreditLimitSheet extends ConsumerStatefulWidget {
  final String customerId;

  const _CreditLimitSheet({required this.customerId});

  @override
  ConsumerState<_CreditLimitSheet> createState() => _CreditLimitSheetState();
}

class _CreditLimitSheetState extends ConsumerState<_CreditLimitSheet> {
  final _limit = TextEditingController();

  @override
  void dispose() {
    _limit.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(customerControllerProvider);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Credit Limit',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _limit,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Limit',
              prefixText: 'Rs ',
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: state.isLoading ? null : () => _save(clear: true),
                  child: const Text('Clear'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: state.isLoading ? null : () => _save(),
                  child: const Text('Save'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _save({bool clear = false}) async {
    final customer = await ref
        .read(customerControllerProvider.notifier)
        .updateCreditLimit(
          customerId: widget.customerId,
          creditLimit: clear ? null : double.tryParse(_limit.text.trim()),
          clearCreditLimit: clear,
        );
    if (!mounted) return;
    if (customer == null) {
      final error = ref.read(customerControllerProvider).error;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error?.toString() ?? 'Credit limit save nahi hui'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }
    Navigator.pop(context);
  }
}

class _SettleDuesSheet extends ConsumerStatefulWidget {
  final String customerId;
  final double outstanding;

  const _SettleDuesSheet({required this.customerId, required this.outstanding});

  @override
  ConsumerState<_SettleDuesSheet> createState() => _SettleDuesSheetState();
}

class _SettleDuesSheetState extends ConsumerState<_SettleDuesSheet> {
  final _amount = TextEditingController();
  final _notes = TextEditingController();
  String _method = 'cash';

  @override
  void initState() {
    super.initState();
    _amount.text = widget.outstanding.toStringAsFixed(0);
  }

  @override
  void dispose() {
    _amount.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(customerSettlementControllerProvider);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Settle Dues',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _amount,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Amount',
              prefixText: 'Rs ',
            ),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: _method,
            items: const [
              DropdownMenuItem(value: 'cash', child: Text('Cash')),
              DropdownMenuItem(value: 'easypaisa', child: Text('EasyPaisa')),
              DropdownMenuItem(value: 'jazzcash', child: Text('JazzCash')),
              DropdownMenuItem(value: 'card', child: Text('Card')),
            ],
            onChanged: (value) => setState(() => _method = value ?? 'cash'),
            decoration: const InputDecoration(labelText: 'Method'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _notes,
            decoration: const InputDecoration(labelText: 'Notes'),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: state.isLoading ? null : _submit,
              child: const Text('Record Settlement'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    final amount = double.tryParse(_amount.text.trim()) ?? 0;
    final ok = await ref
        .read(customerSettlementControllerProvider.notifier)
        .settle(
          customerId: widget.customerId,
          amount: amount,
          method: _method,
          notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
        );
    if (!mounted) return;
    if (!ok) {
      final error = ref.read(customerSettlementControllerProvider).error;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error?.toString() ?? 'Settlement save nahi hui'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }
    Navigator.pop(context);
  }
}
