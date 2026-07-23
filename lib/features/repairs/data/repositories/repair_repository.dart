import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:mobileshop_saas/core/extensions/repair_ticket_ext.dart';
import 'package:mobileshop_saas/core/offline/offline_store.dart';
import 'package:mobileshop_saas/core/utils/offline_error_classifier.dart';
import 'package:mobileshop_saas/features/repairs/data/models/inventory_unit_model.dart';
import 'package:mobileshop_saas/features/repairs/data/models/repair_status_log_model.dart';
import 'package:mobileshop_saas/features/repairs/data/models/repair_ticket_model.dart';
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
        .eq('branch_id', branchId);

    if (status != null) {
      query = query.eq('status', status.code);
    }

    final data = await query.order('created_at', ascending: false).limit(100);

    final tickets =
        (data as List).map((row) => RepairTicketModel.fromMap(row)).toList();

    for (final ticket in tickets) {
      await OfflineStore.saveRepairTicket(ticket);
    }

    return tickets;
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

    for (final mutation in mutations) {
      try {
        switch (mutation.type) {
          case 'upsert_repair_ticket':
            await _syncUpsertRepairTicket(mutation.payload);
            break;
          case 'update_repair_ticket_status':
            await _syncUpdateRepairTicketStatus(mutation.payload);
            break;
          default:
            remaining.add(mutation);
        }
      } catch (e) {
        debugPrint('Repair mutation sync failed: $e');
        remaining.add(mutation);
      }
    }

    await OfflineStore.saveMutationSyncResult(
      userId: userId,
      snapshot: mutations,
      remaining: remaining,
    );
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
