from pathlib import Path
root=Path(__file__).resolve().parents[1]
def read(p): return (root/p).read_text(encoding='utf-8')
def write(p,s): (root/p).write_text(s,encoding='utf-8')
p='lib/features/pos/data/repositories/pos_repository.dart'; s=read(p)
s="import '../models/customer_activity_model.dart';\nimport '../local/customer_activity_local_store.dart';\n"+s
pos=s.index('  Future<CustomerDashboardModel> fetchCustomerDashboard(')
s=s[:pos]+'''  Future<CustomerActivityPage> fetchCustomerActivity(String customerId, {
    DateTime? from, DateTime? to, int offset = 0, int limit = 25,
  }) async {
    for (final key in ['customer.customer.view','customer.credit.view','pos.sale.view','repair.ticket.view']) {
      await _permissions.require(key);
    }
    final tenantId = await _currentTenantId();
    final branchId = await _currentBranchId(tenantId);
    final resolvedId = await LocalStore.resolveCustomerId(customerId);
    final customer = await _loadCustomerById(resolvedId);
    if (customer == null || customer.tenantId != tenantId) throw StateError('Customer shop mismatch.');
    if (offset < 0 || limit < 1 || limit > 100 || (from != null && to != null && !to.isAfter(from))) {
      throw ArgumentError('Invalid history range.');
    }
    // Local unsynchronized work is shown from local authoritative records;
    // never present a remote aggregate as including those pending operations.
    final pending = await OfflineStore.loadMutations(_currentUser.id);
    final hasPending = pending.any((m) => m.payload['customer_id'] == resolvedId ||
      (m.payload['ticket'] is Map && (m.payload['ticket'] as Map)['customer_id'] == resolvedId) ||
      (m.payload['sale_data'] is Map && (m.payload['sale_data'] as Map)['customer_id'] == resolvedId) ||
      m.type.contains('repair') || m.type == 'customer_settlement');
    if (!hasPending) {
      try {
        final data = await _client.rpc('customer_activity_v1', params: {
          'p_customer_id': resolvedId, 'p_branch_id': branchId,
          'p_from': from?.toUtc().toIso8601String(), 'p_to': to?.toUtc().toIso8601String(),
          'p_offset': offset, 'p_limit': limit,
        }).timeout(Network.networkTimeout);
        return CustomerActivityPage.fromMap(Map<String,dynamic>.from(data as Map));
      } catch (error) {
        OfflineErrorClassifier.rethrowIfTerminal(error);
      }
    }
    return CustomerActivityLocalStore.load(tenantId: tenantId,branchId: branchId,
      customerId: resolvedId,from: from,to: to,offset: offset,limit: limit);
  }

  Future<Map<String,dynamic>> customerActivityDocument({required String customerId,
    required String id, required bool repair}) async {
    await _permissions.require(repair ? 'repair.ticket.view' : 'pos.sale.view');
    final tenantId = await _currentTenantId();
    final branchId = await _currentBranchId(tenantId);
    final resolvedId = await LocalStore.resolveCustomerId(customerId);
    try {
      var query = _client.from(repair ? 'repair_tickets' : 'sales')
        .select(repair ? '*' : '*, sale_items(*), sale_payments(*)')
        .eq('id',id).eq('customer_id',resolvedId).eq('branch_id',branchId);
      if (repair) query = query.eq('tenant_id',tenantId);
      final row = await query.single().timeout(Network.networkTimeout);
      return row;
    } catch (error) {
      OfflineErrorClassifier.rethrowIfTerminal(error);
      final table = repair ? 'repair_tickets' : 'sales';
      final rows = await LocalDatabase.select('SELECT * FROM $table WHERE id=? AND customer_id=? AND branch_id=?', [id,resolvedId,branchId]);
      if (rows.isEmpty) throw StateError('Receipt is not available offline.');
      final row = Map<String,dynamic>.from(rows.single);
      if (repair && row['tenant_id'] != tenantId) throw StateError('Receipt shop mismatch.');
      if (!repair) {
        row['sale_items'] = await LocalDatabase.select('SELECT * FROM sale_items WHERE sale_id=?',[id]);
        row['sale_payments'] = await LocalDatabase.select('SELECT * FROM sale_payments WHERE sale_id=?',[id]);
      }
      return row;
    }
  }

''' + s[pos:]
write(p,s)
p='lib/features/pos/presentation/screens/customers_screen.dart';s=read(p)
s="import '../widgets/customer_activity_panel.dart';\n"+s
anchor='                    const SizedBox(height: 20),\n                    const Text(\n                      AppStrings.customerPurchaseHistory,'
s=s.replace(anchor,'                    CustomerActivityPanel(customer: data.customer),\n'+anchor,1)
write(p,s)
