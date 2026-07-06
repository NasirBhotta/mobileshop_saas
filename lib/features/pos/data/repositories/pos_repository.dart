import 'package:flutter/foundation.dart';
import 'package:mobileshop_saas/core/utils/network.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/cart_item_model.dart';
import '../models/customer_model.dart';
import '../models/held_cart_model.dart';
import '../models/sale_model.dart';
import '../models/sale_payment_model.dart';

class PosRepository {
  final SupabaseClient _client = Supabase.instance.client;

  // ── Context helpers (inventory se same pattern) ──
  Future<String> _currentTenantId() async {
    final user = _client.auth.currentUser;
    if (user == null) throw Exception('User not logged in');

    final profile =
        await _client
            .from('users')
            .select('tenant_id')
            .eq('id', user.id)
            .single();

    return profile['tenant_id'] as String;
  }

  Future<String> _currentBranchId(String tenantId) async {
    final user = _client.auth.currentUser!;

    final profile =
        await _client
            .from('users')
            .select('branch_id')
            .eq('id', user.id)
            .single();

    // Branch selected hai?
    final branchId = profile['branch_id'] as String?;
    if (branchId != null) return branchId;

    // Nahi → pehli branch lo
    final branch =
        await _client
            .from('branches')
            .select('id')
            .eq('tenant_id', tenantId)
            .order('created_at')
            .limit(1)
            .single();

    return branch['id'] as String;
  }

  // ════════════════════════════════════════
  // CHECKOUT
  // ════════════════════════════════════════
  Future<SaleModel> checkout({
    required List<CartItemModel> items,
    required List<SalePaymentModel> payments,
    String? customerId,
    String? customerName,
    String? notes,
  }) async {
    final tenantId = await _currentTenantId();
    final branchId = await _currentBranchId(tenantId);
    final user = _client.auth.currentUser!;

    // ── Step 1: Stock check ──
    // Har item ke liye check karo
    for (final item in items) {
      final inv =
          await _client
              .from('inventory')
              .select('quantity')
              .eq('branch_id', branchId)
              .eq('product_id', item.productId)
              .maybeSingle();

      final currentStock = (inv?['quantity'] as num?)?.toInt() ?? 0;

      if (currentStock < item.quantity) {
        throw Exception(
          '${item.productName} ka stock kam hai. '
          'Available: $currentStock, Required: ${item.quantity}',
        );
      }
    }

    // ── Step 2: Totals calculate karo ──
    final subtotal = items.fold<double>(
      0,
      (sum, item) => sum + (item.unitPrice * item.quantity),
    );

    final discountAmount = items.fold<double>(
      0,
      (sum, item) => sum + (item.discountAmount * item.quantity),
    );

    final taxAmount = items.fold<double>(
      0,
      (sum, item) => sum + item.taxAmount,
    );

    final total = subtotal - discountAmount + taxAmount;

    // ── Step 3: Payment validation ──
    final totalPaid = payments.fold<double>(0, (sum, p) => sum + p.amount);

    // Total paid = total hona chahiye (exactly)
    if ((totalPaid - total).abs() > 0.01) {
      throw Exception(
        'Payment total match nahi karta. '
        'Required: ₨${total.toStringAsFixed(0)}, '
        'Entered: ₨${totalPaid.toStringAsFixed(0)}',
      );
    }

    // ── Step 4: Sale insert karo ──
    final saleData =
        await _client
            .from('sales')
            .insert({
              'branch_id': branchId,
              'customer_id': customerId,
              'user_id': user.id,
              'status': SaleStatus.completed.code,
              'subtotal': subtotal,
              'discount_amount': discountAmount,
              'tax_amount': taxAmount,
              'total': total,
              'notes': notes,
            })
            .select()
            .single();

    final saleId = saleData['id'] as String;

    // ── Step 5: Sale items insert ──
    await _client
        .from('sale_items')
        .insert(
          items
              .map(
                (item) => {
                  'sale_id': saleId,
                  'product_id': item.productId,
                  'product_name': item.productName,
                  'product_sku': item.productSku,
                  'quantity': item.quantity,
                  'unit_price': item.unitPrice,
                  'discount_amount': item.discountAmount,
                  'tax_rate': item.taxRate,
                  'line_total': item.lineTotal,
                },
              )
              .toList(),
        );

    // ── Step 6: Payments insert ──
    await _client
        .from('sale_payments')
        .insert(
          payments
              .map(
                (p) => {
                  'sale_id': saleId,
                  'method': p.method.code,
                  'amount': p.amount,
                },
              )
              .toList(),
        );

    // ── Step 7: Stock update (inventory ghatao) ──
    for (final item in items) {
      // Current stock fetch
      final inv =
          await _client
              .from('inventory')
              .select('quantity')
              .eq('branch_id', branchId)
              .eq('product_id', item.productId)
              .single();

      final currentStock = (inv['quantity'] as num).toInt();
      final newStock = currentStock - item.quantity;

      await _client
          .from('inventory')
          .update({
            'quantity': newStock,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('branch_id', branchId)
          .eq('product_id', item.productId);
    }

    debugPrint('✅ Sale complete: $saleId, Total: ₨$total');

    // ── Step 8: Complete sale return karo ──
    return SaleModel(
      id: saleId,
      branchId: branchId,
      customerId: customerId,
      customerName: customerName,
      userId: user.id,
      status: SaleStatus.completed,
      subtotal: subtotal,
      discountAmount: discountAmount,
      taxAmount: taxAmount,
      total: total,
      notes: notes,
      items: items,
      payments: payments,
      createdAt: DateTime.now(),
    );
  }

  // ════════════════════════════════════════
  // HOLD CART
  // ════════════════════════════════════════
  Future<HeldCartModel> holdCart({
    required List<CartItemModel> items,
    String? label,
    String? customerId,
    String? customerName,
  }) async {
    final tenantId = await _currentTenantId();
    final branchId = await _currentBranchId(tenantId);
    final user = _client.auth.currentUser!;

    // Cart data JSON mein save karo
    final cartData = {
      'items': items.map((e) => e.toMap()).toList(),
      'customer_id': customerId,
      'customer_name': customerName,
    };

    // 24 ghante baad expire
    final expiresAt = DateTime.now().add(const Duration(hours: 24));

    final data =
        await _client
            .from('held_carts')
            .insert({
              'branch_id': branchId,
              'user_id': user.id,
              'label': label ?? 'Cart ${DateTime.now().millisecondsSinceEpoch}',
              'cart_data': cartData,
              'expires_at': expiresAt.toIso8601String(),
            })
            .select()
            .single();

    debugPrint('✅ Cart held: ${data['id']}');

    return HeldCartModel(
      id: data['id'] as String,
      branchId: branchId,
      userId: user.id,
      label: label,
      items: items,
      customerId: customerId,
      customerName: customerName,
      createdAt: DateTime.now(),
      expiresAt: expiresAt,
    );
  }

  // ════════════════════════════════════════
  // FETCH HELD CARTS
  // ════════════════════════════════════════
  Future<List<HeldCartModel>> fetchHeldCarts() async {
    final tenantId = await _currentTenantId();
    final branchId = await _currentBranchId(tenantId);

    final data = await _client
        .from('held_carts')
        .select()
        .eq('branch_id', branchId)
        .order('created_at', ascending: false);

    return (data as List)
        .map((e) => HeldCartModel.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  // ════════════════════════════════════════
  // DELETE HELD CART (resume ke baad)
  // ════════════════════════════════════════
  Future<void> deleteHeldCart(String heldCartId) async {
    await _client.from('held_carts').delete().eq('id', heldCartId);
  }

  // ════════════════════════════════════════
  // VOID CART
  // ════════════════════════════════════════
  Future<void> voidCart({
    required List<CartItemModel> items,
    String? reason,
  }) async {
    final tenantId = await _currentTenantId();
    final branchId = await _currentBranchId(tenantId);
    final user = _client.auth.currentUser!;

    // Void log banao (permanently logged — FR-2.1.4)
    await _client.from('void_logs').insert({
      'branch_id': branchId,
      'user_id': user.id,
      'cart_data': {'items': items.map((e) => e.toMap()).toList()},
      'reason': reason,
    });

    debugPrint('✅ Cart voided, reason: $reason');
    // Note: Stock reserve nahi tha → koi stock change nahi
  }

  // ════════════════════════════════════════
  // CUSTOMERS
  // ════════════════════════════════════════

  // Search customers
  Future<List<CustomerModel>> searchCustomers(String query) async {
    final tenantId = await _currentTenantId();
    final branchId = await _currentBranchId(tenantId);

    final data = await _client
        .from('customers')
        .select()
        .eq('branch_id', branchId)
        .or('full_name.ilike.%$query%,phone.ilike.%$query%')
        .limit(10);

    return (data as List)
        .map((e) => CustomerModel.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  // Quick add customer
  Future<CustomerModel> addCustomer({
    required String fullName,
    String? phone,
    String? email,
  }) async {
    final tenantId = await _currentTenantId();
    final branchId = await _currentBranchId(tenantId);

    final data =
        await _client
            .from('customers')
            .insert({
              'tenant_id': tenantId,
              'branch_id': branchId,
              'full_name': fullName,
              'phone': phone,
              'email': email,
            })
            .select()
            .single();

    return CustomerModel.fromMap(data);
  }

  // ════════════════════════════════════════
  // SALES HISTORY
  // ════════════════════════════════════════
  Future<List<SaleModel>> fetchSales({
    int limit = 50,
    SaleStatus? status,
  }) async {
    final tenantId = await _currentTenantId();
    final branchId = await _currentBranchId(tenantId);

    var query = _client
        .from('sales')
        .select('''
      *,
      customers(full_name),
      sale_items(*),
      sale_payments(*)
    ''')
        .eq('branch_id', branchId);

    if (status != null) {
      query = query.eq('status', status.code);
    }

    query
        .order('created_at', ascending: false)
        .limit(limit)
        .timeout(Network.networkTimeout);

    final data = await query;
    return (data as List)
        .map((e) => SaleModel.fromMap(e as Map<String, dynamic>))
        .toList();
  }
}
