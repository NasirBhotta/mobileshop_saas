import '../../../../core/local/local_database.dart';
import '../models/customer_activity_model.dart';

/// All totals cover the full cached range, independently of page size.
/// A cached result is explicitly partial: this device may not have all history.
abstract final class CustomerActivityLocalStore {
  static Future<CustomerActivityPage> load({
    required String tenantId,
    required String branchId,
    required String customerId,
    DateTime? from,
    DateTime? to,
    int offset = 0,
    int limit = 25,
  }) async {
    const scope = '''
      WITH sales_scope AS (
        SELECT s.* FROM sales s JOIN customers c ON c.id=s.customer_id
        WHERE c.tenant_id=? AND s.branch_id=? AND s.customer_id=? AND s.status<>'held'
      ), repairs_scope AS (
        SELECT * FROM repair_tickets WHERE tenant_id=? AND branch_id=? AND customer_id=?
      ), activity AS (
        SELECT 'sale' kind,s.id,s.created_at,s.status,s.total amount,
          COALESCE((SELECT SUM(amount) FROM sale_payments p WHERE p.sale_id=s.id AND p.method<>'credit'),0) paid,
          (SELECT GROUP_CONCAT(product_name || ' ×' || quantity || ' @ ' || unit_price, ', ')
            FROM sale_items i WHERE i.sale_id=s.id) description,
          s.id reference, s.status='completed' active, 1 printable FROM sales_scope s
        UNION ALL
        SELECT 'repair',r.id,r.created_at,r.status,COALESCE(r.customer_charge,r.total_cost,0),
          COALESCE((SELECT SUM(amount) FROM repair_payments p WHERE p.ticket_id=r.id),0)
            - COALESCE((SELECT SUM(amount) FROM repair_payment_refunds f WHERE f.ticket_id=r.id),0),
          r.device_brand || ' ' || r.device_model,r.ticket_no,r.status<>'cancelled',r.ticket_no IS NOT NULL
        FROM repairs_scope r
      ), filtered AS (
        SELECT * FROM activity WHERE (? IS NULL OR julianday(created_at)>=julianday(?))
          AND (? IS NULL OR julianday(created_at)<julianday(?))
      )
    ''';
    final args = <Object?>[
      tenantId,
      branchId,
      customerId,
      tenantId,
      branchId,
      customerId,
      from?.toUtc().toIso8601String(),
      from?.toUtc().toIso8601String(),
      to?.toUtc().toIso8601String(),
      to?.toUtc().toIso8601String(),
    ];
    final entries = await LocalDatabase.select(
      '$scope SELECT * FROM filtered ORDER BY created_at DESC,id DESC,kind LIMIT ? OFFSET ?',
      [...args, limit, offset],
    );
    final totals =
        (await LocalDatabase.select('''$scope
      SELECT COUNT(*) count,
        COALESCE(SUM(CASE WHEN kind='sale' AND active THEN 1 ELSE 0 END),0) purchases,
        COALESCE(SUM(CASE WHEN kind='repair' AND active THEN 1 ELSE 0 END),0) repairs,
        COALESCE(SUM(CASE WHEN active THEN 1 ELSE 0 END),0) visits,
        COALESCE(SUM(CASE WHEN kind='sale' AND active THEN amount ELSE 0 END),0) purchase_amount,
        COALESCE(SUM(CASE WHEN kind='repair' AND active THEN amount ELSE 0 END),0) repair_amount,
        (SELECT COALESCE(SUM(MAX(amount-paid,0)),0) FROM activity WHERE kind='repair' AND active) repair_balance
      FROM filtered
    ''', args)).single;
    final payments = await LocalDatabase.select(
      '''$scope,
      payments AS (
        SELECT p.amount,s.created_at FROM sales_scope s JOIN sale_payments p ON p.sale_id=s.id
          WHERE p.method<>'credit' AND s.status='completed'
        UNION ALL SELECT p.amount,p.received_at FROM repairs_scope r JOIN repair_payments p ON p.ticket_id=r.id
        UNION ALL SELECT -f.amount,f.refunded_at FROM repairs_scope r JOIN repair_payment_refunds f ON f.ticket_id=r.id
        UNION ALL SELECT cs.amount,cs.created_at FROM customer_settlements cs
          JOIN customers c ON c.id=cs.customer_id
          WHERE cs.customer_id=? AND cs.branch_id=? AND c.tenant_id=?
      ) SELECT COALESCE(SUM(amount),0) amount FROM payments
        WHERE (? IS NULL OR julianday(created_at)>=julianday(?)) AND (? IS NULL OR julianday(created_at)<julianday(?))
    ''',
      [...args, customerId, branchId, tenantId, ...args.skip(6)],
    );
    totals['payments'] = payments.single['amount'];
    return CustomerActivityPage(entries, totals, cached: true);
  }
}
