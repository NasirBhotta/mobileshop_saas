import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:mobileshop_saas/core/extensions/repair_ticket_ext.dart';
import 'package:mobileshop_saas/core/offline/offline_store.dart';
import 'package:mobileshop_saas/core/local/local_database.dart';
import 'package:mobileshop_saas/core/utils/offline_error_classifier.dart';
import 'package:mobileshop_saas/features/repairs/data/models/inventory_unit_model.dart';
import 'package:mobileshop_saas/features/repairs/data/models/repair_status_log_model.dart';
import 'package:mobileshop_saas/features/repairs/data/models/repair_ticket_model.dart';
import 'package:mobileshop_saas/features/repairs/data/models/repair_payment_model.dart';
import 'package:mobileshop_saas/features/repairs/data/local/repair_payment_local_committer.dart';
import 'package:mobileshop_saas/features/repairs/data/local/repair_financial_local_committer.dart';
import 'package:mobileshop_saas/features/repairs/data/models/repair_part_model.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:mobileshop_saas/core/entitlements/entitlement_evaluator.dart';
import 'package:mobileshop_saas/core/entitlements/supabase_entitlement_data_source.dart';
import 'package:mobileshop_saas/features/repairs/domain/repair_entitlement_gate.dart';

class RepairRepository {
  static const _networkTimeout = Duration(milliseconds: 1200);

  final SupabaseClient _client;
  final EntitlementEvaluator _entitlements;
  late final RepairEntitlementGate _gate = RepairEntitlementGate(_entitlements);

  RepairRepository({
    SupabaseClient? client,
    EntitlementEvaluator? entitlementEvaluator,
  }) : _client = client ?? Supabase.instance.client,
       _entitlements =
           entitlementEvaluator ??
           EntitlementEvaluator(
             dataSource: SupabaseEntitlementDataSource(client: client),
           );

  User get _currentUser {
    final user = _client.auth.currentUser;
    if (user == null) throw Exception('User not logged in');
    return user;
  }

  // ════════════════════════════════════════
  // CURRENT USER / TENANT / BRANCH HELPERS
  // ════════════════════════════════════════
  //
  // Repair ticket create karte waqt humein 3 cheezen zaroor chahiye:
  //
  // 1. current user id
  // 2. current tenant id
  // 3. selected/current branch id
  //
  // Yeh helpers InventoryRepository jaisa pattern follow karte hain.

  Future<Map<String, dynamic>> _currentProfile() async {
    // Pehle offline cache se profile lo.
    // Isse app fast bhi rahegi aur weak internet par bhi kaam karegi.
    final cachedProfile = await OfflineStore.loadProfile(_currentUser.id);

    if (cachedProfile != null) {
      // Background mein fresh profile fetch karne ki koshish.
      // User ko wait nahi karwate.
      unawaited(_refreshProfileCache());
      return cachedProfile;
    }

    Map<String, dynamic>? profile;

    try {
      profile = await _remoteProfile().timeout(_networkTimeout);

      if (profile != null) {
        final selectedBranchId = await OfflineStore.loadSelectedBranchId(
          _currentUser.id,
        );

        // Agar user ne locally branch select ki hui hai,
        // to profile ki branch_id ko selected branch se override kar do.
        if (selectedBranchId != null) {
          profile['branch_id'] = selectedBranchId;
        }

        await OfflineStore.saveProfile(_currentUser.id, profile);
      }
    } catch (_) {
      profile = await OfflineStore.loadProfile(_currentUser.id);
    }

    if (profile == null) {
      throw Exception('User profile not found');
    }

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
      final profile = await _remoteProfile().timeout(_networkTimeout);

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

    if (tenantId == null) {
      throw Exception('User tenant not found');
    }

    return tenantId;
  }

  Future<String> _currentBranchId(String tenantId) async {
    final profile = await _currentProfile();

    // Sab se pehle selected/current branch profile se lo.
    final selectedBranchId = profile['branch_id'] as String?;
    if (selectedBranchId != null &&
        await _branchBelongsToTenant(
          tenantId: tenantId,
          branchId: selectedBranchId,
        )) {
      return selectedBranchId;
    }

    // Phir offline branches se fallback.
    final cachedBranches = await OfflineStore.loadBranches(tenantId);
    if (cachedBranches.isNotEmpty && cachedBranches.first.id != null) {
      return cachedBranches.first.id!;
    }

    // Last fallback remote branch.
    final branch = await _client
        .from('branches')
        .select('id')
        .eq('tenant_id', tenantId)
        .order('id')
        .limit(1)
        .maybeSingle()
        .timeout(_networkTimeout);

    final branchId = branch?['id'] as String?;

    if (branchId == null) {
      throw Exception('Branch not found');
    }

    return branchId;
  }

  // ════════════════════════════════════════
  // CREATE REPAIR TICKET
  // ════════════════════════════════════════
  //
  // Yeh FR-3.1.1 + FR-3.1.3 ka main method hai.
  //
  // Ismein:
  // 1. ticket object banta hai
  // 2. initial status log banta hai
  // 3. optional local inventory unit banti hai agar productId + IMEI ho
  // 4. local save hota hai
  // 5. Supabase insert try hota hai
  // 6. fail ho to mutation queue mein save hota hai

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
          .timeout(_networkTimeout);
      return branch != null;
    } catch (_) {
      return false;
    }
  }

  Future<RepairTicketModel> createRepairTicket({
    String? customerId,
    required String customerName,
    String? customerPhone,
    String? productId,
    required String deviceBrand,
    required String deviceModel,
    String? deviceColor,
    String? imei,
    required String faultDescription,
    String? technicianId,
    double? estimatedCost,
    DateTime? estimatedCompletionAt,
    String? estimateNote,
  }) async {
    await _gate.require('repairs.tickets');
    if (imei?.trim().isNotEmpty == true) {
      await _gate.require('repairs.imei_linking');
    }
    final tenantId = await _currentTenantId();
    final branchId = await _currentBranchId(tenantId);
    final userId = _currentUser.id;

    final ticketId = const Uuid().v4();
    final now = DateTime.now();

    final cleanedImei = imei?.trim();
    final hasImei = cleanedImei != null && cleanedImei.isNotEmpty;

    // Local ticket number hum khud generate kar rahe hain.
    // Supabase trigger bhi fallback generate kar sakta hai,
    // lekin offline mode mein user ko ticket number immediately chahiye.
    final ticketNo = _generateTicketNo(ticketId, now);

    // Main repair ticket object.
    //
    // inventoryUnitId intentionally null rakha hai.
    // Kyun?
    //
    // Online Supabase trigger IMEI se inventory unit find/create karega
    // aur ticket ke saath link karega.
    //
    // Offline mein hum local unit separately save karenge.
    final ticket = RepairTicketModel(
      id: ticketId,
      tenantId: tenantId,
      branchId: branchId,
      ticketNo: ticketNo,
      customerId: customerId,
      customerName: customerName.trim(),
      customerPhone:
          customerPhone?.trim().isEmpty == true ? null : customerPhone?.trim(),
      productId: productId,
      inventoryUnitId: null,
      deviceBrand: deviceBrand.trim(),
      deviceModel: deviceModel.trim(),
      deviceColor:
          deviceColor?.trim().isEmpty == true ? null : deviceColor?.trim(),
      imei: hasImei ? cleanedImei : null,
      faultDescription: faultDescription.trim(),
      technicianId: technicianId,
      status: RepairTicketStatus.received,
      estimatedCost: estimatedCost,
      estimatedCompletionAt: estimatedCompletionAt,
      estimateNote:
          estimateNote?.trim().isEmpty == true ? null : estimateNote?.trim(),
      createdBy: userId,
      createdAt: now,
      updatedAt: now,
    );

    // Initial status log.
    //
    // Ticket create hota hai to status:
    // null -> received
    final initialLog = RepairStatusLogModel(
      id: const Uuid().v4(),
      ticketId: ticket.id,
      tenantId: tenantId,
      branchId: branchId,
      oldStatus: null,
      newStatus: RepairTicketStatus.received,
      changedBy: userId,
      note: 'Repair ticket created',
      createdAt: now,
    );

    // Local IMEI unit sirf tab banayenge jab productId + IMEI dono hon.
    //
    // ProductId ke bina inventory unit banana safe nahi,
    // kyunki inventory_units table product_id required rakhti hai.
    final localUnit =
        hasImei && productId != null
            ? await _buildLocalInventoryUnit(
              tenantId: tenantId,
              branchId: branchId,
              productId: productId,
              imei: cleanedImei,
              customerId: customerId,
              ticketId: ticket.id,
              now: now,
            )
            : null;

    // Sab se pehle local save.
    //
    // Iska faida:
    // Internet slow/down bhi ho to user ka ticket lose nahi hota.
    await OfflineStore.saveRepairTicketWithInitialLog(
      ticket: ticket,
      log: initialLog,
      inventoryUnit: localUnit,
    );

    try {
      // Remote insert.
      //
      // Supabase trigger:
      // - ticket_no fallback generate karega agar null ho
      // - IMEI unit find/create karega
      // - inventory unit ko in_repair karega
      // - initial status log create karega
      final data = await _client
          .from('repair_tickets')
          .insert(_remoteTicketMap(ticket))
          .select()
          .single()
          .timeout(_networkTimeout);

      final savedTicket = RepairTicketModel.fromMap(data);

      // Remote result local cache mein update kar do.
      // Agar trigger ne inventory_unit_id set kiya ho to wo bhi save ho jayega.
      await OfflineStore.saveRepairTicket(savedTicket);

      // Agar remote ne inventory_unit_id return kiya hai,
      // to local inventory unit ko remote id ke saath align kar do.
      if (savedTicket.inventoryUnitId != null &&
          savedTicket.productId != null &&
          savedTicket.imei != null &&
          savedTicket.imei!.trim().isNotEmpty) {
        await OfflineStore.upsertInventoryUnit(
          InventoryUnitModel(
            id: savedTicket.inventoryUnitId!,
            tenantId: savedTicket.tenantId,
            branchId: savedTicket.branchId,
            productId: savedTicket.productId!,
            imei: savedTicket.imei!.trim(),
            status: InventoryUnitStatus.inRepair,
            customerId: savedTicket.customerId,
            currentRepairTicketId: savedTicket.id,
            createdAt: now,
            updatedAt: DateTime.now(),
          ),
        );
      }

      return savedTicket;
    } catch (e) {
      OfflineErrorClassifier.rethrowIfTerminal(e);
      // Remote fail hua, lekin local save already ho chuka hai.
      //
      // Ab mutation queue mein daal do taake baad mein sync ho sake.
      await OfflineStore.enqueueMutation(
        userId: userId,
        type: 'upsert_repair_ticket',
        payload: {
          'ticket': ticket.toCacheMap(),
          'initial_log': initialLog.toCacheMap(),
          if (localUnit != null) 'inventory_unit': localUnit.toCacheMap(),
        },
      );

      debugPrint('Repair ticket saved offline: $e');
      return ticket;
    }
  }

  // ════════════════════════════════════════
  // FETCH REPAIR TICKETS
  // ════════════════════════════════════════
  //
  // Same offline-first pattern:
  //
  // 1. local cache available hai to pehle woh return karo
  // 2. background mein remote refresh karo
  // 3. cache empty hai to remote try karo
  // 4. remote fail ho to local fallback

  Future<List<RepairTicketModel>> fetchRepairTickets({
    RepairTicketStatus? status,
  }) async {
    await _gate.require('repairs.tickets');
    final tenantId = await _currentTenantId();
    final branchId = await _currentBranchId(tenantId);

    final cachedTickets = await OfflineStore.loadRepairTickets(
      branchId,
      status: status,
    );

    if (cachedTickets.isNotEmpty) {
      unawaited(syncOfflineMutations());
      unawaited(_refreshRepairTicketsCache(branchId: branchId, status: status));
      return cachedTickets;
    }

    try {
      return await _fetchRemoteRepairTickets(
        tenantId: tenantId,
        branchId: branchId,
        status: status,
      ).timeout(_networkTimeout);
    } catch (_) {
      return OfflineStore.loadRepairTickets(branchId, status: status);
    }
  }

  Future<List<RepairTicketModel>> _fetchRemoteRepairTickets({
    required String tenantId,
    required String branchId,
    RepairTicketStatus? status,
  }) async {
    var query = _client
        .from('repair_tickets')
        .select()
        .eq('tenant_id', tenantId)
        .eq('branch_id', branchId)
        .isFilter('archived_at', null);

    if (status != null) {
      query = query.eq('status', status.code);
    }

    final data = await query.order('created_at', ascending: false).limit(100);

    final tickets =
        (data as List).map((row) => RepairTicketModel.fromMap(row)).toList();

    for (final ticket in tickets) {
      await OfflineStore.saveRepairTicket(ticket);
    }
    await _refreshRepairFinancialEventsCache(
      tenantId: tenantId,
      branchId: branchId,
    );

    return tickets;
  }

  Future<void> _refreshRepairFinancialEventsCache({
    required String tenantId,
    required String branchId,
  }) async {
    try {
      final rows = await _client
          .from('repair_financial_events')
          .select()
          .eq('tenant_id', tenantId)
          .eq('branch_id', branchId)
          .order('occurred_at');
      for (final row in rows as List) {
        final event = Map<String, dynamic>.from(row as Map);
        await LocalDatabase.execute(
          '''
          INSERT INTO repair_financial_events(
            id, tenant_id, branch_id, ticket_id, event_type,
            source_event_key, revenue_amount, inventory_cost,
            direct_parts_cost, commission_cost, other_direct_cost,
            gross_profit, reversal_of_event_id, occurred_at, effective_at,
            created_by, created_at
          ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
          ON CONFLICT(id) DO UPDATE SET
            revenue_amount = excluded.revenue_amount,
            inventory_cost = excluded.inventory_cost,
            direct_parts_cost = excluded.direct_parts_cost,
            commission_cost = excluded.commission_cost,
            other_direct_cost = excluded.other_direct_cost,
            gross_profit = excluded.gross_profit,
            reversal_of_event_id = excluded.reversal_of_event_id,
            occurred_at = excluded.occurred_at,
            effective_at = excluded.effective_at
          ''',
          [
            event['id'],
            event['tenant_id'],
            event['branch_id'],
            event['ticket_id'],
            event['event_type'],
            event['source_event_key'],
            event['revenue_amount'],
            event['inventory_cost'],
            event['direct_parts_cost'],
            event['commission_cost'],
            event['other_direct_cost'],
            event['gross_profit'],
            event['reversal_of_event_id'],
            event['occurred_at'],
            event['effective_at'] ?? event['occurred_at'],
            event['created_by'],
            event['created_at'],
          ],
        );
      }
    } catch (_) {
      // Ticket refresh must still work offline or against an older schema.
    }
  }

  Future<void> _refreshRepairTicketsCache({
    required String branchId,
    RepairTicketStatus? status,
  }) async {
    try {
      final tenantId = await _currentTenantId();

      await _fetchRemoteRepairTickets(
        tenantId: tenantId,
        branchId: branchId,
        status: status,
      ).timeout(_networkTimeout);
    } catch (_) {}
  }

  Future<void> refreshCurrentRepairTicketsCache({
    Duration timeout = _networkTimeout,
  }) async {
    final tenantId = await _currentTenantId();
    final branchId = await _currentBranchId(tenantId);
    await _fetchRemoteRepairTickets(
      tenantId: tenantId,
      branchId: branchId,
    ).timeout(timeout);
  }

  // ════════════════════════════════════════
  // STATUS LOGS
  // ════════════════════════════════════════

  Future<List<RepairStatusLogModel>> fetchStatusLogs(String ticketId) async {
    await _gate.require('repairs.tickets');
    final cachedLogs = await OfflineStore.loadRepairStatusLogs(ticketId);

    if (cachedLogs.isNotEmpty) {
      unawaited(_refreshStatusLogsCache(ticketId));
      return cachedLogs;
    }

    try {
      final data = await _client
          .from('repair_status_logs')
          .select()
          .eq('ticket_id', ticketId)
          .order('created_at', ascending: false)
          .timeout(_networkTimeout);

      final logs =
          (data as List)
              .map((row) => RepairStatusLogModel.fromMap(row))
              .toList();

      for (final log in logs) {
        await OfflineStore.saveRepairStatusLog(log);
      }

      return logs;
    } catch (_) {
      return OfflineStore.loadRepairStatusLogs(ticketId);
    }
  }

  Future<RepairTicketModel> updateRepairTicketStatus({
    required RepairTicketModel ticket,
    required RepairTicketStatus status,
    String? note,
    double? totalCost,
  }) async {
    await _gate.require('repairs.tickets');
    if (status == RepairTicketStatus.completed ||
        status == RepairTicketStatus.cancelled) {
      throw StateError('Use the financial completion/cancellation workflow.');
    }
    if (ticket.status == status) return ticket;

    if (!ticket.status.canMoveTo(status)) {
      throw Exception(
        'Status ${ticket.status.label} se ${status.label} par move nahi ho sakta',
      );
    }

    final now = DateTime.now();
    final userId = _currentUser.id;

    final updatedTicket = ticket.copyWith(
      status: status,
      totalCost: totalCost ?? ticket.totalCost,
      completedAt:
          status == RepairTicketStatus.completed
              ? ticket.completedAt ?? now
              : ticket.completedAt,
      deliveredAt:
          status == RepairTicketStatus.delivered
              ? ticket.deliveredAt ?? now
              : ticket.deliveredAt,
      updatedAt: now,
    );

    final statusLog = RepairStatusLogModel(
      id: const Uuid().v4(),
      ticketId: ticket.id,
      tenantId: ticket.tenantId,
      branchId: ticket.branchId,
      oldStatus: ticket.status,
      newStatus: status,
      changedBy: userId,
      note: note?.trim().isEmpty == true ? null : note?.trim(),
      createdAt: now,
    );

    await OfflineStore.saveRepairTicket(updatedTicket);
    await OfflineStore.saveRepairStatusLog(statusLog);

    try {
      final data = await _client
          .from('repair_tickets')
          .update(_remoteTicketStatusMap(updatedTicket))
          .eq('id', ticket.id)
          .select()
          .single()
          .timeout(_networkTimeout);

      final savedTicket = RepairTicketModel.fromMap(data);
      await OfflineStore.saveRepairTicket(savedTicket);

      await _client
          .from('repair_status_logs')
          .upsert(statusLog.toCacheMap(), onConflict: 'id')
          .timeout(_networkTimeout);

      return savedTicket;
    } catch (e) {
      OfflineErrorClassifier.rethrowIfTerminal(e);
      await OfflineStore.enqueueMutation(
        userId: userId,
        type: 'update_repair_ticket_status',
        payload: {
          'ticket': updatedTicket.toCacheMap(),
          'status_log': statusLog.toCacheMap(),
        },
      );

      debugPrint('Repair status update saved offline: $e');
      return updatedTicket;
    }
  }

  Future<List<RepairPaymentModel>> fetchRepairPayments(String ticketId) async {
    await _gate.require('repairs.tickets');
    try {
      final data = await _client
          .from('repair_payments')
          .select()
          .eq('ticket_id', ticketId)
          .order('received_at')
          .timeout(_networkTimeout);
      final payments =
          (data as List).map((row) => RepairPaymentModel.fromMap(row)).toList();
      for (final payment in payments) {
        await _saveRepairPaymentCache(payment);
      }
      return payments;
    } catch (_) {
      return _loadRepairPayments(ticketId);
    }
  }

  Future<List<RepairPartModel>> fetchRepairParts(String ticketId) async {
    await _gate.require('repairs.tickets');
    try {
      final rows = await _client
          .from('repair_parts')
          .select()
          .eq('ticket_id', ticketId)
          .order('created_at')
          .timeout(_networkTimeout);
      final parts =
          (rows as List).map((row) => RepairPartModel.fromMap(row)).toList();
      await _replaceLocalRepairParts(ticketId, parts);
      return parts;
    } catch (_) {
      return _loadLocalRepairParts(ticketId);
    }
  }

  Future<void> saveRepairParts({
    required RepairTicketModel ticket,
    required List<RepairPartModel> parts,
  }) async {
    await _gate.require('repairs.tickets');
    await _replaceLocalRepairParts(
      ticket.id,
      parts,
      createdByOverride: _currentUser.id,
    );
    try {
      await _client
          .rpc(
            'save_repair_parts_v2',
            params: {
              'p_ticket_id': ticket.id,
              'p_parts': parts.map((part) => part.toRpcMap()).toList(),
            },
          )
          .timeout(_networkTimeout);
    } catch (error) {
      OfflineErrorClassifier.rethrowIfTerminal(error);
      await OfflineStore.enqueueMutation(
        userId: _currentUser.id,
        type: 'save_repair_parts_v2',
        payload: {
          'ticket_id': ticket.id,
          'parts': parts.map((part) => part.toRpcMap()).toList(),
        },
      );
    }
  }

  Future<RepairTicketModel> completeRepair({
    required RepairTicketModel ticket,
    required double customerCharge,
    double serviceCharge = 0,
    double discount = 0,
    double commission = 0,
    double otherDirectCost = 0,
  }) async {
    await _gate.require('repairs.tickets');
    final eventId = const Uuid().v4();
    var localCommitted = false;
    try {
      await _client
          .rpc(
            'complete_repair_ticket_v2',
            params: {
              'p_ticket_id': ticket.id,
              'p_event_id': eventId,
              'p_customer_charge': customerCharge,
              'p_service_charge': serviceCharge,
              'p_discount': discount,
              'p_commission': commission,
              'p_other_direct_cost': otherDirectCost,
            },
          )
          .timeout(_networkTimeout);
    } catch (error) {
      OfflineErrorClassifier.rethrowIfTerminal(error);
      await RepairFinancialLocalCommitter.complete(
        ticket: ticket,
        eventId: eventId,
        userId: _currentUser.id,
        customerCharge: customerCharge,
        serviceCharge: serviceCharge,
        discount: discount,
        commission: commission,
        otherDirectCost: otherDirectCost,
      );
      localCommitted = true;
      await OfflineStore.enqueueMutation(
        userId: _currentUser.id,
        type: 'complete_repair_ticket_v2',
        payload: {
          'ticket_id': ticket.id,
          'event_id': eventId,
          'customer_charge': customerCharge,
          'service_charge': serviceCharge,
          'discount': discount,
          'commission': commission,
          'other_direct_cost': otherDirectCost,
        },
      );
    }
    // Reports and dashboard read the local immutable financial snapshot.
    // Mirror a successful remote commit locally as well; the event key makes
    // this safe if the same completion is replayed.
    if (!localCommitted) {
      await RepairFinancialLocalCommitter.complete(
        ticket: ticket,
        eventId: eventId,
        userId: _currentUser.id,
        customerCharge: customerCharge,
        serviceCharge: serviceCharge,
        discount: discount,
        commission: commission,
        otherDirectCost: otherDirectCost,
      );
    }
    final updated = ticket.copyWith(
      status: RepairTicketStatus.completed,
      totalCost: customerCharge,
      partsCost: await _localPartCost(ticket.id),
      laborCost: commission,
      completedAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    await OfflineStore.saveRepairTicket(updated);
    return updated;
  }

  Future<RepairTicketModel> cancelRepair(
    RepairTicketModel ticket, {
    String? refundAccountId,
  }) async {
    await _gate.require('repairs.tickets');
    final eventId = const Uuid().v4();
    final refundId = const Uuid().v4();
    final refundLedgerTransactionId = const Uuid().v4();
    var localCommitted = false;
    try {
      await _client
          .rpc(
            'cancel_repair_ticket_v3',
            params: {
              'p_ticket_id': ticket.id,
              'p_event_id': eventId,
              'p_refund_id': refundId,
              'p_refund_account_id': refundAccountId,
              'p_refund_ledger_transaction_id': refundLedgerTransactionId,
            },
          )
          .timeout(_networkTimeout);
    } catch (error) {
      OfflineErrorClassifier.rethrowIfTerminal(error);
      await RepairFinancialLocalCommitter.cancel(
        ticket: ticket,
        eventId: eventId,
        userId: _currentUser.id,
        refundId: refundId,
        refundAccountId: refundAccountId,
        refundLedgerTransactionId: refundLedgerTransactionId,
        enforceRefundBalance: true,
      );
      localCommitted = true;
      await OfflineStore.enqueueMutation(
        userId: _currentUser.id,
        type: 'cancel_repair_ticket_v3',
        payload: {
          'ticket_id': ticket.id,
          'event_id': eventId,
          'refund_id': refundId,
          'refund_account_id': refundAccountId,
          'refund_ledger_transaction_id': refundLedgerTransactionId,
        },
      );
    }
    // Keep local inventory, supplier balances, and financial reports aligned
    // after a successful online reversal too.
    if (!localCommitted) {
      await RepairFinancialLocalCommitter.cancel(
        ticket: ticket,
        eventId: eventId,
        userId: _currentUser.id,
        refundId: refundId,
        refundAccountId: refundAccountId,
        refundLedgerTransactionId: refundLedgerTransactionId,
        enforceRefundBalance: false,
      );
    }
    final updated = ticket.copyWith(
      status: RepairTicketStatus.cancelled,
      updatedAt: DateTime.now(),
    );
    await OfflineStore.saveRepairTicket(updated);
    return updated;
  }

  Future<void> archiveRepair(RepairTicketModel ticket) async {
    await _gate.require('repairs.tickets');
    final now = DateTime.now();
    final archived = ticket.copyWith(
      archivedAt: now,
      archivedBy: _currentUser.id,
      updatedAt: now,
    );
    try {
      await _client
          .rpc('archive_repair_ticket_v2', params: {'p_ticket_id': ticket.id})
          .timeout(_networkTimeout);
    } catch (error) {
      OfflineErrorClassifier.rethrowIfTerminal(error);
      await OfflineStore.enqueueMutation(
        userId: _currentUser.id,
        type: 'archive_repair_ticket_v2',
        payload: {'ticket_id': ticket.id},
      );
    }
    await OfflineStore.saveRepairTicket(archived);
  }

  Future<RepairPaymentModel> recordRepairPayment({
    required RepairTicketModel ticket,
    required double amount,
    required String method,
    required String accountId,
    String? note,
  }) async {
    await _gate.require('repairs.tickets');
    final now = DateTime.now();
    final payment = RepairPaymentModel(
      id: const Uuid().v4(),
      tenantId: ticket.tenantId,
      branchId: ticket.branchId,
      ticketId: ticket.id,
      amount: amount,
      method: method,
      accountId: accountId,
      ledgerTransactionId: const Uuid().v4(),
      note: note?.trim().isEmpty == true ? null : note?.trim(),
      receivedBy: _currentUser.id,
      receivedAt: now,
      createdAt: now,
    );
    await RepairPaymentLocalCommitter.commit(payment);
    try {
      await _client
          .rpc(
            'record_repair_payment_v2',
            params: {
              'p_payment_id': payment.id,
              'p_ticket_id': payment.ticketId,
              'p_amount': payment.amount,
              'p_method': payment.method,
              'p_account_id': payment.accountId,
              'p_ledger_transaction_id': payment.ledgerTransactionId,
              'p_note': payment.note,
              'p_received_at': payment.receivedAt.toIso8601String(),
            },
          )
          .timeout(_networkTimeout);
    } catch (e) {
      // The local payment and account ledger entry are already committed
      // atomically. Queue every remote failure instead of reporting a false
      // failure that could make the cashier submit the same payment again.
      await OfflineStore.enqueueMutation(
        userId: _currentUser.id,
        type: 'record_repair_payment_v2',
        payload: payment.toMap(),
      );
      debugPrint('Repair payment saved offline: $e');
    }
    return payment;
  }

  Future<void> _refreshStatusLogsCache(String ticketId) async {
    try {
      final data = await _client
          .from('repair_status_logs')
          .select()
          .eq('ticket_id', ticketId)
          .order('created_at', ascending: false)
          .timeout(_networkTimeout);

      final logs =
          (data as List)
              .map((row) => RepairStatusLogModel.fromMap(row))
              .toList();

      for (final log in logs) {
        await OfflineStore.saveRepairStatusLog(log);
      }
    } catch (_) {}
  }

  // ════════════════════════════════════════
  // OFFLINE MUTATION SYNC
  // ════════════════════════════════════════
  //
  // OfflineStore generic queue rakhta hai.
  // RepairRepository sirf repair-related mutations process karegi.
  //
  // Unknown mutation types ko remaining mein wapas save kar dete hain,
  // taake InventoryRepository/POSRepository apni mutations khud handle kar sakein.

  Future<void> syncOfflineMutations() async {
    final userId = _currentUser.id;
    final mutations = await OfflineStore.loadMutations(userId);

    if (mutations.isEmpty) return;

    final remaining = <OfflineMutation>[];
    final failedFinancialTicketIds = <String>{};

    for (final mutation in mutations) {
      final financialTicketId =
          const {
                'save_repair_parts_v2',
                'complete_repair_ticket_v2',
                'cancel_repair_ticket_v2',
                'cancel_repair_ticket_v3',
                'archive_repair_ticket_v2',
              }.contains(mutation.type)
              ? mutation.payload['ticket_id'] as String?
              : null;
      if (financialTicketId != null &&
          failedFinancialTicketIds.contains(financialTicketId)) {
        remaining.add(mutation);
        continue;
      }
      try {
        switch (mutation.type) {
          case 'upsert_repair_ticket':
            await _syncUpsertRepairTicket(mutation.payload);
            break;
          case 'update_repair_ticket_status':
            await _syncUpdateRepairTicketStatus(mutation.payload);
            break;
          case 'record_repair_payment_v2':
            await _syncRepairPayment(mutation.payload);
            break;
          case 'save_repair_parts_v2':
            try {
              await _client.rpc(
                'save_repair_parts_v2',
                params: {
                  'p_ticket_id': mutation.payload['ticket_id'],
                  'p_parts': mutation.payload['parts'],
                },
              );
            } catch (error) {
              final staleFinalizedMutation =
                  _isFinalizedPartsRejection(error) ||
                  await _isEquivalentFinalizedPartsReplay(mutation.payload);
              if (!staleFinalizedMutation) {
                rethrow;
              }
              debugPrint(
                'Discarded stale repair-parts mutation for finalized ticket '
                '${mutation.payload['ticket_id']}.',
              );
            }
            break;
          case 'complete_repair_ticket_v2':
            await _client.rpc(
              'complete_repair_ticket_v2',
              params: {
                'p_ticket_id': mutation.payload['ticket_id'],
                'p_event_id': mutation.payload['event_id'],
                'p_customer_charge': mutation.payload['customer_charge'],
                'p_service_charge': mutation.payload['service_charge'],
                'p_discount': mutation.payload['discount'],
                'p_commission': mutation.payload['commission'],
                'p_other_direct_cost': mutation.payload['other_direct_cost'],
              },
            );
            break;
          case 'cancel_repair_ticket_v2':
            await _client.rpc(
              'cancel_repair_ticket_v2',
              params: {
                'p_ticket_id': mutation.payload['ticket_id'],
                'p_event_id': mutation.payload['event_id'],
              },
            );
            break;
          case 'cancel_repair_ticket_v3':
            await _client.rpc(
              'cancel_repair_ticket_v3',
              params: {
                'p_ticket_id': mutation.payload['ticket_id'],
                'p_event_id': mutation.payload['event_id'],
                'p_refund_id': mutation.payload['refund_id'],
                'p_refund_account_id': mutation.payload['refund_account_id'],
                'p_refund_ledger_transaction_id':
                    mutation.payload['refund_ledger_transaction_id'],
              },
            );
            break;
          case 'archive_repair_ticket_v2':
            await _client.rpc(
              'archive_repair_ticket_v2',
              params: {'p_ticket_id': mutation.payload['ticket_id']},
            );
            break;
          default:
            remaining.add(mutation);
        }
      } catch (e) {
        debugPrint('Repair mutation sync failed: $e');
        if (financialTicketId != null) {
          failedFinancialTicketIds.add(financialTicketId);
        }
        remaining.add(mutation);
      }
    }

    await OfflineStore.saveMutationSyncResult(
      userId: userId,
      snapshot: mutations,
      remaining: remaining,
    );
  }

  Future<bool> _isEquivalentFinalizedPartsReplay(
    Map<String, dynamic> payload,
  ) async {
    try {
      final ticketId = payload['ticket_id'] as String?;
      final requestedRaw = payload['parts'] as List?;
      if (ticketId == null || requestedRaw == null) return false;

      final ticket =
          await _client
              .from('repair_tickets')
              .select('status')
              .eq('id', ticketId)
              .maybeSingle();
      if (!const {
        'completed',
        'delivered',
        'cancelled',
      }.contains(ticket?['status'])) {
        return false;
      }

      final savedRaw = await _client
          .from('repair_parts')
          .select(
            'source_type, product_id, supplier_id, settlement_type, '
            'name, quantity, unit_cost_snapshot, unit_sale_price',
          )
          .eq('ticket_id', ticketId);
      final requested =
          requestedRaw
              .map(
                (part) => _repairPartReplayKey(
                  Map<String, dynamic>.from(part as Map),
                ),
              )
              .toList()
            ..sort();
      final saved =
          (savedRaw as List)
              .map(
                (part) => _repairPartReplayKey(
                  Map<String, dynamic>.from(part as Map),
                ),
              )
              .toList()
            ..sort();
      if (requested.length != saved.length) return false;
      for (var index = 0; index < requested.length; index++) {
        if (requested[index] != saved[index]) return false;
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  bool _isFinalizedPartsRejection(Object error) {
    if (error is! PostgrestException || error.code != 'P0001') return false;
    return error.message == 'Finalized repair parts cannot be edited.' ||
        error.message == 'Cancelled repair parts cannot be edited.';
  }

  String _repairPartReplayKey(Map<String, dynamic> part) {
    final source = part['source_type']?.toString() ?? '';
    final directName =
        source == 'direct_purchase'
            ? part['name']?.toString().trim().toLowerCase() ?? ''
            : '';
    String amount(Object? value) =>
        ((value as num?)?.toDouble() ?? double.nan).toStringAsFixed(4);
    return [
      source,
      part['product_id']?.toString() ?? '',
      part['supplier_id']?.toString() ?? '',
      part['settlement_type']?.toString() ?? 'already_recorded',
      directName,
      part['quantity']?.toString() ?? '',
      amount(part['unit_cost_snapshot']),
      amount(part['unit_sale_price']),
    ].join('|');
  }

  Future<void> _syncUpsertRepairTicket(Map<String, dynamic> payload) async {
    final ticketMap = Map<String, dynamic>.from(payload['ticket'] as Map);

    // Offline local inventory_unit_id remote DB mein exist nahi karta ho sakta.
    // Isliye remote insert ke waqt inventory_unit_id remove kar dete hain.
    // Supabase trigger IMEI + product_id se unit find/create kar lega.
    ticketMap.remove('inventory_unit_id');

    final data =
        await _client
            .from('repair_tickets')
            .upsert(ticketMap, onConflict: 'id')
            .select()
            .single();

    final savedTicket = RepairTicketModel.fromMap(data);
    await OfflineStore.saveRepairTicket(savedTicket);

    // Initial log usually Supabase trigger create karega.
    // Agar ticket already existed ho aur trigger na chale,
    // to next status-log fetch remote se cache align kar dega.
  }

  Future<void> _syncUpdateRepairTicketStatus(
    Map<String, dynamic> payload,
  ) async {
    final ticket = RepairTicketModel.fromMap(
      Map<String, dynamic>.from(payload['ticket'] as Map),
    );
    final log = RepairStatusLogModel.fromMap(
      Map<String, dynamic>.from(payload['status_log'] as Map),
    );

    final data =
        await _client
            .from('repair_tickets')
            .update(_remoteTicketStatusMap(ticket))
            .eq('id', ticket.id)
            .select()
            .single();

    await OfflineStore.saveRepairTicket(RepairTicketModel.fromMap(data));

    await _client
        .from('repair_status_logs')
        .upsert(log.toCacheMap(), onConflict: 'id');
  }

  Future<void> _syncRepairPayment(Map<String, dynamic> payload) async {
    final payment = RepairPaymentModel.fromMap(payload);
    await _client.rpc(
      'record_repair_payment_v2',
      params: {
        'p_payment_id': payment.id,
        'p_ticket_id': payment.ticketId,
        'p_amount': payment.amount,
        'p_method': payment.method,
        'p_account_id': payment.accountId,
        'p_ledger_transaction_id': payment.ledgerTransactionId,
        'p_note': payment.note,
        'p_received_at': payment.receivedAt.toIso8601String(),
      },
    );
  }

  Future<void> _saveRepairPaymentCache(RepairPaymentModel payment) {
    final map = payment.toMap();
    return LocalDatabase.execute('''
      INSERT OR REPLACE INTO repair_payments(
        id, tenant_id, branch_id, ticket_id, amount, method, account_id,
        ledger_transaction_id, note, received_by, received_at, created_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''', map.values.toList());
  }

  Future<void> _replaceLocalRepairParts(
    String ticketId,
    List<RepairPartModel> parts, {
    String? createdByOverride,
  }) {
    return LocalDatabase.runInTransaction(() async {
      await LocalDatabase.execute(
        "DELETE FROM repair_parts WHERE ticket_id = ? AND state = 'planned'",
        [ticketId],
      );
      for (final part in parts) {
        final map = part.toMap();
        await LocalDatabase.execute(
          '''
          INSERT OR REPLACE INTO repair_parts(
            id, tenant_id, branch_id, ticket_id, source_type, product_id,
            supplier_id, settlement_type, name, quantity, unit_cost_snapshot,
            unit_sale_price, state, created_by, created_at, updated_at
          ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
          ''',
          [
            map['id'],
            map['tenant_id'],
            map['branch_id'],
            map['ticket_id'],
            map['source_type'],
            map['product_id'],
            map['supplier_id'],
            map['settlement_type'],
            map['name'],
            map['quantity'],
            map['unit_cost_snapshot'],
            map['unit_sale_price'],
            map['state'],
            createdByOverride ?? map['created_by'],
            map['created_at'],
            map['updated_at'],
          ],
        );
      }
    });
  }

  Future<List<RepairPartModel>> _loadLocalRepairParts(String ticketId) async {
    final rows = await LocalDatabase.select(
      'SELECT * FROM repair_parts WHERE ticket_id = ? ORDER BY created_at',
      [ticketId],
    );
    return rows.map(RepairPartModel.fromMap).toList();
  }

  Future<double> _localPartCost(String ticketId) async {
    final rows = await LocalDatabase.select(
      'SELECT COALESCE(SUM(quantity * unit_cost_snapshot), 0) AS cost FROM repair_parts WHERE ticket_id = ?',
      [ticketId],
    );
    return (rows.single['cost'] as num).toDouble();
  }

  Future<List<RepairPaymentModel>> _loadRepairPayments(String ticketId) async {
    final rows = await LocalDatabase.select(
      'SELECT * FROM repair_payments WHERE ticket_id = ? ORDER BY received_at',
      [ticketId],
    );
    return rows.map(RepairPaymentModel.fromMap).toList();
  }

  // ════════════════════════════════════════
  // PRIVATE HELPERS
  // ════════════════════════════════════════

  Future<InventoryUnitModel> _buildLocalInventoryUnit({
    required String tenantId,
    required String branchId,
    required String productId,
    required String imei,
    required String ticketId,
    required DateTime now,
    String? customerId,
  }) async {
    // Pehle local unit dhoondo.
    // Agar pehle se same branch + IMEI exist hai,
    // to usi id ko reuse karenge.
    final existing = await OfflineStore.loadInventoryUnitByImei(
      branchId: branchId,
      imei: imei,
    );

    return InventoryUnitModel(
      id: existing?.id ?? const Uuid().v4(),
      tenantId: existing?.tenantId ?? tenantId,
      branchId: existing?.branchId ?? branchId,
      productId: existing?.productId ?? productId,
      imei: imei,
      status: InventoryUnitStatus.inRepair,
      saleId: existing?.saleId,
      customerId: customerId ?? existing?.customerId,
      warrantyStartAt: existing?.warrantyStartAt,
      warrantyEndAt: existing?.warrantyEndAt,
      currentRepairTicketId: ticketId,
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
    );
  }

  Map<String, dynamic> _remoteTicketMap(RepairTicketModel ticket) {
    final map = ticket.toInsertMap();

    // Remote DB khud updated_at manage karegi trigger se.
    // created_at hum rakh sakte hain because offline-created ticket ka
    // original time preserve ho jaye ga.
    map.remove('updated_at');

    // Null values Supabase ko bhejna okay hai,
    // lekin inventory_unit_id null hi rehne do.
    // Trigger IMEI + product_id se link handle karega.
    return map;
  }

  Map<String, dynamic> _remoteTicketStatusMap(RepairTicketModel ticket) {
    return {
      'status': ticket.status.code,
      'total_cost': ticket.totalCost,
      'completed_at': ticket.completedAt?.toIso8601String(),
      'delivered_at': ticket.deliveredAt?.toIso8601String(),
    };
  }

  String _generateTicketNo(String ticketId, DateTime now) {
    final year = now.year.toString().padLeft(4, '0');
    final month = now.month.toString().padLeft(2, '0');
    final day = now.day.toString().padLeft(2, '0');
    final shortId = ticketId.substring(0, 6).toUpperCase();

    return 'REP-$year$month$day-$shortId';
  }
}
