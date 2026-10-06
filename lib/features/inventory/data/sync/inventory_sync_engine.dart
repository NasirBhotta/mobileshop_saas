import 'dart:async';
import 'dart:math';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/local/local_store.dart';
import '../../../../core/offline/offline_store.dart';
import '../../../../core/utils/offline_error_classifier.dart';
import '../models/price_history_model.dart';
import '../../../repairs/data/models/inventory_unit_model.dart';

/// Persistent, ordered upload worker for the Inventory module.
/// Fully decoupled from UI operations. Handles outbound mutations and inbound
/// data synchronization with retry backoff, jitter, and network gating.
class InventorySyncEngine {
  static final InventorySyncEngine instance = InventorySyncEngine();

  final SupabaseClient? _customClient;
  final Connectivity? _connectivity;
  final Random _random;

  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  Future<void>? _syncInFlight;
  Timer? _scheduledSyncTimer;
  int _consecutiveFailures = 0;
  bool _hasConnection = true;
  bool _disposed = false;
  Object? lastSyncError;

  static const int _baseDelayMs = 1000;
  static const int _maxDelayMs = 30000;
  static const Duration _networkTimeout = Duration(seconds: 8);

  InventorySyncEngine({
    SupabaseClient? client,
    Connectivity? connectivity,
    Random? random,
  }) : _customClient = client,
       _connectivity = connectivity,
       _random = random ?? Random() {
    _initConnectivityListener();
  }

  SupabaseClient get _client {
    if (_customClient != null) return _customClient;
    try {
      return Supabase.instance.client;
    } catch (_) {
      return SupabaseClient('http://127.0.0.1:54321', 'anon-key');
    }
  }

  @visibleForTesting
  set hasConnection(bool value) => _hasConnection = value;

  void _initConnectivityListener() {
    try {
      final conn = _connectivity ?? Connectivity();
      _connectivitySub = conn.onConnectivityChanged.listen((results) {
        final connected = results.any((r) => r != ConnectivityResult.none);
        final wasConnected = _hasConnection;
        _hasConnection = connected;

        if (connected && !wasConnected) {
          debugPrint(
            '[InventorySyncEngine] 🌐 Network restored -> Triggering sync',
          );
          _consecutiveFailures = 0;
          triggerSync();
        } else if (!connected && wasConnected) {
          debugPrint('[InventorySyncEngine] 🔌 Network lost -> Sync paused');
        }
      });
    } catch (e) {
      debugPrint(
        '[InventorySyncEngine] ⚠️ Failed to init connectivity listener: $e',
      );
    }
  }

  void dispose() {
    _disposed = true;
    _connectivitySub?.cancel();
    _scheduledSyncTimer?.cancel();
  }

  /// Triggers a non-blocking background sync pass.
  void triggerSync() {
    if (_disposed) return;
    unawaited(
      syncNow().catchError((Object error, StackTrace stack) {
        lastSyncError = error;
        debugPrint('[InventorySyncEngine] Sync could not complete: $error');
      }),
    );
  }

  /// Executes or returns the active sync pass.
  Future<void> syncNow() {
    final currentSync = _syncInFlight;
    if (currentSync != null) {
      return currentSync;
    }

    _scheduledSyncTimer?.cancel();
    late final Future<void> sync;
    sync = _runRequestedSyncCycles().whenComplete(() {
      if (identical(_syncInFlight, sync)) {
        _syncInFlight = null;
      }
    });
    _syncInFlight = sync;
    return sync;
  }

  Future<void> _runRequestedSyncCycles() async {
    final userId = _client.auth.currentUser?.id;
    lastSyncError = null;
    do {
      final completed = await _runSyncCycle(userId);
      if (!completed || _disposed) return;
      // Await follow-up work too, so a refresh cannot finish before products
      // queued during an active upload have had their sync pass.
      // Always take another snapshot after a successful pass. Enqueueing must
      // not require a UI trigger to include work added while uploading.
    } while (_hasConnection);
  }

  Future<bool> _runSyncCycle(String? expectedUserId) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      debugPrint('[InventorySyncEngine] ⏸️ User not logged in. Skipping sync.');
      return false;
    }
    if (user.id != expectedUserId) {
      lastSyncError = StateError('Account changed during inventory sync');
      return false;
    }

    final mutations = await OfflineStore.loadMutations(user.id);
    if (!mutations.any((mutation) => ownsMutation(mutation.type))) {
      return false;
    }

    debugPrint(
      '[InventorySyncEngine] 🚀 Starting sync cycle (${mutations.length} pending mutations)',
    );

    // Retain everything until it has actually been acknowledged by the server.
    // This also preserves operations owned by other module sync workers.
    final remaining = List<OfflineMutation>.of(mutations);

    for (final mutation in mutations) {
      if (!ownsMutation(mutation.type)) continue;
      if (_disposed || _client.auth.currentUser?.id != user.id) {
        lastSyncError = StateError(
          'Inventory sync paused because the session changed',
        );
        break;
      }
      // Check network connectivity before processing each mutation
      if (!_hasConnection) {
        debugPrint(
          '[InventorySyncEngine] ⏸️ Sync paused (No internet connection)',
        );
        break;
      }

      final swMut = Stopwatch()..start();
      try {
        await _processMutation(mutation);
        // Acknowledge each confirmed operation before sending the next one.
        // A crash later in the batch cannot replay earlier stock snapshots.
        await OfflineStore.removeMutation(
          userId: user.id,
          mutationId: mutation.id,
        );
        remaining.removeWhere((pending) => pending.id == mutation.id);
        _consecutiveFailures = 0;
        debugPrint(
          '[InventorySyncEngine] ✅ Successfully synced mutation: ${mutation.type} (ID: ${mutation.id}) in ${swMut.elapsedMilliseconds}ms',
        );
      } catch (e) {
        lastSyncError = e;
        final isRetryable = _isRetryableUpload(e);
        if (isRetryable) {
          _consecutiveFailures++;
          final backoffMs = _calculateBackoffWithJitter(_consecutiveFailures);
          debugPrint(
            '[InventorySyncEngine] ⚠️ Transient failure in ${swMut.elapsedMilliseconds}ms for ${mutation.type} (ID: ${mutation.id}): $e. '
            'Retrying in ${backoffMs}ms (Failures: $_consecutiveFailures)',
          );
          _scheduleRetry(backoffMs);
          break; // Stop further processing in this cycle to respect backoff
        } else {
          // Database/auth failures need intervention, but are never evidence
          // that the user's data was saved. Keep this and dependent operations.
          debugPrint(
            '[InventorySyncEngine] ❌ Terminal failure in ${swMut.elapsedMilliseconds}ms for ${mutation.type} (ID: ${mutation.id}): $e. '
            'Retaining mutation and dependent operations for a later sync.',
          );
          break;
        }
      }
    }

    debugPrint(
      '[InventorySyncEngine] 🏁 Sync cycle finished. '
      'Processed: ${mutations.length - remaining.length}, Remaining: ${remaining.length}',
    );
    return !remaining.any((mutation) => ownsMutation(mutation.type));
  }

  static bool ownsMutation(String type) =>
      _supportedMutationTypes.contains(type);

  bool _isRetryableUpload(Object error) {
    if (error is PostgrestException &&
        const {
          '408',
          '429',
          '500',
          '502',
          '503',
          '504',
          '57014',
        }.contains(error.code)) {
      return true;
    }
    return OfflineErrorClassifier.isRetryable(error);
  }

  static const _supportedMutationTypes = {
    'upsert_product',
    'delete_product',
    'upsert_category',
    'delete_category',
    'branch_threshold',
    'category_threshold',
    'stock_adjustment',
    'tenant_settings',
    'select_branch',
  };

  int _calculateBackoffWithJitter(int failureCount) {
    final exponential = _baseDelayMs * pow(2, min(failureCount - 1, 5)).toInt();
    final clamped = min(exponential, _maxDelayMs);
    final jitter = (_random.nextDouble() * 0.4 + 0.8); // 80% - 120% jitter
    return (clamped * jitter).toInt();
  }

  void _scheduleRetry(int delayMs) {
    if (_disposed) return;
    _scheduledSyncTimer?.cancel();
    _scheduledSyncTimer = Timer(Duration(milliseconds: delayMs), () {
      triggerSync();
    });
  }

  Future<void> _processMutation(OfflineMutation mutation) async {
    switch (mutation.type) {
      case 'upsert_product':
        await _syncUpsertProduct(mutation.payload);
        break;

      case 'delete_product':
        await _client
            .from('products')
            .update({'is_active': false})
            .eq('id', mutation.payload['product_id'])
            .eq('tenant_id', mutation.payload['tenant_id'])
            .eq('branch_id', mutation.payload['branch_id'])
            .timeout(_networkTimeout);
        break;

      case 'upsert_category':
        await _client
            .from('categories')
            .upsert(
              mutation.payload['category'] as Map<String, dynamic>,
              onConflict: 'id',
            )
            .timeout(_networkTimeout);
        break;

      case 'delete_category':
        await _client
            .from('categories')
            .delete()
            .eq('id', mutation.payload['category_id'])
            .eq('tenant_id', mutation.payload['tenant_id'])
            .eq('branch_id', mutation.payload['branch_id'])
            .timeout(_networkTimeout);
        break;

      case 'branch_threshold':
        await _client
            .from('inventory')
            .upsert({
              'branch_id': mutation.payload['branch_id'],
              'product_id': mutation.payload['product_id'],
              'reorder_threshold': mutation.payload['threshold'],
              'updated_at': mutation.payload['updated_at'],
            }, onConflict: 'branch_id,product_id')
            .timeout(_networkTimeout);
        break;

      case 'category_threshold':
        await _client
            .from('categories')
            .update({
              'default_reorder_threshold': mutation.payload['threshold'],
            })
            .eq('id', mutation.payload['category_id'])
            .eq('tenant_id', mutation.payload['tenant_id'])
            .eq('branch_id', mutation.payload['branch_id'])
            .timeout(_networkTimeout);
        break;

      case 'stock_adjustment':
        await _syncStockAdjustment(mutation.payload);
        break;

      case 'tenant_settings':
        await _client
            .from('tenant_settings')
            .upsert(
              mutation.payload['settings'] as Map<String, dynamic>,
              onConflict: 'tenant_id',
            )
            .timeout(_networkTimeout);
        break;

      case 'select_branch':
        await _client
            .from('users')
            .update({'branch_id': mutation.payload['branch_id']})
            .eq('id', mutation.payload['user_id'])
            .timeout(_networkTimeout);
        break;

      default:
        throw UnsupportedError(
          'Unsupported inventory mutation: ${mutation.type}',
        );
    }
  }

  Future<void> _syncUpsertProduct(Map<String, dynamic> payload) async {
    final product = Map<String, dynamic>.from(payload['product'] as Map);
    final stock = product.remove('stock') as int? ?? 0;
    product.remove('category_name');
    product.remove('categories');
    product.remove('branch_threshold');
    product.remove('category_threshold');
    final reorderThreshold = product['reorder_threshold'] as int?;

    try {
      await _client
          .rpc(
            'upsert_inventory_product_v2',
            params: {
              'p_product': {...product, 'stock': stock},
            },
          )
          .timeout(_networkTimeout);
      return;
    } on PostgrestException catch (e) {
      if (!_isMissingSecureProductRpc(e)) rethrow;
    }

    // Compatibility path for deployments that have not installed the additive
    // product RPC yet. Once available, the RPC owns tenant/branch fields and
    // only uses stock for an initial product inventory row.
    await _client
        .from('products')
        .upsert(product, onConflict: 'id')
        .timeout(_networkTimeout);

    await _client
        .from('inventory')
        .upsert({
          'branch_id': product['branch_id'],
          'product_id': product['id'],
          'quantity': stock < 0 ? 0 : stock,
          if (reorderThreshold != null) 'reorder_threshold': reorderThreshold,
          'updated_at': DateTime.now().toIso8601String(),
        }, onConflict: 'branch_id,product_id')
        .timeout(_networkTimeout);
  }

  Future<void> _syncStockAdjustment(Map<String, dynamic> payload) async {
    final adjustment = Map<String, dynamic>.from(payload['adjustment'] as Map);
    final newStock = (payload['new_stock'] as num).toInt();

    final remoteAdjustment = Map<String, dynamic>.from(adjustment);
    remoteAdjustment.remove('product_name');
    remoteAdjustment.remove('products');

    try {
      await _client
          .rpc(
            'adjust_inventory_stock_v2',
            params: {'p_adjustment': remoteAdjustment},
          )
          .timeout(_networkTimeout);
      return;
    } on PostgrestException catch (e) {
      if (!_isMissingSecureStockAdjustmentRpc(e)) rethrow;
    }

    // Compatibility path for the current production backend. It is used only
    // while the additive RPC has not yet been installed; once present, queued
    // adjustments use the server-side delta and idempotency boundary above.
    await _client
        .from('stock_adjustments')
        .upsert(remoteAdjustment, onConflict: 'id')
        .timeout(_networkTimeout);

    await _client
        .from('inventory')
        .upsert({
          'branch_id': adjustment['branch_id'],
          'product_id': adjustment['product_id'],
          'quantity': newStock,
          'updated_at': DateTime.now().toIso8601String(),
        }, onConflict: 'branch_id,product_id')
        .timeout(_networkTimeout);
  }

  bool _isMissingSecureStockAdjustmentRpc(PostgrestException error) {
    final message = error.message.toLowerCase();
    return error.code == 'PGRST202' ||
        (message.contains('adjust_inventory_stock_v2') &&
            (message.contains('could not find') ||
                message.contains('does not exist')));
  }

  bool _isMissingSecureProductRpc(PostgrestException error) {
    final message = error.message.toLowerCase();
    return error.code == 'PGRST202' ||
        (message.contains('upsert_inventory_product_v2') &&
            (message.contains('could not find') ||
                message.contains('does not exist')));
  }

  // ════════════════════════════════════════
  // INBOUND SYNC HELPERS (PULL TO LOCAL SQLITE)
  // ════════════════════════════════════════

  /// Pulls remote price history in the background and updates SQLite.
  Future<void> syncProductPriceHistoryOnline({
    required String tenantId,
    required String branchId,
    required String productId,
  }) async {
    try {
      final data = await _client
          .from('product_price_history')
          .select()
          .eq('tenant_id', tenantId)
          .eq('branch_id', branchId)
          .eq('product_id', productId)
          .order('changed_at', ascending: false)
          .limit(50)
          .timeout(const Duration(seconds: 4));

      final historyList =
          (data as List)
              .map(
                (e) => PriceHistoryModel.fromMap(
                  Map<String, dynamic>.from(e as Map),
                ),
              )
              .toList();

      if (historyList.isNotEmpty) {
        await LocalStore.saveProductPriceHistory(historyList);
        debugPrint(
          '[InventorySyncEngine] 📥 Synced ${historyList.length} price history entries for product $productId',
        );
      }
    } catch (e) {
      debugPrint(
        '[InventorySyncEngine] ℹ️ Background price history sync skipped: $e',
      );
    }
  }

  /// Pulls remote stock adjustments in the background and updates SQLite.
  Future<void> syncStockAdjustmentsOnline({
    required String tenantId,
    required String branchId,
    String? productId,
    int limit = 50,
  }) async {
    try {
      var query = _client
          .from('stock_adjustments')
          .select('*, products(name)')
          .eq('branch_id', branchId);

      if (productId != null) {
        query = query.eq('product_id', productId);
      }

      final data = await query
          .order('created_at', ascending: false)
          .limit(limit)
          .timeout(_networkTimeout);

      final maps = (data as List).cast<Map<String, dynamic>>();
      if (maps.isNotEmpty) {
        await LocalStore.saveStockAdjustments(maps);
        debugPrint(
          '[InventorySyncEngine] 📥 Synced ${maps.length} stock adjustment entries for branch $branchId',
        );
      }
    } catch (e) {
      debugPrint(
        '[InventorySyncEngine] ℹ️ Background stock adjustments sync skipped: $e',
      );
    }
  }

  /// Pulls remote inventory units for IMEI tracking and saves to SQLite.
  Future<void> syncInventoryUnitsOnline({
    required String branchId,
    required String productId,
  }) async {
    try {
      final res = await _client
          .from('inventory_units')
          .select()
          .eq('product_id', productId)
          .timeout(_networkTimeout);

      final remoteList =
          (res as List)
              .map(
                (r) => InventoryUnitModel.fromMap(
                  Map<String, dynamic>.from(r as Map),
                ),
              )
              .toList();

      for (final unit in remoteList) {
        await LocalStore.upsertInventoryUnit(unit);
      }
      debugPrint(
        '[InventorySyncEngine] 📥 Synced ${remoteList.length} inventory units for product $productId',
      );
    } catch (e) {
      debugPrint(
        '[InventorySyncEngine] ℹ️ Background inventory units sync skipped: $e',
      );
    }
  }
}
