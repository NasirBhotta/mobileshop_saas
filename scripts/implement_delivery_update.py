from pathlib import Path

root = Path(__file__).resolve().parents[1]
def read(p): return (root / p).read_text(encoding='utf-8')
def write(p, s): (root / p).write_text(s, encoding='utf-8')

# Keep the existing legacy entry point intact; the new delivery path explicitly
# opts into deferred accounting. Financial inputs must survive cache round trips.
p='lib/features/repairs/data/models/repair_ticket_model.dart'
s=read(p)
fields=[('bool','deliveryAccounting','delivery_accounting','false'),('double?','customerCharge','customer_charge',None),('double','serviceCharge','service_charge','0'),('double','discountAmount','discount_amount','0'),('double','perJobCommission','per_job_commission','0'),('double','otherDirectCost','other_direct_cost','0'),('DateTime?','finalizedAt','finalized_at',None)]
for typ,name,col,default in fields:
    s=s.replace('  final String? archivedBy;', f'  final {typ} {name};\n  final String? archivedBy;')
    s=s.replace('    this.archivedBy,',f'    this.{name}'+(f' = {default}' if default else '')+',\n    this.archivedBy,')
    expr=f"_bool(map['{col}'])" if typ=='bool' else (f"_date(map['{col}'])" if typ=='DateTime?' else f"(map['{col}'] as num?)?.toDouble()"+(' ?? 0' if default else ''))
    s=s.replace("      archivedBy: map['archived_by'] as String?,",f'      {name}: {expr},\n'+"      archivedBy: map['archived_by'] as String?,")
    s=s.replace("      'archived_by': archivedBy,",f"      '{col}': {name}"+('?.toIso8601String()' if typ=='DateTime?' else '')+',\n'+"      'archived_by': archivedBy,")
    s=s.replace('    String? archivedBy,',f'    {typ.rstrip("?")}? {name},\n    String? archivedBy,')
    s=s.replace('      archivedBy: archivedBy ?? this.archivedBy,',f'      {name}: {name} ?? this.{name},\n      archivedBy: archivedBy ?? this.archivedBy,')
write(p,s)
p='lib/core/local/local_database.dart'; s=read(p)
s=s.replace("      column: 'customer_charge',", "      column: 'customer_charge',") # schema already has financial inputs
anchor="    // REPAIR STATUS LOGS"
pos=s.index(anchor); pos=s.rfind('\n',0,pos)
s=s[:pos]+"\n    await _addColumnIfMissing(table: 'repair_tickets', column: 'delivery_accounting', definition: 'INTEGER NOT NULL DEFAULT 0');\n"+s[pos:]
write(p,s)
p='lib/core/local/local_store.dart'; s=read(p)
start=s.index('  static Future<void> saveRepairTicket('); end=s.index('  static Future<List<RepairTicketModel>> loadRepairTickets',start)
body=s[start:end]
body=body.replace('        photo_paths\n','        photo_paths, delivery_accounting, customer_charge, service_charge,\n        discount_amount, per_job_commission, other_direct_cost, finalized_at\n')
body=body.replace('?, ?, ?)\n', '?, ?, ?, ?, ?, ?, ?, ?, ?, ?)\n')
body=body.replace('        jsonEncode(ticket.photoPaths),','        jsonEncode(ticket.photoPaths),\n        ticket.deliveryAccounting ? 1 : 0,\n        ticket.customerCharge, ticket.serviceCharge, ticket.discountAmount,\n        ticket.perJobCommission, ticket.otherDirectCost,\n        ticket.finalizedAt?.toIso8601String(),')
s=s[:start]+body+s[end:]
s=s.replace("      'UPDATE sales SET customer_id = ? WHERE customer_id = ?',", "      'UPDATE sales SET customer_id = ? WHERE customer_id = ?',")
anchor="    await LocalDatabase.execute('DELETE FROM customers WHERE id = ?', [\n      localCustomerId,"
s=s.replace(anchor,"    await LocalDatabase.execute(\n      'UPDATE repair_tickets SET customer_id = ? WHERE customer_id = ?',\n      [remoteCustomerId, localCustomerId],\n    );\n"+anchor)
write(p,s)

# Reuse the transactional stock/supplier/event posting engine for delivery.
p='lib/features/repairs/data/local/repair_financial_local_committer.dart'; s=read(p)
s=s.replace('    double otherDirectCost = 0,\n  }) {','    double otherDirectCost = 0,\n    bool atDelivery = false,\n  }) {',1)
anchor="      if (current['tenant_id'] != ticket.tenantId ||"
pos=s.index(anchor)
end=s.index('      final paidRows',pos)
s=s[:pos]+'''      if (current['tenant_id'] != ticket.tenantId ||
          current['branch_id'] != ticket.branchId) {
        throw StateError('Repair scope mismatch.');
      }
      if (atDelivery) {
        if (current['status'] == 'delivered') return;
        if (current['status'] != 'completed') {
          throw StateError('Only completed tickets may be delivered.');
        }
        final posted = await LocalDatabase.select(
          "SELECT 1 FROM repair_financial_events WHERE ticket_id = ? AND event_type = 'completion' LIMIT 1",
          [ticket.id],
        );
        if (posted.isNotEmpty || current['finalized_at'] != null ||
            current['delivery_accounting'] != 1) {
          await LocalDatabase.execute(
            "UPDATE repair_tickets SET status = 'delivered', delivered_at = ?, updated_at = ? WHERE id = ?",
            [_now(), _now(), ticket.id],
          );
          await _insertStatusLog(id: '$eventId-status', ticket: ticket,
            userId: userId, oldStatus: 'completed', newStatus: 'delivered');
          return;
        }
      } else if (const {'completed', 'delivered', 'cancelled'}.contains(current['status'])) {
        throw StateError('Ticket cannot be completed.');
      }
''' + s[end:]
s=s.replace("UPDATE repair_tickets SET status = 'completed',", "UPDATE repair_tickets SET status = ?,",1)
s=s.replace('          customerCharge,\n          customerCharge,',"          atDelivery ? 'delivered' : 'completed',\n          customerCharge,\n          customerCharge,",1)
s=s.replace('          completed_at = ?, finalized_at = ?, updated_at = ?', '          completed_at = COALESCE(completed_at, ?), finalized_at = ?, updated_at = ?,\n          delivered_at = CASE WHEN ? THEN ? ELSE delivered_at END',1)
s=s.replace('          ticket.id,\n        ],\n      );\n      await _insertStatusLog(', '          atDelivery ? 1 : 0, _now(),\n          ticket.id,\n        ],\n      );\n      await _insertStatusLog(',1)
s=s.replace("        newStatus: 'completed',", "        newStatus: atDelivery ? 'delivered' : 'completed',",1)
s=s.replace("      if (current['status'] == 'completed' ||\n          current['status'] == 'delivered') {", "      if ((current['status'] == 'completed' || current['status'] == 'delivered') &&\n          (current['delivery_accounting'] != 1 || current['finalized_at'] != null ||\n           (await LocalDatabase.select(\n             \"SELECT 1 FROM repair_financial_events WHERE ticket_id = ? AND event_type = 'completion' LIMIT 1\",\n             [ticket.id],\n           )).isNotEmpty)) {")
pos=s.index('  static Future<void> cancel(')
s=s[:pos]+'''  static Future<void> prepare({
    required RepairTicketModel ticket, required String eventId,
    required String userId, required double customerCharge,
    double serviceCharge = 0, double discount = 0,
    double commission = 0, double otherDirectCost = 0,
  }) => LocalDatabase.runInTransaction(() async {
    final rows = await LocalDatabase.select('SELECT * FROM repair_tickets WHERE id = ?', [ticket.id]);
    if (rows.isEmpty || rows.single['tenant_id'] != ticket.tenantId ||
        rows.single['branch_id'] != ticket.branchId) throw StateError('Repair scope mismatch.');
    final row = rows.single;
    if (row['status'] == 'completed' && row['delivery_accounting'] == 1 &&
        row['customer_charge'] == customerCharge && row['service_charge'] == serviceCharge &&
        row['discount_amount'] == discount && row['per_job_commission'] == commission &&
        row['other_direct_cost'] == otherDirectCost) return;
    if (const {'completed','delivered','cancelled'}.contains(row['status'])) {
      throw StateError('Ticket cannot be completed from its current status.');
    }
    for (final value in [customerCharge, serviceCharge, discount, commission, otherDirectCost]) {
      if (!value.isFinite || value < 0) throw StateError('Invalid repair amount.');
    }
    final paid = await LocalDatabase.select('SELECT COALESCE(SUM(amount),0) AS paid FROM repair_payments WHERE ticket_id = ?', [ticket.id]);
    if ((paid.single['paid'] as num) > customerCharge + 0.01) throw StateError('Customer charge cannot be below payments received.');
    await LocalDatabase.execute("""
      UPDATE repair_tickets SET status = 'completed', delivery_accounting = 1,
        customer_charge = ?, total_cost = ?, service_charge = ?, discount_amount = ?,
        per_job_commission = ?, labor_cost = ?, other_direct_cost = ?, completed_at = ?, updated_at = ?
      WHERE id = ?
    """, [customerCharge, customerCharge, serviceCharge, discount, commission, commission,
      otherDirectCost, _now(), _now(), ticket.id]);
    await _insertStatusLog(id: '$eventId-status', ticket: ticket, userId: userId,
      oldStatus: row['status'] as String, newStatus: 'completed');
  });

''' + s[pos:]
write(p,s)
