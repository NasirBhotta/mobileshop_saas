from pathlib import Path
root=Path(__file__).resolve().parents[1]
def read(p): return (root/p).read_text(encoding='utf-8')
def write(p,s): (root/p).write_text(s,encoding='utf-8')
p='lib/features/repairs/data/repositories/repair_repository.dart'; s=read(p)
s="import 'package:mobileshop_saas/core/local/local_store.dart';\nimport 'package:mobileshop_saas/features/pos/data/models/customer_model.dart';\nimport 'package:mobileshop_saas/features/pos/data/repositories/sale_customer_resolver.dart';\n"+s
# Gate selected customers by actual local tenant before accepting offline writes.
s=s.replace('    final ticketId = const Uuid().v4();', '''    if (customerId != null) {
      customerId = await LocalStore.resolveCustomerId(customerId);
      final customer = await OfflineStore.loadCustomerById(customerId);
      if (customer == null || customer.tenantId != tenantId) {
        throw StateError('Selected customer is not available in this shop.');
      }
    }
    final ticketId = const Uuid().v4();''',1)
s=s.replace('      final data = await _client\n          .from(\'repair_tickets\')\n          .insert(_remoteTicketMap(ticketToCommit))', '''      final remoteMap = _remoteTicketMap(ticketToCommit);
      await _resolveRepairCustomer(remoteMap);
      final data = await _client
          .from('repair_tickets')
          .insert(remoteMap)''',1)
s=s.replace('    if (ticket.status == status) return ticket;', '''    if (ticket.status == status) return ticket;
    if (status == RepairTicketStatus.delivered) {
      return _deliverRepair(ticket);
    }''',1)
# Change new completion calls only; queued v2 replay is left intact.
a=s.index('  Future<RepairTicketModel> completeRepair('); b=s.index('  Future<RepairTicketModel> cancelRepair(',a)
s=s[:a]+'''  Future<RepairTicketModel> completeRepair({
    required RepairTicketModel ticket, required double customerCharge,
    double serviceCharge = 0, double discount = 0,
    double commission = 0, double otherDirectCost = 0,
  }) async {
    await _gate.require('repairs.tickets');
    final eventId = const Uuid().v4();
    final payload = <String, dynamic>{
      'ticket_id': ticket.id, 'event_id': eventId,
      'customer_charge': customerCharge, 'service_charge': serviceCharge,
      'discount': discount, 'commission': commission, 'other_direct_cost': otherDirectCost,
    };
    Future<void> local() => RepairFinancialLocalCommitter.prepare(
      ticket: ticket, eventId: eventId, userId: _currentUser.id,
      customerCharge: customerCharge, serviceCharge: serviceCharge,
      discount: discount, commission: commission, otherDirectCost: otherDirectCost,
    );
    await _commitDeferredRepair('prepare_repair_ticket_v3', payload, local);
    final updated = await LocalStore.loadRepairTicketById(ticket.id);
    if (updated == null) throw StateError('Repair ticket not found.');
    await OfflineStore.saveRepairTicket(updated);
    return updated;
  }

  Future<RepairTicketModel> _deliverRepair(RepairTicketModel ticket) async {
    if (ticket.status != RepairTicketStatus.completed) {
      throw StateError('Only completed tickets may be delivered.');
    }
    final eventId = const Uuid().v4();
    final payload = <String, dynamic>{'ticket_id': ticket.id, 'event_id': eventId};
    Future<void> local() => RepairFinancialLocalCommitter.complete(
      ticket: ticket, eventId: eventId, userId: _currentUser.id,
      customerCharge: ticket.customerCharge ?? ticket.totalCost ?? 0,
      serviceCharge: ticket.serviceCharge, discount: ticket.discountAmount,
      commission: ticket.perJobCommission, otherDirectCost: ticket.otherDirectCost,
      atDelivery: true,
    );
    await _commitDeferredRepair('deliver_repair_ticket_v3', payload, local);
    final updated = await LocalStore.loadRepairTicketById(ticket.id);
    if (updated == null) throw StateError('Repair ticket not found.');
    await OfflineStore.saveRepairTicket(updated);
    return updated;
  }

  Future<void> _commitDeferredRepair(String type, Map<String, dynamic> payload,
      Future<void> Function() local) async {
    // Do not let an online command overtake this ticket's queued parents/parts.
    final pending = await OfflineStore.loadMutations(_currentUser.id);
    final hasPendingParent = pending.any((m) =>
      m.payload['ticket_id'] == payload['ticket_id'] ||
      (m.payload['ticket'] is Map && (m.payload['ticket'] as Map)['id'] == payload['ticket_id']));
    if (!hasPendingParent) {
      try {
        await _syncDeferredRepair(type, payload).timeout(_networkTimeout);
      } catch (error) {
        OfflineErrorClassifier.rethrowIfTerminal(error);
        await local();
        await OfflineStore.enqueueMutation(userId: _currentUser.id, type: type, payload: payload);
        return;
      }
      await local();
      return;
    }
    await local();
    await OfflineStore.enqueueMutation(userId: _currentUser.id, type: type, payload: payload);
  }

  Future<void> _syncDeferredRepair(String type, Map<String, dynamic> payload) async {
    await _client.rpc(type, params: {
      for (final key in ['ticket_id','event_id',
        if (type == 'prepare_repair_ticket_v3') ...[
          'customer_charge','service_charge','discount','commission','other_direct_cost']])
        'p_$key': payload[key],
    });
  }

''' + s[b:]
# Every repair mutation participates in dependency ordering, including parent creation.
a=s.index('      final financialTicketId ='); b=s.index('      if (financialTicketId != null',a)
s=s[:a]+'''      final financialTicketId = mutation.payload['ticket_id'] as String? ??
          (mutation.payload['ticket'] is Map
            ? (mutation.payload['ticket'] as Map)['id'] as String? : null);
'''+s[b:]
anchor="          case 'complete_repair_ticket_v2':"
s=s.replace(anchor,"          case 'prepare_repair_ticket_v3':\n          case 'deliver_repair_ticket_v3':\n            await _syncDeferredRepair(mutation.type, mutation.payload);\n            break;\n"+anchor,1)
s=s.replace("    ticketMap.remove('inventory_unit_id');", "    ticketMap.remove('inventory_unit_id');\n    await _resolveRepairCustomer(ticketMap);",1)
# Reuse existing customer resolver, insert-only pending creations and persisted aliases.
pos=s.index('  Future<void> _syncUpsertRepairTicket(')
s=s[:pos]+'''  Future<void> _resolveRepairCustomer(Map<String, dynamic> ticket) async {
    final id = ticket['customer_id'] as String?;
    if (id == null) return;
    final tenantId = ticket['tenant_id'] as String;
    Future<CustomerModel?> find(String column, String value) async {
      final row = await _client.from('customers').select()
        .eq('tenant_id', tenantId).eq(column, value).maybeSingle();
      return row == null ? null : CustomerModel.fromMap(row);
    }
    final customer = await SaleCustomerResolver(
      resolveId: LocalStore.resolveCustomerId,
      findRemote: (id) => find('id', id),
      loadLocal: (id) async {
        final c = await OfflineStore.loadCustomerById(id);
        return c?.tenantId == tenantId ? c : null;
      },
      findByPhone: (phone) => find('phone', phone),
      pendingCreation: (id) async {
        for (final m in await OfflineStore.loadMutations(_currentUser.id)) {
          if (m.type == 'add_customer' && m.payload['id'] == id &&
              m.payload['tenant_id'] == tenantId) return Map<String,dynamic>.from(m.payload);
        }
        return null;
      },
      createIfMissing: (payload) async {
        await _client.from('customers').upsert({
          for (final key in ['id','tenant_id','branch_id','full_name','phone','email','notes','credit_limit','created_at'])
            key: payload[key], 'outstanding_balance': 0,
        }, onConflict: 'id', ignoreDuplicates: true);
      },
      rememberAlias: (local, remote) => LocalStore.reassignCustomerId(
        localCustomerId: local, remoteCustomerId: remote),
    ).resolve(id);
    if (customer.tenantId != tenantId) throw StateError('Customer shop mismatch.');
    ticket['customer_id'] = customer.id;
  }

''' + s[pos:]
write(p,s)

# Optional result callback preserves existing POS callers and cart behavior.
p='lib/features/pos/presentation/widgets/customer_attach_sheet.dart'; s=read(p)
s="import '../../data/models/customer_model.dart';\n"+s
s=s.replace('  final WidgetRef ref;','  final WidgetRef ref;\n  final ValueChanged<CustomerModel>? onSelected;\n  final bool startWithAdd;',1)
s=s.replace('const CustomerAttachSheet({super.key, required this.ref});','const CustomerAttachSheet({super.key, required this.ref, this.onSelected, this.startWithAdd = false});')
s=s.replace('  // Add form controllers','  @override\n  void initState() {\n    super.initState();\n    _showAddForm = widget.startWithAdd;\n  }\n\n  void _select(CustomerModel customer) {\n    if (widget.onSelected != null) {\n      widget.onSelected!(customer);\n    } else {\n      ref.read(cartProvider.notifier).attachCustomer(customer);\n    }\n    Navigator.pop(context);\n  }\n\n  // Add form controllers',1)
s=s.replace('if (ref.read(cartProvider).customer != null)', 'if (widget.onSelected == null && ref.read(cartProvider).customer != null)')
s=s.replace('                  ref.read(cartProvider.notifier).attachCustomer(customer);\n                  Navigator.pop(context);', '                  _select(customer);')
s=s.replace('    ref.read(cartProvider.notifier).attachCustomer(customer);\n    Navigator.pop(context);', '    _select(customer);')
s=s.replace('final ValueChanged<dynamic> onSelected;', 'final ValueChanged<CustomerModel> onSelected;')
write(p,s)
p='lib/features/repairs/presentation/screens/repair_form_screen.dart'; s=read(p)
s="import 'package:mobileshop_saas/features/pos/data/models/customer_model.dart';\nimport 'package:mobileshop_saas/features/pos/presentation/widgets/customer_attach_sheet.dart';\n"+s
s=s.replace('  // Customer fields','  CustomerModel? _selectedCustomer;\n\n  void _chooseCustomer({bool create = false}) {\n    showModalBottomSheet<void>(context: context, isScrollControlled: true,\n      builder: (_) => SingleChildScrollView(child: CustomerAttachSheet(ref: ref,\n        startWithAdd: create, onSelected: (customer) {\n          setState(() {\n            _selectedCustomer = customer;\n            _customerNameController.text = customer.fullName;\n            _customerPhoneController.text = customer.phone ?? \'\';\n          });\n        },\n      )));\n  }\n\n  // Customer fields',1)
s=s.replace('                      children: [\n                        _AppTextField(','''                      children: [
                        Wrap(spacing: 8, children: [
                          OutlinedButton(onPressed: isSaving ? null : () => _chooseCustomer(), child: const Text('Select Existing Customer')),
                          OutlinedButton(onPressed: isSaving ? null : () => _chooseCustomer(create: true), child: const Text('Add New Customer')),
                          TextButton(onPressed: isSaving ? null : () => setState(() => _selectedCustomer = null), child: const Text('Manual / Guest')),
                        ]),
                        if (_selectedCustomer != null) Text('Linked customer: ${_selectedCustomer!.fullName}'),
                        _AppTextField(''',1)
s=s.replace('      customerName: _customerNameController.text,', '      customerId: _selectedCustomer?.id,\n      customerName: _customerNameController.text,',1)
write(p,s)
