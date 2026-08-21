import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:mobileshop_saas/core/entitlements/entitlement_evaluator.dart';
import 'package:mobileshop_saas/core/entitlements/supabase_entitlement_data_source.dart';
import 'package:mobileshop_saas/core/offline/offline_store.dart';
import 'package:mobileshop_saas/features/accounts/data/local/accounts_local_store.dart';
import 'package:mobileshop_saas/features/accounts/data/models/account_models.dart';
import 'package:mobileshop_saas/features/accounts/domain/account_entitlement_gate.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

typedef AccountPermissionGuard = Future<void> Function(String permissionKey);

class AccountPermissionDeniedException implements Exception {
  final String permissionKey;

  const AccountPermissionDeniedException(this.permissionKey);

  @override
  String toString() => 'Account permission is required: $permissionKey';
}

class DuplicateAccountNameException implements Exception {
  final String name;

  const DuplicateAccountNameException(this.name);

  @override
  String toString() => 'An account named "$name" already exists.';
}

class AccountsRepository {
  static const _networkTimeout = Duration(milliseconds: 1200);

  final SupabaseClient _client;
  final AccountEntitlementGate _entitlements;
  final AccountPermissionGuard? _permissionGuard;

  AccountsRepository({
    SupabaseClient? client,
    EntitlementEvaluator? entitlementEvaluator,
    AccountPermissionGuard? permissionGuard,
  }) : _client = client ?? Supabase.instance.client,
       _permissionGuard = permissionGuard,
       _entitlements = AccountEntitlementGate(
         entitlementEvaluator ??
             EntitlementEvaluator(
               dataSource: SupabaseEntitlementDataSource(client: client),
             ),
       );

  Future<void> _requirePermission(String permissionKey) async {
    await _permissionGuard?.call(permissionKey);
  }

  User get _currentUser {
    final user = _client.auth.currentUser;
    if (user == null) throw Exception('User not logged in');
    return user;
  }

  Future<Map<String, dynamic>> _currentProfile() async {
    final cached = await OfflineStore.loadProfile(_currentUser.id);
    if (cached != null) return cached;

    final profile = await _client
        .from('users')
        .select('id, tenant_id, branch_id')
        .eq('id', _currentUser.id)
        .maybeSingle()
        .timeout(_networkTimeout);

    if (profile == null) throw Exception('User profile not found');

    final selectedBranchId = await OfflineStore.loadSelectedBranchId(
      _currentUser.id,
    );
    if (selectedBranchId != null) profile['branch_id'] = selectedBranchId;

    await OfflineStore.saveProfile(_currentUser.id, profile);
    return profile;
  }

  Future<String> _tenantId() async {
    final profile = await _currentProfile();
    final tenantId = profile['tenant_id'] as String?;
    if (tenantId == null) throw Exception('Tenant not found');
    return tenantId;
  }

  Future<String> _branchId(String tenantId) async {
    final profile = await _currentProfile();
    final selected = profile['branch_id'] as String?;
    if (selected != null) return selected;

    final branches = await OfflineStore.loadBranches(tenantId);
    if (branches.isNotEmpty && branches.first.id != null) {
      return branches.first.id!;
    }

    final branch = await _client
        .from('branches')
        .select('id')
        .eq('tenant_id', tenantId)
        .limit(1)
        .maybeSingle()
        .timeout(_networkTimeout);

    final branchId = branch?['id'] as String?;
    if (branchId == null) throw Exception('Branch not found');
    return branchId;
  }

  Future<List<AccountModel>> fetchAccounts() async {
    await _entitlements.require('accounts.core');
    await _requirePermission('account.account.view');
    final tenantId = await _tenantId();
    final branchId = await _branchId(tenantId);

    var canCleanDuplicates = false;
    try {
      await _requirePermission('account.account.update');
      canCleanDuplicates = true;
    } catch (_) {}
    if (canCleanDuplicates) {
      final safeDuplicates =
          await AccountsLocalStore.deactivateSafeDuplicateCashAccounts(
            branchId,
          );
      for (final duplicate in safeDuplicates) {
        try {
          await _client
              .from('accounts')
              .upsert(duplicate.toMap())
              .timeout(_networkTimeout);
        } catch (error) {
          await OfflineStore.enqueueMutation(
            userId: _currentUser.id,
            type: 'upsert_account',
            payload: duplicate.toMap(),
          );
          debugPrint('Safe duplicate account cleanup queued offline: $error');
        }
      }
    }

    final cached = await AccountsLocalStore.loadAccounts(branchId);
    if (cached.isNotEmpty) {
      unawaited(_syncThenRefreshAccounts(tenantId, branchId));
      return cached;
    }

    try {
      final remote = await _fetchRemoteAccounts(
        tenantId,
        branchId,
      ).timeout(_networkTimeout);
      if (remote.isNotEmpty) return remote;
    } catch (_) {}

    return [_createDefaultCashAccount(tenantId: tenantId, branchId: branchId)];
  }

  Future<List<AccountTransactionModel>> fetchTransactions({
    int limit = 80,
  }) async {
    await _entitlements.require('accounts.core');
    await _requirePermission('account.transaction.view');
    final tenantId = await _tenantId();
    final branchId = await _branchId(tenantId);

    final cached = await AccountsLocalStore.loadTransactions(
      branchId,
      limit: limit,
    );
    if (cached.isNotEmpty) {
      unawaited(_syncThenRefreshTransactions(tenantId, branchId, limit: limit));
      return cached;
    }

    try {
      return await _fetchRemoteTransactions(
        tenantId,
        branchId,
        limit: limit,
      ).timeout(_networkTimeout);
    } catch (_) {
      return AccountsLocalStore.loadTransactions(branchId, limit: limit);
    }
  }

  Future<List<AccountLedgerReconciliation>> reconcileLedger() async {
    await _entitlements.require('accounts.core');
    await _requirePermission('account.account.view');
    await _requirePermission('account.transaction.view');
    final tenantId = await _tenantId();
    final branchId = await _branchId(tenantId);

    try {
      final response = await _client
          .rpc(
            'account_ledger_reconciliation',
            params: {'p_tenant_id': tenantId, 'p_branch_id': branchId},
          )
          .timeout(_networkTimeout);
      return (response as List)
          .map(
            (row) => AccountLedgerReconciliation.fromMap(
              Map<String, dynamic>.from(row as Map),
            ),
          )
          .toList();
    } catch (_) {
      return AccountsLocalStore.reconcileBranch(branchId);
    }
  }

  Future<Map<String, dynamic>> fetchLedgerIntegritySummary() async {
    await _entitlements.require('accounts.core');
    await _requirePermission('account.account.view');
    await _requirePermission('account.transaction.view');
    final tenantId = await _tenantId();
    final branchId = await _branchId(tenantId);
    final response = await _client
        .rpc(
          'account_ledger_integrity_summary',
          params: {'p_tenant_id': tenantId, 'p_branch_id': branchId},
        )
        .timeout(_networkTimeout);
    return Map<String, dynamic>.from(response as Map);
  }

  Future<AccountModel> createAccount({
    required String name,
    required AccountType type,
    double openingBalance = 0,
    String? note,
  }) async {
    await _entitlements.require('accounts.core');
    await _requirePermission('account.account.create');
    final tenantId = await _tenantId();
    final branchId = await _branchId(tenantId);
    final cleanName = name.trim();
    if (await AccountsLocalStore.accountNameExists(
      branchId: branchId,
      name: cleanName,
    )) {
      throw DuplicateAccountNameException(cleanName);
    }
    final now = DateTime.now();

    final account = AccountModel(
      id: const Uuid().v4(),
      tenantId: tenantId,
      branchId: branchId,
      name: cleanName,
      type: type,
      openingBalance: openingBalance,
      currentBalance: openingBalance,
      note: _clean(note),
      createdBy: _currentUser.id,
      createdAt: now,
      updatedAt: now,
    );

    await AccountsLocalStore.saveAccount(account);

    try {
      await _client
          .from('accounts')
          .upsert(account.toMap())
          .timeout(_networkTimeout);
    } catch (e) {
      if (_isDuplicateNameError(e)) {
        await AccountsLocalStore.removeAccount(account.id);
        throw DuplicateAccountNameException(cleanName);
      }
      await OfflineStore.enqueueMutation(
        userId: _currentUser.id,
        type: 'upsert_account',
        payload: account.toMap(),
      );
      debugPrint('Account saved offline: $e');
    }

    return account;
  }

  Future<AccountModel> updateAccount({
    required String accountId,
    required String name,
    required AccountType type,
    String? note,
  }) async {
    await _entitlements.require('accounts.core');
    await _requirePermission('account.account.update');
    final existing = await AccountsLocalStore.loadAccountById(accountId);
    if (existing == null || !existing.isActive) {
      throw Exception('Account not found.');
    }
    final cleanName = name.trim();
    if (await AccountsLocalStore.accountNameExists(
      branchId: existing.branchId,
      name: cleanName,
      excludingAccountId: accountId,
    )) {
      throw DuplicateAccountNameException(cleanName);
    }
    final updated = AccountModel(
      id: existing.id,
      tenantId: existing.tenantId,
      branchId: existing.branchId,
      name: cleanName,
      type:
          existing.isDefault || _isSystemCashAccount(existing)
              ? existing.type
              : type,
      openingBalance: existing.openingBalance,
      currentBalance: existing.currentBalance,
      isDefault: existing.isDefault,
      isActive: existing.isActive,
      note: _clean(note),
      createdBy: existing.createdBy,
      createdAt: existing.createdAt,
      updatedAt: DateTime.now(),
    );
    await AccountsLocalStore.saveAccount(updated);
    await _upsertAccountOrQueue(updated, rollback: existing);
    return updated;
  }

  Future<void> deactivateAccount(String accountId) async {
    await _entitlements.require('accounts.core');
    await _requirePermission('account.account.update');
    final existing = await AccountsLocalStore.loadAccountById(accountId);
    if (existing == null || !existing.isActive) {
      throw Exception('Account not found.');
    }
    if (existing.isDefault || _isSystemCashAccount(existing)) {
      throw Exception(
        _isSystemCashAccount(existing)
            ? 'Cash in Shop system account cannot be deleted.'
            : 'Default account cannot be deleted.',
      );
    }
    final updated = existing.copyWith(
      isActive: false,
      updatedAt: DateTime.now(),
    );
    await AccountsLocalStore.saveAccount(updated);
    await _upsertAccountOrQueue(updated, rollback: existing);
  }

  Future<void> setDefaultCashAccount(String accountId) async {
    await _entitlements.require('accounts.core');
    await _requirePermission('account.account.update');
    final account = await AccountsLocalStore.loadAccountById(accountId);
    if (account == null || !account.isActive) {
      throw Exception('Account not found.');
    }
    if (account.type != AccountType.cash) {
      throw Exception('Only a cash account can be the default cash account.');
    }
    if (account.isDefault) return;

    await AccountsLocalStore.setDefaultAccount(
      branchId: account.branchId,
      accountId: account.id,
    );
    final payload = {
      'account_id': account.id,
      'tenant_id': account.tenantId,
      'branch_id': account.branchId,
    };
    try {
      await _setDefaultAccountRemote(payload).timeout(_networkTimeout);
    } catch (error) {
      await OfflineStore.enqueueMutation(
        userId: _currentUser.id,
        type: 'set_default_account',
        payload: payload,
      );
      debugPrint('Default cash account change queued offline: $error');
    }
  }

  Future<void> _setDefaultAccountRemote(Map<String, dynamic> payload) async {
    await _client.rpc(
      'set_default_cash_account',
      params: {'p_account_id': payload['account_id']},
    );
  }

  Future<void> _upsertAccountOrQueue(
    AccountModel account, {
    required AccountModel rollback,
  }) async {
    try {
      await _client
          .from('accounts')
          .upsert(account.toMap())
          .timeout(_networkTimeout);
    } catch (e) {
      if (_isDuplicateNameError(e)) {
        await AccountsLocalStore.saveAccount(rollback);
        throw DuplicateAccountNameException(account.name);
      }
      await OfflineStore.enqueueMutation(
        userId: _currentUser.id,
        type: 'upsert_account',
        payload: account.toMap(),
      );
      debugPrint('Account update saved offline: $e');
    }
  }

  bool _isDuplicateNameError(Object error) {
    final message = error.toString().toLowerCase();
    return message.contains('account_name_exists') ||
        message.contains('uq_accounts_branch_normalized_name');
  }

  Future<AccountTransactionModel> recordTransaction({
    required String accountId,
    required AccountTransactionDirection direction,
    required AccountTransactionType type,
    required double amount,
    String? description,
    String? referenceType,
    String? referenceId,
    String? sourceEventKey,
    String? reversalOfTransactionId,
    DateTime? transactionAt,
  }) async {
    await _entitlements.require('accounts.core');
    await _requirePermission('account.transaction.create');
    if (amount <= 0) throw Exception('Amount must be greater than zero.');

    final account = await AccountsLocalStore.loadAccountById(accountId);
    if (account == null) throw Exception('Account not found.');

    final now = DateTime.now();
    final transaction = AccountTransactionModel(
      id: const Uuid().v4(),
      tenantId: account.tenantId,
      branchId: account.branchId,
      accountId: account.id,
      type: type,
      direction: direction,
      amount: amount,
      description: _clean(description),
      referenceType: referenceType,
      referenceId: referenceId,
      sourceEventKey: sourceEventKey,
      reversalOfTransactionId: reversalOfTransactionId,
      transactionAt: transactionAt ?? now,
      createdBy: _currentUser.id,
      createdAt: now,
    );

    await AccountsLocalStore.applyTransaction(transaction);

    try {
      await _recordTransactionRemote(transaction).timeout(_networkTimeout);
    } catch (e) {
      await OfflineStore.enqueueMutation(
        userId: _currentUser.id,
        type: 'record_account_transaction',
        payload: transaction.toMap(),
      );
      debugPrint('Account transaction saved offline: $e');
    }

    return transaction;
  }

  Future<void> transfer({
    required String fromAccountId,
    required String toAccountId,
    required double amount,
    String? description,
  }) async {
    await _entitlements.require('accounts.transfers');
    await _requirePermission('account.transaction.create');
    if (amount <= 0) throw Exception('Amount must be greater than zero.');
    if (fromAccountId == toAccountId) {
      throw Exception('Select two different accounts.');
    }

    final from = await AccountsLocalStore.loadAccountById(fromAccountId);
    final to = await AccountsLocalStore.loadAccountById(toAccountId);
    if (from == null || to == null) throw Exception('Account not found.');

    final now = DateTime.now();
    final groupId = const Uuid().v4();
    final outgoing = AccountTransactionModel(
      id: const Uuid().v4(),
      tenantId: from.tenantId,
      branchId: from.branchId,
      accountId: from.id,
      relatedAccountId: to.id,
      transferGroupId: groupId,
      type: AccountTransactionType.transferOut,
      direction: AccountTransactionDirection.moneyOut,
      amount: amount,
      description: _clean(description) ?? 'Transfer to ${to.name}',
      transactionAt: now,
      createdBy: _currentUser.id,
      createdAt: now,
    );
    final incoming = AccountTransactionModel(
      id: const Uuid().v4(),
      tenantId: to.tenantId,
      branchId: to.branchId,
      accountId: to.id,
      relatedAccountId: from.id,
      transferGroupId: groupId,
      type: AccountTransactionType.transferIn,
      direction: AccountTransactionDirection.moneyIn,
      amount: amount,
      description: _clean(description) ?? 'Transfer from ${from.name}',
      transactionAt: now,
      createdBy: _currentUser.id,
      createdAt: now,
    );

    await AccountsLocalStore.applyTransfer(
      outgoing: outgoing,
      incoming: incoming,
    );

    try {
      await _recordTransferRemote(outgoing, incoming).timeout(_networkTimeout);
    } catch (e) {
      await OfflineStore.enqueueMutation(
        userId: _currentUser.id,
        type: 'record_account_transfer',
        payload: {'outgoing': outgoing.toMap(), 'incoming': incoming.toMap()},
      );
      debugPrint('Account transfer saved offline: $e');
    }
  }

  Future<void> syncOfflineMutations() async {
    final userId = _currentUser.id;
    final mutations = await OfflineStore.loadMutations(userId);
    if (mutations.isEmpty) return;

    final remaining = <OfflineMutation>[];
    Object? accountSyncError;

    for (final mutation in mutations) {
      try {
        switch (mutation.type) {
          case 'upsert_account':
            await _client.from('accounts').upsert(mutation.payload);
            break;
          case 'set_default_account':
            await _setDefaultAccountRemote(mutation.payload);
            break;
          case 'record_account_transaction':
            await _recordTransactionRemote(
              AccountTransactionModel.fromMap(mutation.payload),
            );
            break;
          case 'record_account_transfer':
            await _recordTransferRemote(
              AccountTransactionModel.fromMap(
                Map<String, dynamic>.from(mutation.payload['outgoing'] as Map),
              ),
              AccountTransactionModel.fromMap(
                Map<String, dynamic>.from(mutation.payload['incoming'] as Map),
              ),
            );
            break;
          default:
            remaining.add(mutation);
        }
      } catch (e) {
        debugPrint('Accounts sync failed: $e');
        if (_isDuplicateNameError(e)) {
          debugPrint(
            'Discarding conflicting account mutation from sync queue: ${mutation.payload}',
          );
        } else {
          remaining.add(mutation);
          accountSyncError ??= e;
        }
      }
    }

    await OfflineStore.saveMutationSyncResult(
      userId: userId,
      snapshot: mutations,
      remaining: remaining,
    );
    if (accountSyncError != null) {
      throw Exception('Accounts could not sync yet: $accountSyncError');
    }
  }

  Future<void> _syncThenRefreshAccounts(
    String tenantId,
    String branchId,
  ) async {
    try {
      await syncOfflineMutations();
    } catch (_) {
      return;
    }
    if (await _hasPendingOptimisticAccountMutation()) return;
    await _refreshAccounts(tenantId, branchId);
  }

  Future<bool> _hasPendingOptimisticAccountMutation() async {
    final pending = await OfflineStore.loadMutations(_currentUser.id);
    return pending.any(
      (mutation) =>
          // Pending settlements/sales protect optimistic cash balance from stale server balance
          mutation.type == 'customer_settlement' ||
          mutation.type == 'sale_checkout' ||
          mutation.type == 'sale_return' ||
          mutation.type == 'sale_return_approval',
    );
  }

  Future<void> _syncThenRefreshTransactions(
    String tenantId,
    String branchId, {
    required int limit,
  }) async {
    try {
      await syncOfflineMutations();
    } catch (_) {
      return;
    }
    await _refreshTransactions(tenantId, branchId, limit: limit);
  }

  Future<void> _refreshAccounts(String tenantId, String branchId) async {
    try {
      await _fetchRemoteAccounts(tenantId, branchId).timeout(_networkTimeout);
    } catch (_) {}
  }

  Future<void> refreshCurrentAccountsCache({
    Duration timeout = _networkTimeout,
  }) async {
    await _entitlements.require('accounts.core');
    // POS financial writes update SQLite optimistically. Never replace that
    // newer balance with an older server snapshot while its mutation is queued.
    if (await _hasPendingOptimisticAccountMutation()) return;
    final tenantId = await _tenantId();
    final branchId = await _branchId(tenantId);
    await _fetchRemoteAccounts(tenantId, branchId).timeout(timeout);
  }

  Future<List<AccountModel>> _fetchRemoteAccounts(
    String tenantId,
    String branchId,
  ) async {
    final data = await _client
        .from('accounts')
        .select()
        .eq('tenant_id', tenantId)
        .eq('branch_id', branchId)
        .eq('is_active', true)
        .order('is_default', ascending: false)
        .order('name');

    final accounts =
        (data as List).map((row) => AccountModel.fromMap(row)).toList();
    for (final account in accounts) {
      await AccountsLocalStore.saveAccount(account);
    }
    await AccountsLocalStore.retainOnlyRemoteActiveAccounts(
      branchId: branchId,
      activeAccountIds: accounts.map((account) => account.id).toSet(),
    );
    return accounts;
  }

  Future<void> _refreshTransactions(
    String tenantId,
    String branchId, {
    int limit = 80,
  }) async {
    try {
      await _fetchRemoteTransactions(
        tenantId,
        branchId,
        limit: limit,
      ).timeout(_networkTimeout);
    } catch (_) {}
  }

  Future<void> refreshCurrentTransactionsCache({
    int limit = 80,
    Duration timeout = _networkTimeout,
  }) async {
    await _entitlements.require('accounts.core');
    final tenantId = await _tenantId();
    final branchId = await _branchId(tenantId);
    await _fetchRemoteTransactions(
      tenantId,
      branchId,
      limit: limit,
    ).timeout(timeout);
  }

  Future<List<AccountTransactionModel>> _fetchRemoteTransactions(
    String tenantId,
    String branchId, {
    int limit = 80,
  }) async {
    final data = await _client
        .from('account_transactions')
        .select()
        .eq('tenant_id', tenantId)
        .eq('branch_id', branchId)
        .order('transaction_at', ascending: false)
        .limit(limit);

    final transactions =
        (data as List)
            .map((row) => AccountTransactionModel.fromMap(row))
            .toList();
    for (final transaction in transactions) {
      await AccountsLocalStore.saveTransaction(transaction);
    }
    return transactions;
  }

  Future<void> _recordTransactionRemote(
    AccountTransactionModel transaction,
  ) async {
    await _client.rpc(
      'record_account_transaction_v2',
      params: {
        'p_transaction_id': transaction.id,
        'p_tenant_id': transaction.tenantId,
        'p_branch_id': transaction.branchId,
        'p_account_id': transaction.accountId,
        'p_transaction_type': transaction.type.code,
        'p_direction': transaction.direction.code,
        'p_amount': transaction.amount,
        'p_description': transaction.description,
        'p_reference_type': transaction.referenceType,
        'p_reference_id': transaction.referenceId,
        'p_source_event_key': transaction.sourceEventKey,
        'p_reversal_of_transaction_id': transaction.reversalOfTransactionId,
        'p_transaction_at': transaction.transactionAt.toIso8601String(),
      },
    );
  }

  Future<void> _recordTransferRemote(
    AccountTransactionModel outgoing,
    AccountTransactionModel incoming,
  ) async {
    await _client.rpc(
      'record_account_transfer',
      params: {
        'p_out_transaction_id': outgoing.id,
        'p_in_transaction_id': incoming.id,
        'p_tenant_id': outgoing.tenantId,
        'p_branch_id': outgoing.branchId,
        'p_from_account_id': outgoing.accountId,
        'p_to_account_id': incoming.accountId,
        'p_transfer_group_id': outgoing.transferGroupId,
        'p_amount': outgoing.amount,
        'p_description': outgoing.description,
        'p_transaction_at': outgoing.transactionAt.toIso8601String(),
      },
    );
  }

  AccountModel _createDefaultCashAccount({
    required String tenantId,
    required String branchId,
  }) {
    final now = DateTime.now();
    final account = AccountModel(
      id: const Uuid().v4(),
      tenantId: tenantId,
      branchId: branchId,
      name: 'Cash in Shop',
      type: AccountType.cash,
      isDefault: true,
      createdBy: _currentUser.id,
      createdAt: now,
      updatedAt: now,
    );

    unawaited(AccountsLocalStore.saveAccount(account));
    unawaited(
      _client
          .from('accounts')
          .upsert(account.toMap())
          .timeout(_networkTimeout)
          .catchError((e) {
            return OfflineStore.enqueueMutation(
              userId: _currentUser.id,
              type: 'upsert_account',
              payload: account.toMap(),
            );
          }),
    );

    return account;
  }

  String? _clean(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    return trimmed;
  }

  bool _isSystemCashAccount(AccountModel account) =>
      account.name.trim().toLowerCase() == 'cash in shop';
}
