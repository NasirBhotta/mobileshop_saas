import 'dart:async';
import 'package:mobileshop_saas/core/authorization/permission_evaluator.dart';
import 'package:mobileshop_saas/core/local/local_database.dart';
import 'package:flutter/foundation.dart';
import 'package:mobileshop_saas/core/local/local_store.dart';
import 'package:mobileshop_saas/core/offline/offline_store.dart';
import 'package:mobileshop_saas/core/utils/network.dart';
import 'package:mobileshop_saas/core/utils/offline_error_classifier.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../inventory/data/models/product_model.dart';
import '../models/cart_item_model.dart';
import '../models/customer_dashboard_model.dart';
import '../models/customer_model.dart';
import '../models/discount_approval_model.dart';
import '../models/held_cart_model.dart';
import '../models/sale_model.dart';
import '../models/sale_payment_model.dart';
import '../models/sale_return_model.dart';
import '../local/pos_local_ledger_committer.dart';
import '../local/pos_local_refund_committer.dart';
import '../local/pos_local_settlement_committer.dart';
import '../../domain/pos_payment_account_policy.dart';
import '../../domain/pos_refund_allocation.dart';
import '../../../accounts/data/local/accounts_local_store.dart';
import 'sale_return_parent_recovery.dart';
import 'package:mobileshop_saas/core/entitlements/entitlement_evaluator.dart';
import 'package:mobileshop_saas/core/entitlements/supabase_entitlement_data_source.dart';
import 'package:mobileshop_saas/features/pos/domain/pos_entitlement_gate.dart';

class PosRepository {
  static const _offlineWriteTimeout = Duration(milliseconds: 1200);
  // Checkout performs several transactional writes, so the general fast
  // offline fallback is not a realistic deadline for this RPC.
  static const _saleCommitTimeout = Duration(seconds: 8);
  final SupabaseClient _client;
  final PermissionEvaluator _permissions;
  final EntitlementEvaluator _entitlements;
  late final PosEntitlementGate _entitlementGate = PosEntitlementGate(
    _entitlements,
  );
  Future<void>? _offlineSyncInFlight;

  PosRepository({
    SupabaseClient? client,
    required PermissionEvaluator permissions,
    EntitlementEvaluator? entitlementEvaluator,
  }) : _client = client ?? Supabase.instance.client,
       _permissions = permissions,
       _entitlements =
           entitlementEvaluator ??
           EntitlementEvaluator(
             dataSource: SupabaseEntitlementDataSource(client: client),
           );

  Future<void> _requireFeature(String key) => _entitlementGate.require(key);

  Map<String, dynamic> _saleSyncPayload(SaleModel sale) => {
    'id': sale.id,
    'branch_id': sale.branchId,
    'customer_id': sale.customerId,
    'user_id': sale.userId,
    'status': sale.status.code,
    'subtotal': sale.subtotal,
    'discount_amount': sale.discountAmount,
    'tax_amount': sale.taxAmount,
    'total': sale.total,
    'notes': sale.notes,
    'created_at': sale.createdAt?.toIso8601String(),
    'sale_items': sale.items.map((item) => item.toMap()).toList(),
    'sale_payments': sale.payments.map((payment) => payment.toMap()).toList(),
  };

  Future<bool> _commitSaleRemote(Map<String, dynamic> saleData) async {
    final result = await _client
        .rpc('commit_pos_sale_v2', params: {'p_sale': saleData})
        .timeout(_saleCommitTimeout);
    return result == true;
  }

  User get _currentUser {
    final user = _client.auth.currentUser;
    if (user == null) throw Exception('User not logged in');
    return user;
  }

  Future<Map<String, dynamic>> _currentProfile() async {
    final cachedProfile = await OfflineStore.loadProfile(_currentUser.id);
    if (cachedProfile != null) {
      unawaited(_refreshProfileCache());
      return cachedProfile;
    }

    Map<String, dynamic>? profile;
    try {
      profile = await _remoteProfile().timeout(
        const Duration(milliseconds: 1200),
      );
      if (profile != null) {
        final selectedBranchId = await OfflineStore.loadSelectedBranchId(
          _currentUser.id,
        );
        if (selectedBranchId != null) {
          profile['branch_id'] = selectedBranchId;
        }
        await OfflineStore.saveProfile(_currentUser.id, profile);
      }
    } catch (_) {
      profile = await OfflineStore.loadProfile(_currentUser.id);
    }

    if (profile == null) throw Exception('User profile not found');
    return profile;
  }

  Future<Map<String, dynamic>?> _remoteProfile() {
    return _client
        .from('users')
        .select('id, tenant_id, branch_id, full_name, email, phone, role')
        .eq('id', _currentUser.id)
        .maybeSingle();
  }

  Future<void> _refreshProfileCache() async {
    try {
      final profile = await _remoteProfile().timeout(
        const Duration(milliseconds: 1200),
      );
      if (profile != null) {
        final selectedBranchId = await OfflineStore.loadSelectedBranchId(
          _currentUser.id,
        );
        if (selectedBranchId != null) {
          profile['branch_id'] = selectedBranchId;
        }
        await OfflineStore.saveProfile(_currentUser.id, profile);
      }
    } catch (_) {}
  }

  Future<String> _currentTenantId() async {
    final profile = await _currentProfile();
    final tenantId = profile['tenant_id'] as String?;
    if (tenantId == null) throw Exception('User tenant not found');
    return tenantId;
  }

  Future<String> _currentBranchId(String tenantId) async {
    final profile = await _currentProfile();
    final selectedBranchId = profile['branch_id'] as String?;
    if (selectedBranchId != null &&
        await _branchBelongsToTenant(
          tenantId: tenantId,
          branchId: selectedBranchId,
        )) {
      return selectedBranchId;
    }

    final cachedBranches = await OfflineStore.loadBranches(tenantId);
    if (cachedBranches.isNotEmpty && cachedBranches.first.id != null) {
      return cachedBranches.first.id!;
    }

    final branch = await _client
        .from('branches')
        .select('id')
        .eq('tenant_id', tenantId)
        .order('id')
        .limit(1)
        .maybeSingle()
        .timeout(const Duration(milliseconds: 1200));

    final branchId = branch?['id'] as String?;
    if (branchId == null) throw Exception('Branch not found');
    return branchId;
  }

  Future<bool> _branchBelongsToTenant({
    required String tenantId,
    required String branchId,
  }) async {
    final cachedBranches = await OfflineStore.loadBranches(tenantId);
    if (cachedBranches.any((branch) => branch.id == branchId)) return true;

    try {
      final branch = await _client
          .from('branches')
          .select('id')
          .eq('id', branchId)
          .eq('tenant_id', tenantId)
          .maybeSingle()
          .timeout(Network.networkTimeout);
      return branch != null;
    } catch (_) {
      return false;
    }
  }

  // ════════════════════════════════════════
  // CHECKOUT
  // ════════════════════════════════════════
  Future<DiscountEvaluation> evaluateDiscount({
    required String scope,
    String? productId,
    required double baseAmount,
    required DiscountType type,
    required double value,
    String? approvalPin,
  }) async {
    await _requireFeature('pos.discounts');
    if (value < 0) {
      return const DiscountEvaluation(
        allowed: false,
        requiresApproval: false,
        discountAmount: 0,
        message: 'Discount negative nahi ho sakta',
      );
    }

    final discountAmount =
        type == DiscountType.percent ? baseAmount * (value / 100) : value;
    if (discountAmount > baseAmount) {
      return const DiscountEvaluation(
        allowed: false,
        requiresApproval: false,
        discountAmount: 0,
        message: 'Discount amount item price se zyada nahi ho sakta',
      );
    }

    final profile = await _currentProfile();
    final role = (profile['role'] as String? ?? 'cashier').toLowerCase();
    final settings = await _posPolicySettings();
    final fixedLimit = _discountFixedLimitForRole(role, settings);
    final percentLimit = _discountPercentLimitForRole(role, settings);
    final withinLimit =
        type == DiscountType.percent
            ? value <= percentLimit
            : discountAmount <= fixedLimit;

    if (withinLimit) {
      return DiscountEvaluation(
        allowed: true,
        requiresApproval: false,
        discountAmount: discountAmount,
      );
    }

    final approverId = await _verifyApprovalPin(approvalPin);
    if (approverId == null) {
      final limitText =
          type == DiscountType.percent
              ? '${percentLimit.toStringAsFixed(0)}%'
              : 'Rs ${fixedLimit.toStringAsFixed(0)}';
      return DiscountEvaluation(
        allowed: false,
        requiresApproval: true,
        discountAmount: discountAmount,
        message:
            'Discount limit $limitText se zyada hai. Manager PIN required.',
      );
    }

    return DiscountEvaluation(
      allowed: true,
      requiresApproval: true,
      discountAmount: discountAmount,
      approvedBy: approverId,
    );
  }

  Future<Map<String, dynamic>> _posPolicySettings() async {
    final tenantId = await _currentTenantId();
    try {
      final settings = await _client
          .from('tenant_settings')
          .select()
          .eq('tenant_id', tenantId)
          .maybeSingle()
          .timeout(Network.networkTimeout);
      final resolved = settings ?? _defaultPosPolicySettings(tenantId);
      await OfflineStore.saveTenantSettings(tenantId, resolved);
      return resolved;
    } catch (_) {
      return await OfflineStore.loadTenantSettings(tenantId) ??
          _defaultPosPolicySettings(tenantId);
    }
  }

  Map<String, dynamic> _defaultPosPolicySettings(String tenantId) => {
    'tenant_id': tenantId,
    'adjustment_qty_threshold': 10,
    'adjustment_value_threshold': 50000.0,
    'return_approval_threshold': 25000.0,
    'return_window_days': 7,
    'cashier_discount_fixed_limit': 500.0,
    'cashier_discount_percent_limit': 10.0,
    'manager_discount_fixed_limit': 5000.0,
    'manager_discount_percent_limit': 25.0,
    'discount_audit_threshold': 1000.0,
    'receipt_footer': 'Thank you for shopping with us.',
    'updated_at': DateTime.now().toIso8601String(),
  };

  double _discountFixedLimitForRole(
    String role,
    Map<String, dynamic> settings,
  ) {
    if (role == 'owner') return double.infinity;
    if (role == 'manager') {
      return (settings['manager_discount_fixed_limit'] as num?)?.toDouble() ??
          5000;
    }
    return (settings['cashier_discount_fixed_limit'] as num?)?.toDouble() ??
        500;
  }

  double _discountPercentLimitForRole(
    String role,
    Map<String, dynamic> settings,
  ) {
    if (role == 'owner') return 100;
    if (role == 'manager') {
      return (settings['manager_discount_percent_limit'] as num?)?.toDouble() ??
          25;
    }
    return (settings['cashier_discount_percent_limit'] as num?)?.toDouble() ??
        10;
  }

  Future<String?> _verifyApprovalPin(String? approvalPin) async {
    final pin = approvalPin?.trim();
    if (pin == null || pin.isEmpty) return null;
    try {
      final tenantId = await _currentTenantId();
      final approver = await _client
          .from('users')
          .select('id, tenant_id')
          .eq('tenant_id', tenantId)
          .eq('approval_pin', pin)
          .maybeSingle()
          .timeout(Network.networkTimeout);
      final approverId = approver?['id'] as String?;
      if (approverId == null) return null;
      final access = await _permissions.canFor(
        userId: approverId,
        tenantId: tenantId,
        permissionKey: 'pos.discount.approve',
      );
      return access.isAllowed ? approverId : null;
    } catch (_) {
      return null;
    }
  }

  Future<SaleModel> checkout({
    required List<CartItemModel> items,
    required List<SalePaymentModel> payments,
    List<DiscountApprovalModel> discountApprovals = const [],
    String? customerId,
    String? customerName,
    CustomerModel? attachedCustomer,
    String? notes,
  }) async {
    await _requireFeature('pos.checkout');
    if (items.any((item) => item.discountAmount > 0)) {
      await _requireFeature('pos.discounts');
    }
    if (payments.any((payment) => payment.method == PaymentMethod.credit)) {
      await _requireFeature('pos.credit_sales');
    }
    await _validatePaymentAccounts(payments);
    final tenantId = await _currentTenantId();
    final branchId = await _currentBranchId(tenantId);
    final user = _currentUser;
    var effectiveCustomerId = customerId;
    var effectiveCustomerName = customerName;
    if (customerId != null) {
      var resolvedCustomer = await _loadCustomerById(customerId);
      final phone = attachedCustomer?.phone;
      if (resolvedCustomer == null &&
          phone != null &&
          phone.trim().isNotEmpty) {
        resolvedCustomer = await _findCustomerByPhone(
          tenantId: tenantId,
          branchId: branchId,
          phone: phone.trim(),
        );
      }
      if (resolvedCustomer != null) {
        effectiveCustomerId = resolvedCustomer.id;
        effectiveCustomerName = resolvedCustomer.fullName;
      }
    }
    final costedItems = await _withUnitCostsAtSale(
      branchId: branchId,
      items: items,
    );

    // ── Step 1: Stock check ──
    try {
      for (final item in costedItems) {
        final inv = await _client
            .from('inventory')
            .select('quantity')
            .eq('branch_id', branchId)
            .eq('product_id', item.productId)
            .maybeSingle()
            .timeout(Network.networkTimeout);

        final currentStock = (inv?['quantity'] as num?)?.toInt() ?? 0;

        if (currentStock < item.quantity) {
          throw Exception(
            '${item.productName} ka stock kam hai. '
            'Available: $currentStock, Required: ${item.quantity}',
          );
        }
      }
    } catch (e) {
      if (e.toString().contains('stock kam hai')) rethrow;

      // Offline fallback: check stock locally from cached products
      final cachedProducts = await OfflineStore.loadProducts(branchId);
      for (final item in costedItems) {
        final cachedProduct = cachedProducts.firstWhere(
          (p) => p.id == item.productId,
          orElse:
              () =>
                  throw Exception(
                    'Product ${item.productName} locally cached nahi mila.',
                  ),
        );
        if (cachedProduct.stock < item.quantity) {
          throw Exception(
            '${item.productName} ka stock kam hai. '
            'Available (Offline cache): ${cachedProduct.stock}, Required: ${item.quantity}',
          );
        }
      }
    }

    // ── Step 2: Totals calculate karo ──
    final subtotal = costedItems.fold<double>(
      0,
      (sum, item) => sum + (item.unitPrice * item.quantity),
    );

    final discountAmount = costedItems.fold<double>(
      0,
      (sum, item) => sum + (item.discountAmount * item.quantity),
    );

    final taxAmount = costedItems.fold<double>(
      0,
      (sum, item) => sum + item.taxAmount,
    );

    final total = subtotal - discountAmount + taxAmount;

    // ── Step 3: Payment validation ──
    final totalPaid = payments.fold<double>(0, (sum, p) => sum + p.amount);

    if ((totalPaid - total).abs() > 0.01) {
      throw Exception(
        'Payment total match nahi karta. '
        'Required: ₨${total.toStringAsFixed(0)}, '
        'Entered: ₨${totalPaid.toStringAsFixed(0)}',
      );
    }

    final creditAmount = payments
        .where((payment) => payment.method == PaymentMethod.credit)
        .fold<double>(0, (sum, payment) => sum + payment.amount);
    if (creditAmount > 0) {
      await _validateCreditCheckout(
        customerId: effectiveCustomerId,
        creditAmount: creditAmount,
      );
    }

    final saleId = const Uuid().v4();
    final identifiedPayments =
        payments
            .map(
              (payment) => payment.copyWith(
                id: payment.id ?? const Uuid().v4(),
                saleId: saleId,
                ledgerTransactionId:
                    PosPaymentAccountPolicy.requiresAccount(payment.method)
                        ? payment.ledgerTransactionId ?? const Uuid().v4()
                        : null,
              ),
            )
            .toList();
    final sale = SaleModel(
      id: saleId,
      branchId: branchId,
      customerId: effectiveCustomerId,
      customerName: effectiveCustomerName,
      userId: user.id,
      status: SaleStatus.completed,
      subtotal: subtotal,
      discountAmount: discountAmount,
      taxAmount: taxAmount,
      total: total,
      notes: notes,
      items: costedItems,
      payments: identifiedPayments,
      createdAt: DateTime.now(),
    );

    var remoteSaleAndStockCommitted = false;
    try {
      await _commitSaleRemote(_saleSyncPayload(sale));
      remoteSaleAndStockCommitted = true;

      // Save locally as already synced (SQLite synced = 1)
      await _saveSaleLocally(sale);
      await LocalStore.markSaleSynced(saleId);
      if (creditAmount > 0 && effectiveCustomerId != null) {
        await _adjustCustomerOutstanding(
          customerId: effectiveCustomerId,
          delta: creditAmount,
          synced: false,
        );
      }

      for (final item in costedItems) {
        await OfflineStore.decrementStock(
          branchId: branchId,
          productId: item.productId,
          quantity: item.quantity,
        );
      }

      debugPrint('✅ Sale complete remotely: $saleId, Total: ₨$total');
    } catch (e) {
      OfflineErrorClassifier.rethrowIfTerminal(e);
      debugPrint('Offline checkout: Saving locally. Error: $e');

      // Save locally (synced = 0 by default in SQLite / LocalStore)
      await _saveSaleLocally(sale);
      if (remoteSaleAndStockCommitted) {
        await LocalStore.markSaleSynced(saleId);
      }
      if (creditAmount > 0 && effectiveCustomerId != null) {
        await _adjustCustomerOutstanding(
          customerId: effectiveCustomerId,
          delta: creditAmount,
          synced: false,
        );
      }

      for (final item in costedItems) {
        await OfflineStore.decrementStock(
          branchId: branchId,
          productId: item.productId,
          quantity: item.quantity,
        );
      }

      // Enqueue mutation for later sync
      if (!remoteSaleAndStockCommitted) {
        await OfflineStore.enqueueMutation(
          userId: user.id,
          type: 'sale_checkout',
          payload: {'sale_id': saleId, 'sale_data': _saleSyncPayload(sale)},
        );
      }
    }

    try {
      await _logDiscountAudits(
        saleId: saleId,
        branchId: branchId,
        discountApprovals: discountApprovals,
      );
    } catch (e) {
      debugPrint('Discount audit save failed after checkout: $e');
    }

    return sale;
  }

  Future<void> _saveSaleLocally(SaleModel sale) async {
    await PosLocalLedgerCommitter.commit(sale);
    await OfflineStore.saveSale(sale);
  }

  Future<void> _validatePaymentAccounts(List<SalePaymentModel> payments) async {
    for (final payment in payments) {
      if (!PosPaymentAccountPolicy.requiresAccount(payment.method)) {
        if (payment.accountId != null) {
          throw Exception('Khata payment cash account se link nahi ho sakti.');
        }
        continue;
      }
      final accountId = payment.accountId;
      if (accountId == null) {
        throw Exception(
          '${payment.method.label} receiving account select karein.',
        );
      }
      final account = await AccountsLocalStore.loadAccountById(accountId);
      if (account == null ||
          !PosPaymentAccountPolicy.isCompatible(payment.method, account)) {
        throw Exception(
          '${payment.method.label} ke liye compatible active account select karein.',
        );
      }
    }
  }

  Future<List<CartItemModel>> _withUnitCostsAtSale({
    required String branchId,
    required List<CartItemModel> items,
  }) async {
    final cachedProducts = await OfflineStore.loadProducts(branchId);
    final costByProductId = {
      for (final product in cachedProducts) product.id: product.costPrice,
    };

    return [
      for (final item in items)
        item.unitCost != null
            ? item
            : item.copyWith(unitCost: costByProductId[item.productId]),
    ];
  }

  Future<void> _validateCreditCheckout({
    required String? customerId,
    required double creditAmount,
  }) async {
    if (customerId == null) {
      throw Exception('Khata sale ke liye customer attach karna zaroori hai.');
    }
    final customer = await _loadCustomerById(customerId);
    if (customer == null) {
      throw Exception('Customer profile nahi mila.');
    }
    final limit = customer.creditLimit;
    if (limit == null) {
      return;
    }
    final projected = customer.outstandingBalance + creditAmount;
    if (projected > limit + 0.01) {
      throw Exception(
        'Khata limit exceed ho rahi hai. Limit: Rs ${limit.toStringAsFixed(0)}, '
        'Current due: Rs ${customer.outstandingBalance.toStringAsFixed(0)}, '
        'New credit: Rs ${creditAmount.toStringAsFixed(0)}',
      );
    }
  }

  Future<CustomerModel?> _loadCustomerById(String customerId) async {
    final tenantId = await _currentTenantId();
    final branchId = await _currentBranchId(tenantId);
    try {
      final data = await _client
          .from('customers')
          .select()
          .eq('id', customerId)
          .eq('branch_id', branchId)
          .maybeSingle()
          .timeout(Network.networkTimeout);
      if (data == null) {
        final local = await OfflineStore.loadCustomerById(customerId);
        return local?.branchId == branchId ? local : null;
      }
      final customer = CustomerModel.fromMap(data);
      await OfflineStore.saveCustomer(customer);
      return customer;
    } catch (_) {
      final local = await OfflineStore.loadCustomerById(customerId);
      return local?.branchId == branchId ? local : null;
    }
  }

  Future<void> _adjustCustomerOutstanding({
    required String customerId,
    required double delta,
    required bool synced,
  }) async {
    await OfflineStore.adjustCustomerOutstanding(
      customerId: customerId,
      delta: delta,
    );
    if (!synced) return;
    try {
      final customer = await OfflineStore.loadCustomerById(customerId);
      if (customer == null) return;
      await _client
          .from('customers')
          .update({'outstanding_balance': customer.outstandingBalance})
          .eq('id', customerId)
          .eq('branch_id', customer.branchId)
          .timeout(Network.networkTimeout);
    } catch (e) {
      if (!_isMissingCustomerCreditSchema(e)) rethrow;
    }
  }

  Future<void> _logDiscountAudits({
    required String saleId,
    required String branchId,
    required List<DiscountApprovalModel> discountApprovals,
  }) async {
    if (discountApprovals.isEmpty) return;
    final settings = await _posPolicySettings();
    final threshold =
        (settings['discount_audit_threshold'] as num?)?.toDouble() ?? 1000;
    final logs =
        discountApprovals
            .where(
              (approval) =>
                  approval.discountAmount >= threshold ||
                  approval.exceededLimit,
            )
            .toList();
    if (logs.isEmpty) return;

    for (final approval in logs) {
      final id = const Uuid().v4();
      final createdAt = DateTime.now().toIso8601String();
      final payload = {
        'id': id,
        'sale_id': saleId,
        'branch_id': branchId,
        'cashier_id': _currentUser.id,
        'approved_by': approval.approvedBy,
        'scope': approval.scope,
        'product_id': approval.productId,
        'discount_type': approval.type.code,
        'requested_value': approval.requestedValue,
        'discount_amount': approval.discountAmount,
        'reason': approval.reason,
        'created_at': createdAt,
      };

      await LocalDatabase.execute(
        '''
        INSERT OR REPLACE INTO discount_audit_logs(
          id, sale_id, branch_id, cashier_id, approved_by, scope, product_id,
          discount_type, requested_value, discount_amount, reason, synced,
          created_at
        ) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?)
        ''',
        [
          id,
          saleId,
          branchId,
          _currentUser.id,
          approval.approvedBy,
          approval.scope,
          approval.productId,
          approval.type.code,
          approval.requestedValue,
          approval.discountAmount,
          approval.reason,
          0,
          createdAt,
        ],
      );

      try {
        await _client
            .from('discount_audit_logs')
            .insert(payload)
            .timeout(Network.networkTimeout);
        await LocalDatabase.execute(
          'UPDATE discount_audit_logs SET synced = 1 WHERE id = ?',
          [id],
        );
      } catch (e) {
        OfflineErrorClassifier.rethrowIfTerminal(e);
        await OfflineStore.enqueueMutation(
          userId: _currentUser.id,
          type: 'discount_audit',
          payload: payload,
        );
      }
    }
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
    final user = _currentUser;

    final cartId = DateTime.now().millisecondsSinceEpoch.toString();
    final cartData = {
      'items': items.map((e) => e.toMap()).toList(),
      'customer_id': customerId,
      'customer_name': customerName,
    };

    final expiresAt = DateTime.now().add(const Duration(hours: 24));
    final heldCart = HeldCartModel(
      id: cartId,
      branchId: branchId,
      userId: user.id,
      label: label ?? 'Cart $cartId',
      items: items,
      customerId: customerId,
      customerName: customerName,
      createdAt: DateTime.now(),
      expiresAt: expiresAt,
    );

    // Save locally immediately
    await OfflineStore.saveHeldCart(heldCart);

    try {
      await _client
          .from('held_carts')
          .insert({
            'id': cartId,
            'branch_id': branchId,
            'user_id': user.id,
            'label': heldCart.label,
            'cart_data': cartData,
            'expires_at': expiresAt.toIso8601String(),
          })
          .timeout(Network.networkTimeout);

      debugPrint('✅ Cart held remotely: $cartId');
    } catch (e) {
      OfflineErrorClassifier.rethrowIfTerminal(e);
      debugPrint(
        'Offline holdCart: saved locally. Queueing mutation. Error: $e',
      );
      await OfflineStore.enqueueMutation(
        userId: user.id,
        type: 'held_cart_save',
        payload: {
          'id': cartId,
          'branch_id': branchId,
          'user_id': user.id,
          'label': heldCart.label,
          'cart_data': cartData,
          'expires_at': expiresAt.toIso8601String(),
        },
      );
    }

    return heldCart;
  }

  // ════════════════════════════════════════
  // FETCH HELD CARTS
  // ════════════════════════════════════════
  Future<List<HeldCartModel>> fetchHeldCarts() async {
    final tenantId = await _currentTenantId();
    final branchId = await _currentBranchId(tenantId);

    try {
      final data = await _client
          .from('held_carts')
          .select()
          .eq('branch_id', branchId)
          .order('created_at', ascending: false)
          .timeout(Network.networkTimeout);

      final carts =
          (data as List)
              .map((e) => HeldCartModel.fromMap(e as Map<String, dynamic>))
              .toList();

      // Write results to cache
      for (final cart in carts) {
        await OfflineStore.saveHeldCart(cart);
      }
      return carts;
    } catch (_) {
      // Fallback
      return await OfflineStore.loadHeldCarts(branchId);
    }
  }

  Future<String?> fetchReceiptFooter() async {
    final settings = await _posPolicySettings();
    return settings['receipt_footer'] as String?;
  }

  Future<void> saveReceiptFooter(String footer) async {
    final tenantId = await _currentTenantId();
    final safeFooter = footer.length > 160 ? footer.substring(0, 160) : footer;
    final settings = {
      ...(await _posPolicySettings()),
      'tenant_id': tenantId,
      'receipt_footer': safeFooter,
      'updated_at': DateTime.now().toIso8601String(),
    };
    await OfflineStore.saveTenantSettings(tenantId, settings);
    try {
      await _client
          .from('tenant_settings')
          .upsert(settings, onConflict: 'tenant_id')
          .timeout(Network.networkTimeout);
    } catch (e) {
      OfflineErrorClassifier.rethrowIfTerminal(e);
      await OfflineStore.enqueueMutation(
        userId: _currentUser.id,
        type: 'tenant_settings',
        payload: {'settings': settings},
      );
    }
  }

  // ════════════════════════════════════════
  // DELETE HELD CART
  // ════════════════════════════════════════
  Future<void> deleteHeldCart(String heldCartId) async {
    final tenantId = await _currentTenantId();
    final branchId = await _currentBranchId(tenantId);
    final user = _currentUser;

    // Delete locally
    await OfflineStore.deleteHeldCart(branchId: branchId, cartId: heldCartId);

    try {
      await _client
          .from('held_carts')
          .delete()
          .eq('id', heldCartId)
          .eq('branch_id', branchId)
          .timeout(Network.networkTimeout);
    } catch (e) {
      OfflineErrorClassifier.rethrowIfTerminal(e);
      debugPrint('Offline deleteHeldCart: Queued delete mutation. Error: $e');
      await OfflineStore.enqueueMutation(
        userId: user.id,
        type: 'held_cart_delete',
        payload: {'id': heldCartId, 'branch_id': branchId},
      );
    }
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
    final user = _currentUser;

    final cartData = {'items': items.map((e) => e.toMap()).toList()};

    try {
      await _client
          .from('void_logs')
          .insert({
            'branch_id': branchId,
            'user_id': user.id,
            'cart_data': cartData,
            'reason': reason,
          })
          .timeout(Network.networkTimeout);

      debugPrint('✅ Cart voided remotely, reason: $reason');
    } catch (e) {
      OfflineErrorClassifier.rethrowIfTerminal(e);
      debugPrint('Offline voidCart: Queued void mutation. Error: $e');
      await OfflineStore.enqueueMutation(
        userId: user.id,
        type: 'void_cart',
        payload: {
          'branch_id': branchId,
          'user_id': user.id,
          'cart_data': cartData,
          'reason': reason,
        },
      );
    }
  }

  // ════════════════════════════════════════
  // CUSTOMERS
  // ════════════════════════════════════════
  Future<SaleModel?> findSaleForReturn(String invoiceId) async {
    await _requireFeature('pos.returns');
    final tenantId = await _currentTenantId();
    final branchId = await _currentBranchId(tenantId);
    final normalized = invoiceId.trim();
    if (normalized.isEmpty) return null;

    try {
      final data = await _client
          .from('sales')
          .select('''
            *,
            customers(full_name),
            sale_items(*),
            sale_payments(*)
          ''')
          .eq('branch_id', branchId)
          .ilike('id', '$normalized%')
          .limit(1)
          .maybeSingle()
          .timeout(Network.networkTimeout);

      if (data != null) {
        final sale = SaleModel.fromMap(data);
        await OfflineStore.saveSale(sale);
        return sale;
      }
    } catch (_) {}

    final sales = await OfflineStore.loadSales(branchId);
    for (final sale in sales) {
      if (sale.id == normalized || (sale.id?.startsWith(normalized) ?? false)) {
        return sale;
      }
    }
    return null;
  }

  Future<Map<String, int>> loadReturnedQuantities(String saleId) async {
    await _requireFeature('pos.returns');
    final tenantId = await _currentTenantId();
    final branchId = await _currentBranchId(tenantId);
    final returned = <String, int>{};
    try {
      final rows = await _client
          .from('sale_return_items')
          .select('product_id, quantity, sale_returns!inner(status)')
          .eq('original_sale_id', saleId)
          .eq('sale_returns.branch_id', branchId)
          .neq('sale_returns.status', 'rejected')
          .timeout(Network.networkTimeout);

      for (final row in rows as List) {
        final map = Map<String, dynamic>.from(row as Map);
        final productId = map['product_id'] as String;
        returned[productId] =
            (returned[productId] ?? 0) + (map['quantity'] as num).toInt();
      }
      return returned;
    } catch (_) {}

    final rows = await LocalDatabase.select(
      '''
      SELECT ri.product_id, SUM(ri.quantity) AS quantity
      FROM sale_return_items ri
      INNER JOIN sale_returns r ON r.id = ri.return_id
      WHERE ri.original_sale_id = ? AND r.branch_id = ? AND r.status != 'rejected'
      GROUP BY ri.product_id
      ''',
      [saleId, branchId],
    );
    for (final row in rows) {
      returned[row['product_id'] as String] =
          (row['quantity'] as num?)?.toInt() ?? 0;
    }
    return returned;
  }

  Future<SaleReturnModel> processReturn({
    required SaleModel sale,
    required Map<String, int> quantitiesByProductId,
    required RefundMethod refundMethod,
    required double refundAmount,
    String? overrideReason,
  }) async {
    await _requireFeature('pos.returns');
    if (sale.id == null) throw Exception('Original invoice ID missing');

    final canOverrideWindow =
        (await _permissions.can('pos.return.override')).isAllowed;
    final canApprove = (await _permissions.can('pos.return.approve')).isAllowed;
    final settings = await _returnSettings();
    final approvalThreshold =
        (settings['return_approval_threshold'] as num?)?.toDouble() ?? 25000;
    final returnWindowDays =
        (settings['return_window_days'] as num?)?.toInt() ?? 7;
    final returnedQuantities = await loadReturnedQuantities(sale.id!);

    final items = <SaleReturnItemModel>[];
    for (final saleItem in sale.items) {
      final requested = quantitiesByProductId[saleItem.productId] ?? 0;
      if (requested <= 0) continue;

      final alreadyReturned = returnedQuantities[saleItem.productId] ?? 0;
      final available = saleItem.quantity - alreadyReturned;
      if (requested > available) {
        throw Exception(
          '${saleItem.productName}: return qty $requested original available qty $available se zyada hai.',
        );
      }
      items.add(
        SaleReturnItemModel.fromSaleItem(item: saleItem, quantity: requested),
      );
    }

    if (items.isEmpty) throw Exception('Return quantity select karein');

    final maxRefundAmount = items.fold<double>(
      0,
      (sum, item) => sum + item.refundAmount,
    );
    final normalizedRefundAmount =
        refundAmount.clamp(0, maxRefundAmount).toDouble();
    final refundItems = _withDistributedRefundAmounts(
      items: items,
      refundAmount: normalizedRefundAmount,
      maxRefundAmount: maxRefundAmount,
    );
    final reasons = <String>[];
    final saleDate = sale.createdAt;
    if (saleDate != null) {
      final lastReturnDate = saleDate.add(Duration(days: returnWindowDays));
      if (DateTime.now().isAfter(lastReturnDate)) {
        if (!canOverrideWindow) {
          throw Exception(
            'Return window $returnWindowDays din ki hai. Owner override required hai.',
          );
        }
        if (overrideReason == null || overrideReason.trim().isEmpty) {
          throw Exception('Owner override reason zaroori hai');
        }
        reasons.add('Owner override: return window exceeded');
      }
    }

    if (normalizedRefundAmount > approvalThreshold && !canApprove) {
      reasons.add('Refund value approval threshold se zyada hai');
    }

    final status =
        reasons.isEmpty || canApprove
            ? SaleReturnStatus.approved
            : SaleReturnStatus.pendingApproval;
    final normalizedOverrideReason =
        overrideReason == null || overrideReason.trim().isEmpty
            ? null
            : overrideReason.trim();
    var saleReturn = SaleReturnModel(
      id: const Uuid().v4(),
      originalSaleId: sale.id!,
      branchId: sale.branchId,
      userId: _currentUser.id,
      status: status,
      refundMethod: refundMethod,
      refundAmount: normalizedRefundAmount,
      approvalRequiredReason: reasons.isEmpty ? null : reasons.join('; '),
      overrideReason: normalizedOverrideReason,
      approvedBy: status == SaleReturnStatus.approved ? _currentUser.id : null,
      createdAt: DateTime.now(),
      items: refundItems,
    );
    if (status == SaleReturnStatus.approved &&
        refundMethod == RefundMethod.cash &&
        normalizedRefundAmount > 0) {
      saleReturn = await _withRefundAllocation(saleReturn);
    }

    await _saveReturnLocally(
      saleReturn,
      synced: false,
      postRefund: status == SaleReturnStatus.approved,
    );
    if (status == SaleReturnStatus.approved) {
      await _restockReturnItems(saleReturn);
    }

    if (await _isSaleSyncPending(sale.id!)) {
      await _queueReturnMutation(saleReturn, type: 'sale_return');
      return saleReturn;
    }

    try {
      await _syncReturnRemote(saleReturn);
      await _markReturnSynced(saleReturn.id);
    } catch (e) {
      OfflineErrorClassifier.rethrowIfTerminal(e);
      debugPrint('Offline return: saved locally. Queueing mutation. Error: $e');
      await _queueReturnMutation(saleReturn, type: 'sale_return');
    }

    return saleReturn;
  }

  List<SaleReturnItemModel> _withDistributedRefundAmounts({
    required List<SaleReturnItemModel> items,
    required double refundAmount,
    required double maxRefundAmount,
  }) {
    if (items.isEmpty || maxRefundAmount <= 0) return items;

    var remainingRefund = refundAmount;
    return [
      for (var i = 0; i < items.length; i++)
        () {
          final item = items[i];
          final itemRefund =
              i == items.length - 1
                  ? remainingRefund
                  : refundAmount * (item.refundAmount / maxRefundAmount);
          remainingRefund -= itemRefund;

          return SaleReturnItemModel(
            productId: item.productId,
            productName: item.productName,
            productSku: item.productSku,
            quantity: item.quantity,
            refundAmount: itemRefund,
            restockProductId: item.restockProductId ?? const Uuid().v4(),
            restockCondition: item.restockCondition,
            resalePrice: item.quantity <= 0 ? null : itemRefund / item.quantity,
          );
        }(),
    ];
  }

  Future<List<SaleReturnModel>> fetchPendingReturns() async {
    await _requireFeature('pos.returns');
    final tenantId = await _currentTenantId();
    final branchId = await _currentBranchId(tenantId);

    try {
      final rows = await _client
          .from('sale_returns')
          .select('*, sale_return_items(*)')
          .eq('branch_id', branchId)
          .eq('status', SaleReturnStatus.pendingApproval.code)
          .order('created_at', ascending: false)
          .timeout(Network.networkTimeout);
      final returns =
          (rows as List).map((row) {
            final map = Map<String, dynamic>.from(row as Map);
            map['items'] = map['sale_return_items'];
            return SaleReturnModel.fromMap(map);
          }).toList();
      for (final saleReturn in returns) {
        await _saveReturnLocally(saleReturn, synced: true);
      }
      return returns;
    } catch (_) {}

    final rows = await LocalDatabase.select(
      '''
      SELECT * FROM sale_returns
      WHERE branch_id = ? AND status = ?
      ORDER BY created_at DESC
      ''',
      [branchId, SaleReturnStatus.pendingApproval.code],
    );
    final returns = <SaleReturnModel>[];
    for (final row in rows) {
      final items = await LocalDatabase.select(
        'SELECT * FROM sale_return_items WHERE return_id = ?',
        [row['id']],
      );
      returns.add(SaleReturnModel.fromMap({...row, 'items': items}));
    }
    return returns;
  }

  Future<List<SaleReturnModel>> fetchApprovedReturns({int limit = 100}) async {
    await _requireFeature('pos.returns');
    final tenantId = await _currentTenantId();
    final branchId = await _currentBranchId(tenantId);

    try {
      final rows = await _client
          .from('sale_returns')
          .select('*, sale_return_items(*)')
          .eq('branch_id', branchId)
          .eq('status', SaleReturnStatus.approved.code)
          .order('created_at', ascending: false)
          .limit(limit)
          .timeout(Network.networkTimeout);
      final returns =
          (rows as List).map((row) {
            final map = Map<String, dynamic>.from(row as Map);
            map['items'] = map['sale_return_items'];
            return SaleReturnModel.fromMap(map);
          }).toList();
      for (final saleReturn in returns) {
        await _saveReturnLocally(saleReturn, synced: true);
      }
      return returns;
    } catch (_) {}

    final rows = await LocalDatabase.select(
      '''
      SELECT * FROM sale_returns
      WHERE branch_id = ? AND status = ?
      ORDER BY created_at DESC
      LIMIT ?
      ''',
      [branchId, SaleReturnStatus.approved.code, limit],
    );
    final returns = <SaleReturnModel>[];
    for (final row in rows) {
      final items = await LocalDatabase.select(
        'SELECT * FROM sale_return_items WHERE return_id = ?',
        [row['id']],
      );
      returns.add(SaleReturnModel.fromMap({...row, 'items': items}));
    }
    return returns;
  }

  Future<SaleReturnModel> approveReturn(SaleReturnModel pendingReturn) async {
    await _requireFeature('pos.returns');
    await _permissions.require(
      'pos.return.approve',
      message: 'Manager ya Owner approval required hai',
    );

    var approved = _returnWithRestockIds(
      pendingReturn.copyWith(
        status: SaleReturnStatus.approved,
        approvedBy: _currentUser.id,
      ),
    );
    if (approved.refundMethod == RefundMethod.cash &&
        approved.refundAmount > 0 &&
        approved.refundLegs.isEmpty) {
      approved = await _withRefundAllocation(approved);
    }
    final wasAlreadyApproved = await _isReturnAlreadyApproved(approved.id);
    await _saveReturnLocally(approved, synced: false, postRefund: true);
    if (!wasAlreadyApproved) {
      await _restockReturnItems(approved);
    }

    try {
      await _syncReturnRemote(approved);
      await _markReturnSynced(approved.id);
    } catch (e) {
      OfflineErrorClassifier.rethrowIfTerminal(e);
      debugPrint('Offline return approval queued. Error: $e');
      await _queueReturnMutation(approved, type: 'sale_return_approval');
    }
    return approved;
  }

  Future<bool> _isSaleSyncPending(String saleId) async {
    final mutations = await OfflineStore.loadMutations(_currentUser.id);
    for (final mutation in mutations) {
      if (mutation.type != 'sale_checkout') continue;
      final payloadSaleId = mutation.payload['sale_id'] as String?;
      final saleData = mutation.payload['sale_data'];
      final nestedSaleId =
          saleData is Map ? Map<String, dynamic>.from(saleData)['id'] : null;
      if (payloadSaleId == saleId || nestedSaleId == saleId) return true;
    }

    final rows = await LocalDatabase.select(
      'SELECT synced FROM sales WHERE id = ? LIMIT 1',
      [saleId],
    );
    if (rows.isEmpty) return false;
    return ((rows.first['synced'] as num?)?.toInt() ?? 1) == 0;
  }

  Future<void> _queueReturnMutation(
    SaleReturnModel saleReturn, {
    required String type,
  }) async {
    final mutations = await OfflineStore.loadMutations(_currentUser.id);
    final alreadyQueued = mutations.any(
      (mutation) =>
          mutation.type == type && mutation.payload['id'] == saleReturn.id,
    );
    if (alreadyQueued) return;

    await OfflineStore.enqueueMutation(
      userId: _currentUser.id,
      type: type,
      payload: saleReturn.toMap(),
    );
  }

  SaleReturnModel _returnWithRestockIds(SaleReturnModel saleReturn) {
    var changed = false;
    final items = [
      for (final item in saleReturn.items)
        if (item.restockProductId == null) ...[
          () {
            changed = true;
            final unitRefund =
                item.quantity == 0 ? 0.0 : item.refundAmount / item.quantity;
            return SaleReturnItemModel(
              productId: item.productId,
              productName: item.productName,
              productSku: item.productSku,
              quantity: item.quantity,
              refundAmount: item.refundAmount,
              restockProductId: const Uuid().v4(),
              restockCondition: item.restockCondition,
              resalePrice: item.resalePrice ?? unitRefund,
            );
          }(),
        ] else
          item,
    ];

    if (!changed) return saleReturn;
    return SaleReturnModel(
      id: saleReturn.id,
      originalSaleId: saleReturn.originalSaleId,
      branchId: saleReturn.branchId,
      userId: saleReturn.userId,
      status: saleReturn.status,
      refundMethod: saleReturn.refundMethod,
      refundAmount: saleReturn.refundAmount,
      approvalRequiredReason: saleReturn.approvalRequiredReason,
      overrideReason: saleReturn.overrideReason,
      approvedBy: saleReturn.approvedBy,
      createdAt: saleReturn.createdAt,
      items: items,
      refundLegs: saleReturn.refundLegs,
    );
  }

  Future<bool> _isReturnAlreadyApproved(String returnId) async {
    final rows = await LocalDatabase.select(
      'SELECT status FROM sale_returns WHERE id = ? LIMIT 1',
      [returnId],
    );
    if (rows.isEmpty) return false;
    return rows.first['status'] == SaleReturnStatus.approved.code;
  }

  Future<Map<String, dynamic>> _returnSettings() async {
    final tenantId = await _currentTenantId();
    try {
      final settings = await _client
          .from('tenant_settings')
          .select()
          .eq('tenant_id', tenantId)
          .maybeSingle()
          .timeout(Network.networkTimeout);
      final resolved = settings ?? _defaultReturnSettings(tenantId);
      await OfflineStore.saveTenantSettings(tenantId, resolved);
      return resolved;
    } catch (_) {
      return await OfflineStore.loadTenantSettings(tenantId) ??
          _defaultReturnSettings(tenantId);
    }
  }

  Map<String, dynamic> _defaultReturnSettings(String tenantId) => {
    'tenant_id': tenantId,
    'adjustment_qty_threshold': 10,
    'adjustment_value_threshold': 50000.0,
    'return_approval_threshold': 25000.0,
    'return_window_days': 7,
    'updated_at': DateTime.now().toIso8601String(),
  };

  Future<void> _saveReturnLocally(
    SaleReturnModel saleReturn, {
    required bool synced,
    bool postRefund = false,
  }) async {
    await LocalDatabase.runInTransaction(() async {
      await _saveReturnLocallyRows(saleReturn, synced: synced);
      if (postRefund) {
        await PosLocalRefundCommitter.commitWithinTransaction(saleReturn);
      }
    });
  }

  Future<void> _saveReturnLocallyRows(
    SaleReturnModel saleReturn, {
    required bool synced,
  }) async {
    await LocalDatabase.execute(
      '''
      INSERT OR REPLACE INTO sale_returns(
        id, original_sale_id, branch_id, user_id, status, refund_method,
        refund_amount, approval_required_reason, override_reason, approved_by,
        synced, created_at
      ) VALUES(?,?,?,?,?,?,?,?,?,?,?,?)
      ''',
      [
        saleReturn.id,
        saleReturn.originalSaleId,
        saleReturn.branchId,
        saleReturn.userId,
        saleReturn.status.code,
        saleReturn.refundMethod.code,
        saleReturn.refundAmount,
        saleReturn.approvalRequiredReason,
        saleReturn.overrideReason,
        saleReturn.approvedBy,
        synced ? 1 : 0,
        saleReturn.createdAt.toIso8601String(),
      ],
    );

    // Keep the local child rows an exact mirror of the remote return. This is
    // required because offline reports aggregate sale_return_items directly.
    await LocalDatabase.execute(
      'DELETE FROM sale_return_items WHERE return_id = ?',
      [saleReturn.id],
    );
    for (final item in saleReturn.items) {
      await LocalDatabase.execute(
        '''
        INSERT OR REPLACE INTO sale_return_items(
          id, return_id, original_sale_id, product_id, product_name,
          product_sku, quantity, refund_amount, restock_product_id,
          restock_condition, resale_price
        ) VALUES(?,?,?,?,?,?,?,?,?,?,?)
        ''',
        [
          '${saleReturn.id}_${item.productId}',
          saleReturn.id,
          saleReturn.originalSaleId,
          item.productId,
          item.productName,
          item.productSku,
          item.quantity,
          item.refundAmount,
          item.restockProductId,
          item.restockCondition,
          item.resalePrice,
        ],
      );
    }
  }

  Future<SaleReturnModel> _withRefundAllocation(
    SaleReturnModel saleReturn,
  ) async {
    final rows = await LocalDatabase.select(
      '''
      SELECT payment.id, payment.account_id, payment.amount,
             COALESCE(SUM(refund.amount), 0) AS already_refunded
      FROM sale_payments payment
      LEFT JOIN sale_return_refund_legs refund
        ON refund.original_payment_id = payment.id
       AND refund.return_id <> ?
      WHERE payment.sale_id = ?
        AND payment.method <> 'credit'
        AND payment.account_id IS NOT NULL
      GROUP BY payment.id, payment.account_id, payment.amount
      ORDER BY payment.id
      ''',
      [saleReturn.id, saleReturn.originalSaleId],
    );
    final allocations = PosRefundAllocator.allocate(
      refundAmount: saleReturn.refundAmount,
      payments: rows.map(
        (row) => RefundablePaymentLeg(
          paymentId: row['id'] as String,
          accountId: row['account_id'] as String,
          paidAmount: (row['amount'] as num).toDouble(),
          alreadyRefunded: (row['already_refunded'] as num).toDouble(),
        ),
      ),
    );
    return saleReturn.copyWith(
      refundLegs:
          allocations
              .map(
                (allocation) => SaleReturnRefundLegModel(
                  id: const Uuid().v4(),
                  originalPaymentId: allocation.paymentId,
                  accountId: allocation.accountId,
                  amount: allocation.amount,
                  ledgerTransactionId: const Uuid().v4(),
                ),
              )
              .toList(),
    );
  }

  Future<List<SaleReturnRefundPreviewModel>> previewReturnRefund({
    required String saleId,
    required double refundAmount,
  }) async {
    if (refundAmount <= 0) return const [];
    final rows = await LocalDatabase.select(
      '''
      SELECT payment.id, payment.method, payment.account_id, payment.amount,
             account.name AS account_name,
             COALESCE(SUM(refund.amount), 0) AS already_refunded
      FROM sale_payments payment
      JOIN accounts account ON account.id = payment.account_id
      LEFT JOIN sale_return_refund_legs refund
        ON refund.original_payment_id = payment.id
      WHERE payment.sale_id = ?
        AND payment.method <> 'credit'
        AND payment.account_id IS NOT NULL
        AND account.is_active = 1
      GROUP BY payment.id, payment.method, payment.account_id, payment.amount,
               account.name
      ORDER BY payment.id
      ''',
      [saleId],
    );
    final rowsByPaymentId = {for (final row in rows) row['id'] as String: row};
    final allocations = PosRefundAllocator.allocate(
      refundAmount: refundAmount,
      payments: rows.map(
        (row) => RefundablePaymentLeg(
          paymentId: row['id'] as String,
          accountId: row['account_id'] as String,
          paidAmount: (row['amount'] as num).toDouble(),
          alreadyRefunded: (row['already_refunded'] as num).toDouble(),
        ),
      ),
    );
    return allocations.map((allocation) {
      final row = rowsByPaymentId[allocation.paymentId]!;
      return SaleReturnRefundPreviewModel(
        accountId: allocation.accountId,
        accountName: row['account_name'] as String,
        paymentMethod: PaymentMethodX.fromCode(row['method'] as String).label,
        amount: allocation.amount,
      );
    }).toList();
  }

  Future<double> previewCreditReturnCapacity(String saleId) async {
    final saleRows = await LocalDatabase.select(
      'SELECT customer_id FROM sales WHERE id = ? LIMIT 1',
      [saleId],
    );
    if (saleRows.isEmpty || saleRows.single['customer_id'] == null) return 0;
    final customerId = saleRows.single['customer_id'] as String;
    final creditRows = await LocalDatabase.select(
      '''
      SELECT COALESCE(SUM(amount), 0) AS issued
      FROM sale_payments
      WHERE sale_id = ? AND method = 'credit'
      ''',
      [saleId],
    );
    final reversedRows = await LocalDatabase.select(
      '''
      SELECT COALESCE(SUM(amount), 0) AS reversed
      FROM sale_return_credit_adjustments
      WHERE original_sale_id = ?
      ''',
      [saleId],
    );
    final customerRows = await LocalDatabase.select(
      'SELECT outstanding_balance FROM customers WHERE id = ? LIMIT 1',
      [customerId],
    );
    if (customerRows.isEmpty) return 0;
    final issued = (creditRows.single['issued'] as num).toDouble();
    final reversed = (reversedRows.single['reversed'] as num).toDouble();
    final outstanding =
        (customerRows.single['outstanding_balance'] as num).toDouble();
    return (issued - reversed).clamp(0, outstanding).toDouble();
  }

  Future<void> _markReturnSynced(String returnId) async {
    await LocalDatabase.execute(
      'UPDATE sale_returns SET synced = 1 WHERE id = ?',
      [returnId],
    );
  }

  Future<void> _restockReturnItems(SaleReturnModel saleReturn) async {
    for (final item in saleReturn.items) {
      final returnedProductId = item.restockProductId ?? const Uuid().v4();
      await _ensureReturnedProductCached(
        branchId: saleReturn.branchId,
        item: item,
        returnedProductId: returnedProductId,
      );
      await OfflineStore.incrementStock(
        branchId: saleReturn.branchId,
        productId: returnedProductId,
        quantity: item.quantity,
      );
    }
  }

  Future<void> _ensureReturnedProductCached({
    required String branchId,
    required SaleReturnItemModel item,
    required String returnedProductId,
  }) async {
    final products = await OfflineStore.loadProducts(branchId);
    if (products.any((product) => product.id == returnedProductId)) return;

    final tenantId = await _currentTenantId();
    final unitRefund =
        item.quantity == 0 ? 0.0 : item.refundAmount / item.quantity;
    await OfflineStore.upsertCachedProduct(
      ProductModel(
        id: returnedProductId,
        tenantId: tenantId,
        branchId: branchId,
        name: 'Returned - ${item.productName}',
        sku: _returnedSku(item, returnedProductId),
        description: 'Returned stock. Original product: ${item.productName}.',
        salePrice: item.resalePrice ?? unitRefund,
        costPrice: unitRefund,
        stock: 0,
      ),
    );
  }

  Future<void> _syncReturnRemote(SaleReturnModel saleReturn) async {
    var remoteAlreadyApproved = false;
    try {
      final existing = await _client
          .from('sale_returns')
          .select('status')
          .eq('id', saleReturn.id)
          .eq('branch_id', saleReturn.branchId)
          .maybeSingle()
          .timeout(Network.networkTimeout);
      remoteAlreadyApproved =
          existing?['status'] == SaleReturnStatus.approved.code;
    } catch (_) {}

    await _client
        .from('sale_returns')
        .upsert({
          'id': saleReturn.id,
          'original_sale_id': saleReturn.originalSaleId,
          'branch_id': saleReturn.branchId,
          'user_id': saleReturn.userId,
          'status': saleReturn.status.code,
          'refund_method': saleReturn.refundMethod.code,
          'refund_amount': saleReturn.refundAmount,
          'approval_required_reason': saleReturn.approvalRequiredReason,
          'override_reason': saleReturn.overrideReason,
          'approved_by': saleReturn.approvedBy,
          'created_at': saleReturn.createdAt.toIso8601String(),
        }, onConflict: 'id')
        .timeout(Network.networkTimeout);

    await _client
        .from('sale_return_items')
        .delete()
        .eq('return_id', saleReturn.id)
        .timeout(Network.networkTimeout);
    await _client
        .from('sale_return_items')
        .insert(
          saleReturn.items
              .map(
                (item) => {
                  'return_id': saleReturn.id,
                  'original_sale_id': saleReturn.originalSaleId,
                  'product_id': item.productId,
                  'product_name': item.productName,
                  'product_sku': item.productSku,
                  'quantity': item.quantity,
                  'refund_amount': item.refundAmount,
                },
              )
              .toList(),
        )
        .timeout(Network.networkTimeout);

    if (saleReturn.status == SaleReturnStatus.approved &&
        !remoteAlreadyApproved) {
      for (final item in saleReturn.items) {
        final returnedProductId = item.restockProductId ?? const Uuid().v4();
        await _syncReturnedProductRemote(
          saleReturn: saleReturn,
          item: item,
          returnedProductId: returnedProductId,
        );
        final inv = await _client
            .from('inventory')
            .select('quantity')
            .eq('branch_id', saleReturn.branchId)
            .eq('product_id', returnedProductId)
            .maybeSingle()
            .timeout(Network.networkTimeout);
        final currentStock = (inv?['quantity'] as num?)?.toInt() ?? 0;
        await _client
            .from('inventory')
            .upsert({
              'branch_id': saleReturn.branchId,
              'product_id': returnedProductId,
              'quantity': currentStock + item.quantity,
              'updated_at': DateTime.now().toIso8601String(),
            }, onConflict: 'branch_id,product_id')
            .timeout(Network.networkTimeout);
      }
    }

    if (saleReturn.status == SaleReturnStatus.approved &&
        saleReturn.refundMethod == RefundMethod.cash &&
        saleReturn.refundAmount > 0) {
      await _client
          .rpc(
            'post_pos_return_refund',
            params: {
              'p_return_id': saleReturn.id,
              'p_refund_legs':
                  saleReturn.refundLegs.map((leg) => leg.toMap()).toList(),
            },
          )
          .timeout(Network.networkTimeout);
    }
    if (saleReturn.status == SaleReturnStatus.approved &&
        saleReturn.refundMethod == RefundMethod.credit &&
        saleReturn.refundAmount > 0) {
      await _client
          .rpc('post_pos_credit_return', params: {'p_return_id': saleReturn.id})
          .timeout(Network.networkTimeout);
    }
  }

  Future<void> _syncReturnedProductRemote({
    required SaleReturnModel saleReturn,
    required SaleReturnItemModel item,
    required String returnedProductId,
  }) async {
    final tenantId = await _currentTenantId();
    final unitRefund =
        item.quantity == 0 ? 0.0 : item.refundAmount / item.quantity;

    await _client
        .from('products')
        .upsert({
          'id': returnedProductId,
          'tenant_id': tenantId,
          'branch_id': saleReturn.branchId,
          'category_id': null,
          'name': 'Returned - ${item.productName}',
          'sku': _returnedSku(item, returnedProductId),
          'description':
              'Returned stock from sale ${saleReturn.originalSaleId}. Original product: ${item.productName}.',
          'sale_price': item.resalePrice ?? unitRefund,
          'cost_price': unitRefund,
          'imei_tracked': false,
          'is_active': true,
          'created_at': saleReturn.createdAt.toIso8601String(),
        }, onConflict: 'id')
        .timeout(Network.networkTimeout);
  }

  String _returnedSku(SaleReturnItemModel item, String returnedProductId) {
    final suffix = returnedProductId.replaceAll('-', '').substring(0, 8);
    final base = item.productSku?.trim();
    if (base == null || base.isEmpty) return 'RTN-$suffix';
    return '$base-RTN-$suffix';
  }

  Future<List<CustomerModel>> searchCustomers(String query) async {
    final tenantId = await _currentTenantId();
    final branchId = await _currentBranchId(tenantId);
    unawaited(syncOfflineMutations());
    final localCustomers = await OfflineStore.searchCustomers(
      branchId: branchId,
      query: query,
    );

    try {
      final data = await _client
          .from('customers')
          .select()
          .eq('branch_id', branchId)
          .or('full_name.ilike.%$query%,phone.ilike.%$query%')
          .limit(10)
          .timeout(Network.networkTimeout);

      final remoteCustomers =
          (data as List)
              .map((e) => CustomerModel.fromMap(e as Map<String, dynamic>))
              .toList();

      // Cache locally
      for (final customer in remoteCustomers) {
        await OfflineStore.saveCustomer(customer);
      }
      return _mergeCustomers(
        remoteCustomers,
        localCustomers,
        query: query,
      ).take(10).toList();
    } catch (_) {
      return localCustomers;
    }
  }

  Future<List<CustomerModel>> fetchCustomers({String query = ''}) async {
    final tenantId = await _currentTenantId();
    final branchId = await _currentBranchId(tenantId);
    unawaited(syncOfflineMutations());
    final localCustomers = await OfflineStore.loadCustomers(
      branchId: branchId,
      query: query,
    );

    try {
      var request = _client
          .from('customers')
          .select()
          .eq('branch_id', branchId);
      if (query.trim().isNotEmpty) {
        request = request.or(
          'full_name.ilike.%$query%,phone.ilike.%$query%,email.ilike.%$query%',
        );
      }
      final data = await request
          .order('full_name')
          .limit(100)
          .timeout(Network.networkTimeout);
      final customers =
          (data as List)
              .map((e) => CustomerModel.fromMap(e as Map<String, dynamic>))
              .toList();
      for (final customer in customers) {
        await OfflineStore.saveCustomer(customer);
      }
      return _mergeCustomers(customers, localCustomers, query: query);
    } catch (_) {
      return localCustomers;
    }
  }

  Future<CustomerModel> addCustomer({
    required String fullName,
    String? phone,
    String? email,
    String? notes,
    double? creditLimit,
  }) async {
    final tenantId = await _currentTenantId();
    final branchId = await _currentBranchId(tenantId);
    final user = _currentUser;
    final normalizedPhone = _normalizeOptionalString(phone);
    final normalizedEmail = _normalizeOptionalString(email);
    final normalizedNotes = _normalizeOptionalString(notes);
    if (normalizedPhone != null && normalizedPhone.isNotEmpty) {
      final existing = await _findCustomerByPhone(
        tenantId: tenantId,
        branchId: branchId,
        phone: normalizedPhone,
      );
      if (existing != null) {
        throw Exception('Phone number pehle se kisi customer ke paas hai.');
      }
    }
    var effectiveCreditLimit = creditLimit;
    if (effectiveCreditLimit != null) {
      final access = await _permissions.can('customer.credit.update');
      if (!access.isAllowed) {
        effectiveCreditLimit = null;
      }
    }

    final customerId = const Uuid().v4();
    final customer = CustomerModel(
      id: customerId,
      tenantId: tenantId,
      branchId: branchId,
      fullName: fullName,
      phone: normalizedPhone,
      email: normalizedEmail,
      notes: normalizedNotes,
      creditLimit: effectiveCreditLimit,
      createdAt: DateTime.now(),
    );

    // Save locally first
    await OfflineStore.saveCustomer(customer);
    await OfflineStore.enqueueMutation(
      userId: user.id,
      type: 'add_customer',
      payload: {
        'id': customerId,
        'tenant_id': tenantId,
        'branch_id': branchId,
        'full_name': fullName,
        'phone': normalizedPhone,
        'email': normalizedEmail,
        'notes': normalizedNotes,
        'credit_limit': effectiveCreditLimit,
        'outstanding_balance': 0,
        'created_at': customer.createdAt?.toIso8601String(),
      },
    );
    unawaited(syncOfflineMutations());
    return customer;
  }

  String? _normalizeOptionalString(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    return trimmed;
  }

  bool _isMissingCustomerCreditSchema(Object error) {
    if (error is! PostgrestException) return false;
    final message = error.message.toLowerCase();
    return error.code == 'PGRST204' &&
        (message.contains('credit_limit') ||
            message.contains('outstanding_balance'));
  }

  bool _isMissingDeferredSchema(Object error) {
    if (error is! PostgrestException) return false;
    final message = error.message.toLowerCase();
    return _isMissingCustomerCreditSchema(error) ||
        (error.code == 'PGRST205' &&
            (message.contains('sale_returns') ||
                message.contains('sale_return_items')));
  }

  List<CustomerModel> _mergeCustomers(
    List<CustomerModel> remoteCustomers,
    List<CustomerModel> localCustomers, {
    String query = '',
  }) {
    final byId = <String, CustomerModel>{};
    for (final customer in localCustomers) {
      final id = customer.id;
      if (id != null) byId[id] = customer;
    }
    for (final customer in remoteCustomers) {
      final id = customer.id;
      if (id != null) byId[id] = customer;
    }

    final normalized = query.trim();
    final merged =
        byId.values
            .where(
              (customer) =>
                  normalized.isEmpty || customer.matchesQuery(normalized),
            )
            .toList()
          ..sort(
            (a, b) =>
                a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase()),
          );
    return merged;
  }

  Future<CustomerModel?> _findCustomerByPhone({
    required String tenantId,
    required String branchId,
    required String phone,
  }) async {
    try {
      final data = await _client
          .from('customers')
          .select()
          .eq('tenant_id', tenantId)
          .eq('branch_id', branchId)
          .eq('phone', phone)
          .maybeSingle()
          .timeout(Network.networkTimeout);
      if (data == null) {
        final local = await OfflineStore.loadCustomerByPhone(
          tenantId: tenantId,
          phone: phone,
        );
        return local?.branchId == branchId ? local : null;
      }
      return CustomerModel.fromMap(data);
    } catch (_) {
      final local = await OfflineStore.loadCustomerByPhone(
        tenantId: tenantId,
        phone: phone,
      );
      return local?.branchId == branchId ? local : null;
    }
  }

  Future<CustomerModel> updateCustomerCreditLimit({
    required String customerId,
    double? creditLimit,
    bool clearCreditLimit = false,
  }) async {
    await _permissions.require(
      'customer.credit.update',
      message: 'Credit limit sirf Owner set kar sakta hai.',
    );
    final user = _currentUser;
    final customer = await _loadCustomerById(customerId);
    if (customer == null) throw Exception('Customer profile nahi mila.');
    final updated = customer.copyWith(
      creditLimit: creditLimit,
      clearCreditLimit: clearCreditLimit,
    );
    await OfflineStore.saveCustomer(updated);

    try {
      await _client
          .from('customers')
          .update({'credit_limit': clearCreditLimit ? null : creditLimit})
          .eq('id', customerId)
          .eq('branch_id', customer.branchId)
          .timeout(Network.networkTimeout);
    } catch (e) {
      OfflineErrorClassifier.rethrowIfTerminal(e);
      await OfflineStore.enqueueMutation(
        userId: user.id,
        type: 'customer_credit_limit',
        payload: {
          'customer_id': customerId,
          'branch_id': customer.branchId,
          'credit_limit': clearCreditLimit ? null : creditLimit,
        },
      );
    }
    return updated;
  }

  Future<CustomerDashboardModel> fetchCustomerDashboard(
    String customerId,
  ) async {
    final customer = await _loadCustomerById(customerId);
    if (customer == null) throw Exception('Customer profile nahi mila.');

    final purchases = await _fetchCustomerSales(customerId);
    final settlements = await _fetchCustomerSettlements(customerId);
    final lifetimeValue = purchases.fold<double>(
      0,
      (sum, sale) => sum + sale.total,
    );
    final effectiveOutstanding = _effectiveOutstanding(
      customer: customer,
      purchases: purchases,
      settlements: settlements,
    );
    if ((effectiveOutstanding - customer.outstandingBalance).abs() > 0.01) {
      await OfflineStore.updateCustomerCredit(
        customerId: customerId,
        creditLimit: customer.creditLimit,
        outstandingBalance: effectiveOutstanding,
      );
    }

    return CustomerDashboardModel(
      customer: customer.copyWith(outstandingBalance: effectiveOutstanding),
      lifetimeValue: lifetimeValue,
      outstandingDues: effectiveOutstanding,
      activeRepairTickets: 0,
      purchases: purchases,
      settlements: settlements,
    );
  }

  double _effectiveOutstanding({
    required CustomerModel customer,
    required List<SaleModel> purchases,
    required List<CustomerSettlementModel> settlements,
  }) {
    final creditSales = purchases.fold<double>(0, (sum, sale) {
      final creditPaid = sale.payments
          .where((payment) => payment.method == PaymentMethod.credit)
          .fold<double>(
            0,
            (paymentSum, payment) => paymentSum + payment.amount,
          );
      return sum + creditPaid;
    });
    final settled = settlements.fold<double>(
      0,
      (sum, settlement) => sum + settlement.amount,
    );
    final computed =
        (creditSales - settled).clamp(0, double.infinity).toDouble();
    if (computed > customer.outstandingBalance) return computed;
    return customer.outstandingBalance;
  }

  Future<List<SaleModel>> _fetchCustomerSales(String customerId) async {
    final tenantId = await _currentTenantId();
    final branchId = await _currentBranchId(tenantId);
    try {
      final data = await _client
          .from('sales')
          .select('*, customers(full_name), sale_items(*), sale_payments(*)')
          .eq('customer_id', customerId)
          .eq('branch_id', branchId)
          .order('created_at', ascending: false)
          .limit(100)
          .timeout(Network.networkTimeout);
      return (data as List)
          .map((e) => SaleModel.fromMap(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      final sales = await OfflineStore.loadSales(branchId);
      return sales.where((sale) => sale.customerId == customerId).toList();
    }
  }

  Future<List<CustomerSettlementModel>> _fetchCustomerSettlements(
    String customerId,
  ) async {
    final tenantId = await _currentTenantId();
    final branchId = await _currentBranchId(tenantId);
    try {
      final data = await _client
          .from('customer_settlements')
          .select()
          .eq('customer_id', customerId)
          .eq('branch_id', branchId)
          .order('created_at', ascending: false)
          .limit(100)
          .timeout(Network.networkTimeout);
      final settlements =
          (data as List)
              .map(
                (e) =>
                    CustomerSettlementModel.fromMap(e as Map<String, dynamic>),
              )
              .toList();
      for (final settlement in settlements) {
        await OfflineStore.saveCustomerSettlement(settlement, synced: true);
      }
      return settlements;
    } catch (_) {
      final settlements = await OfflineStore.loadCustomerSettlements(
        customerId,
      );
      return settlements
          .where((settlement) => settlement.branchId == branchId)
          .toList();
    }
  }

  Future<List<CustomerSettlementModel>> fetchCustomerSettlements({
    int limit = 1000,
  }) async {
    final tenantId = await _currentTenantId();
    final branchId = await _currentBranchId(tenantId);
    try {
      final data = await _client
          .from('customer_settlements')
          .select()
          .eq('branch_id', branchId)
          .order('created_at', ascending: false)
          .limit(limit)
          .timeout(Network.networkTimeout);
      final settlements =
          (data as List)
              .map(
                (e) =>
                    CustomerSettlementModel.fromMap(e as Map<String, dynamic>),
              )
              .toList();
      for (final settlement in settlements) {
        await OfflineStore.saveCustomerSettlement(settlement, synced: true);
      }
      return settlements;
    } catch (_) {
      final customers = await OfflineStore.loadCustomers(branchId: branchId);
      final settlements = <CustomerSettlementModel>[];
      for (final customer in customers) {
        final customerId = customer.id;
        if (customerId == null) continue;
        settlements.addAll(
          await OfflineStore.loadCustomerSettlements(customerId),
        );
      }
      settlements.removeWhere((settlement) => settlement.branchId != branchId);
      settlements.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return settlements.take(limit).toList();
    }
  }

  Future<CustomerSettlementModel> settleCustomerDues({
    required String customerId,
    required double amount,
    required String method,
    required String accountId,
    String? notes,
  }) async {
    await _permissions.require(
      'customer.credit.settle',
      message: 'Customer settlement permission required hai.',
    );
    if (amount <= 0) throw Exception('Settlement amount valid nahi hai.');
    final customer = await _loadCustomerById(customerId);
    if (customer == null) throw Exception('Customer profile nahi mila.');
    final tenantId = await _currentTenantId();
    final branchId = await _currentBranchId(tenantId);
    final purchases =
        (await OfflineStore.loadSales(
          branchId,
        )).where((sale) => sale.customerId == customerId).toList();
    final settlements =
        (await OfflineStore.loadCustomerSettlements(
          customerId,
        )).where((settlement) => settlement.branchId == branchId).toList();
    final outstanding = _effectiveOutstanding(
      customer: customer,
      purchases: purchases,
      settlements: settlements,
    );
    if (amount > outstanding + 0.01) {
      throw Exception('Settlement current dues se zyada nahi ho sakti.');
    }
    final account = await AccountsLocalStore.loadAccountById(accountId);
    final paymentMethod = PaymentMethodX.fromCode(method);
    if (account == null ||
        account.branchId != branchId ||
        !PosPaymentAccountPolicy.isCompatible(paymentMethod, account)) {
      throw Exception(
        'Settlement ke liye compatible receiving account select karein.',
      );
    }

    final settlement = CustomerSettlementModel(
      id: const Uuid().v4(),
      customerId: customerId,
      branchId: branchId,
      userId: _currentUser.id,
      amount: amount,
      method: method,
      accountId: accountId,
      ledgerTransactionId: const Uuid().v4(),
      notes: notes,
      createdAt: DateTime.now(),
    );

    await PosLocalSettlementCommitter.commit(
      settlement,
      authoritativeOutstanding: outstanding,
    );

    final payload = {
      'id': settlement.id,
      'customer_id': customerId,
      'branch_id': branchId,
      'user_id': _currentUser.id,
      'amount': amount,
      'method': method,
      'account_id': settlement.accountId,
      'ledger_transaction_id': settlement.ledgerTransactionId,
      'notes': notes,
      'created_at': settlement.createdAt.toIso8601String(),
    };

    try {
      await _client
          .rpc('commit_customer_settlement', params: {'p_settlement': payload})
          .timeout(_offlineWriteTimeout);
      await LocalStore.markCustomerSettlementSynced(settlement.id);
    } catch (e) {
      OfflineErrorClassifier.rethrowIfTerminal(e);
      await OfflineStore.enqueueMutation(
        userId: _currentUser.id,
        type: 'customer_settlement',
        payload: payload,
      );
    }

    return settlement;
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
    final localSales = await OfflineStore.loadSales(branchId);

    // Trigger offline sync in background
    unawaited(syncOfflineMutations());

    try {
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

      final data = await query
          .order('created_at', ascending: false)
          .limit(limit)
          .timeout(Network.networkTimeout);

      final sales =
          (data as List)
              .map((e) => SaleModel.fromMap(e as Map<String, dynamic>))
              .toList();

      // Cache locally
      for (final sale in sales) {
        await OfflineStore.saveSale(sale);
        await LocalStore.markSaleSynced(sale.id!);
      }
      final mergedById = <String, SaleModel>{
        for (final sale in sales)
          if (sale.id != null) sale.id!: sale,
        for (final sale in localSales)
          if (sale.id != null) sale.id!: sale,
      };
      final merged =
          mergedById.values.where((sale) {
              return status == null || sale.status == status;
            }).toList()
            ..sort((a, b) {
              final aDate =
                  a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
              final bDate =
                  b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
              return bDate.compareTo(aDate);
            });
      return merged.take(limit).toList();
    } catch (_) {
      return localSales
          .where((sale) {
            return status == null || sale.status == status;
          })
          .take(limit)
          .toList();
    }
  }

  // ════════════════════════════════════════
  // OFFLINE SYNC
  // ════════════════════════════════════════
  Future<void> syncOfflineMutations() {
    final activeSync = _offlineSyncInFlight;
    if (activeSync != null) return activeSync;

    final sync = _syncOfflineMutations();
    _offlineSyncInFlight = sync;
    return sync.whenComplete(() {
      if (identical(_offlineSyncInFlight, sync)) {
        _offlineSyncInFlight = null;
      }
    });
  }

  Future<void> _syncOfflineMutations() async {
    try {
      final userId = _currentUser.id;
      final mutations = await OfflineStore.loadMutations(userId);
      if (mutations.isEmpty) return;

      final remaining = <OfflineMutation>[];
      final reconciledCustomerIds = <String, String>{};

      for (final mutation in mutations) {
        try {
          _remapMutationCustomerId(mutation, reconciledCustomerIds);
          switch (mutation.type) {
            case 'sale_checkout':
              final saleData = Map<String, dynamic>.from(
                mutation.payload['sale_data'] as Map,
              );
              final saleId = mutation.payload['sale_id'] as String;
              await _commitSaleRemote(saleData);
              await LocalStore.markSaleSynced(saleId);
              break;

            case 'held_cart_save':
              await _client.from('held_carts').upsert({
                'id': mutation.payload['id'],
                'branch_id': mutation.payload['branch_id'],
                'user_id': mutation.payload['user_id'],
                'label': mutation.payload['label'],
                'cart_data': mutation.payload['cart_data'],
                'expires_at': mutation.payload['expires_at'],
              });
              break;

            case 'held_cart_delete':
              var deleteQuery = _client
                  .from('held_carts')
                  .delete()
                  .eq('id', mutation.payload['id']);
              final branchId = mutation.payload['branch_id'] as String?;
              if (branchId != null) {
                deleteQuery = deleteQuery.eq('branch_id', branchId);
              }
              await deleteQuery;
              break;

            case 'void_cart':
              await _client.from('void_logs').insert({
                'branch_id': mutation.payload['branch_id'],
                'user_id': mutation.payload['user_id'],
                'cart_data': mutation.payload['cart_data'],
                'reason': mutation.payload['reason'],
              });
              break;

            case 'add_customer':
              final payload = Map<String, dynamic>.from(mutation.payload);
              try {
                await _client.from('customers').upsert({
                  'id': payload['id'],
                  'tenant_id': payload['tenant_id'],
                  'branch_id': payload['branch_id'],
                  'full_name': payload['full_name'],
                  'phone': payload['phone'],
                  'email': payload['email'],
                  'notes': payload['notes'],
                  'credit_limit': payload['credit_limit'],
                  'outstanding_balance': payload['outstanding_balance'] ?? 0,
                  'created_at': payload['created_at'],
                }, onConflict: 'id');
              } catch (e) {
                if (_isCustomerPhoneConflict(e)) {
                  final localCustomerId = payload['id'] as String;
                  final remoteCustomerId = await _remoteCustomerIdByPhone(
                    tenantId: payload['tenant_id'] as String,
                    phone: payload['phone'] as String?,
                  );
                  if (remoteCustomerId == null) rethrow;

                  reconciledCustomerIds[localCustomerId] = remoteCustomerId;
                  for (final queuedMutation in mutations) {
                    _remapMutationCustomerId(
                      queuedMutation,
                      reconciledCustomerIds,
                    );
                  }
                  await LocalStore.reassignCustomerId(
                    localCustomerId: localCustomerId,
                    remoteCustomerId: remoteCustomerId,
                  );
                  break;
                }

                if (!_isMissingCustomerCreditSchema(e)) rethrow;
                await _client.from('customers').upsert({
                  'id': payload['id'],
                  'tenant_id': payload['tenant_id'],
                  'branch_id': payload['branch_id'],
                  'full_name': payload['full_name'],
                  'phone': payload['phone'],
                  'email': payload['email'],
                  'notes': payload['notes'],
                  'created_at': payload['created_at'],
                }, onConflict: 'id');
              }
              break;

            case 'customer_credit_limit':
              try {
                final customerId = mutation.payload['customer_id'] as String;
                final branchId =
                    mutation.payload['branch_id'] as String? ??
                    (await OfflineStore.loadCustomerById(customerId))?.branchId;
                if (branchId == null) {
                  remaining.add(mutation);
                  break;
                }
                await _client
                    .from('customers')
                    .update({'credit_limit': mutation.payload['credit_limit']})
                    .eq('id', customerId)
                    .eq('branch_id', branchId);
              } catch (e) {
                if (!_isMissingCustomerCreditSchema(e)) rethrow;
                remaining.add(mutation);
              }
              break;

            case 'customer_settlement':
              await _client.rpc(
                'commit_customer_settlement',
                params: {'p_settlement': mutation.payload},
              );
              await LocalStore.markCustomerSettlementSynced(
                mutation.payload['id'] as String,
              );
              break;

            case 'sale_return':
              final saleReturn = SaleReturnModel.fromMap(mutation.payload);
              if (await _isSaleSyncPending(saleReturn.originalSaleId)) {
                remaining.add(mutation);
                break;
              }
              await _ensureRemoteSaleForReturn(saleReturn.originalSaleId);
              await _syncReturnRemote(saleReturn);
              await _markReturnSynced(saleReturn.id);
              break;

            case 'sale_return_approval':
              final saleReturn = SaleReturnModel.fromMap(mutation.payload);
              if (await _isSaleSyncPending(saleReturn.originalSaleId)) {
                remaining.add(mutation);
                break;
              }
              await _ensureRemoteSaleForReturn(saleReturn.originalSaleId);
              await _syncReturnRemote(saleReturn);
              await _markReturnSynced(saleReturn.id);
              break;

            case 'discount_audit':
              await _client
                  .from('discount_audit_logs')
                  .insert(mutation.payload);
              await LocalDatabase.execute(
                'UPDATE discount_audit_logs SET synced = 1 WHERE id = ?',
                [mutation.payload['id']],
              );
              break;

            default:
              remaining.add(mutation);
          }
        } catch (e) {
          if (_isMissingDeferredSchema(e)) {
            remaining.add(mutation);
            continue;
          }
          debugPrint('Failed to sync mutation: ${mutation.type}, error: $e');
          remaining.add(mutation);
        }
      }

      await OfflineStore.saveMutationSyncResult(
        userId: userId,
        snapshot: mutations,
        remaining: remaining,
      );
    } catch (_) {}
  }

  bool _isCustomerPhoneConflict(Object error) {
    return error is PostgrestException &&
        error.code == '23505' &&
        error.message.contains('idx_customers_tenant_phone_unique');
  }

  Future<String?> _remoteCustomerIdByPhone({
    required String tenantId,
    required String? phone,
  }) async {
    if (phone == null || phone.trim().isEmpty) return null;
    final customer =
        await _client
            .from('customers')
            .select('id')
            .eq('tenant_id', tenantId)
            .eq('phone', phone)
            .maybeSingle();
    return customer?['id'] as String?;
  }

  void _remapMutationCustomerId(
    OfflineMutation mutation,
    Map<String, String> reconciledCustomerIds,
  ) {
    if (reconciledCustomerIds.isEmpty) return;

    final directCustomerId = mutation.payload['customer_id'] as String?;
    final remappedDirectId = reconciledCustomerIds[directCustomerId];
    if (remappedDirectId != null) {
      mutation.payload['customer_id'] = remappedDirectId;
    }

    final rawSaleData = mutation.payload['sale_data'];
    if (rawSaleData is Map) {
      final saleData = Map<String, dynamic>.from(rawSaleData);
      final saleCustomerId = saleData['customer_id'] as String?;
      final remappedSaleId = reconciledCustomerIds[saleCustomerId];
      if (remappedSaleId != null) {
        saleData['customer_id'] = remappedSaleId;
        mutation.payload['sale_data'] = saleData;
      }
    }
  }

  Future<void> _ensureRemoteSaleForReturn(String saleId) async {
    final recovery = SaleReturnParentRecoveryService(
      remoteSaleExists: (id) async {
        final row = await _client
            .from('sales')
            .select('id, sale_items(id), sale_payments(id)')
            .eq('id', id)
            .maybeSingle()
            .timeout(Network.networkTimeout);
        if (row == null) return false;
        final items = row['sale_items'] as List? ?? const [];
        final payments = row['sale_payments'] as List? ?? const [];
        return items.isNotEmpty && payments.isNotEmpty;
      },
      loadLocalSnapshot: _loadLocalSaleSnapshot,
      restoreRemoteSale: _restoreRemoteSaleSnapshot,
    );
    await recovery.ensureRemoteParent(saleId);
  }

  Future<Map<String, dynamic>?> _loadLocalSaleSnapshot(String saleId) async {
    final sales = await LocalDatabase.select(
      'SELECT * FROM sales WHERE id = ? LIMIT 1',
      [saleId],
    );
    if (sales.isEmpty) return null;

    final items = await LocalDatabase.select(
      'SELECT * FROM sale_items WHERE sale_id = ?',
      [saleId],
    );
    final payments = await LocalDatabase.select(
      'SELECT * FROM sale_payments WHERE sale_id = ?',
      [saleId],
    );
    if (items.isEmpty || payments.isEmpty) return null;

    return {
      'sale': Map<String, dynamic>.from(sales.first),
      'items': items.map(Map<String, dynamic>.from).toList(),
      'payments': payments.map(Map<String, dynamic>.from).toList(),
    };
  }

  Future<void> _restoreRemoteSaleSnapshot(Map<String, dynamic> snapshot) async {
    final sale = Map<String, dynamic>.from(snapshot['sale'] as Map);
    final items =
        (snapshot['items'] as List)
            .map((item) => Map<String, dynamic>.from(item as Map))
            .toList();
    final payments =
        (snapshot['payments'] as List)
            .map((payment) => Map<String, dynamic>.from(payment as Map))
            .toList();
    final saleId = sale['id'] as String;

    await _client.from('sales').upsert({
      'id': saleId,
      'branch_id': sale['branch_id'],
      'customer_id': sale['customer_id'],
      'user_id': sale['user_id'],
      'status': sale['status'],
      'subtotal': sale['subtotal'],
      'discount_amount': sale['discount_amount'],
      'tax_amount': sale['tax_amount'],
      'total': sale['total'],
      'notes': sale['notes'],
      'created_at': sale['created_at'],
    }, onConflict: 'id');

    await _client.from('sale_items').delete().eq('sale_id', saleId);
    await _client.from('sale_payments').delete().eq('sale_id', saleId);

    await _client
        .from('sale_items')
        .insert(
          items
              .map(
                (item) => {
                  'sale_id': saleId,
                  'product_id': item['product_id'],
                  'product_name': item['product_name'],
                  'product_sku': item['product_sku'],
                  'quantity': item['quantity'],
                  'unit_price': item['unit_price'],
                  'unit_cost_at_sale': item['unit_cost_at_sale'],
                  'discount_amount': item['discount_amount'],
                  'tax_rate': item['tax_rate'],
                  'cogs_total': item['cogs_total'],
                  'line_total': item['line_total'],
                },
              )
              .toList(),
        );

    await _client
        .from('sale_payments')
        .insert(
          payments
              .map(
                (payment) => {
                  'id': payment['id'],
                  'sale_id': saleId,
                  'method': payment['method'],
                  'amount': payment['amount'],
                  'account_id': payment['account_id'],
                  'ledger_transaction_id': payment['ledger_transaction_id'],
                },
              )
              .toList(),
        );
  }
}
