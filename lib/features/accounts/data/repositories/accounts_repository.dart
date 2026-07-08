import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:mobileshop_saas/core/offline/offline_store.dart';
import 'package:mobileshop_saas/features/accounts/data/local/accounts_local_store.dart';
import 'package:mobileshop_saas/features/accounts/data/models/account_models.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

class AccountsRepository {
  static const _networkTimeout = Duration(milliseconds: 1200);

  final SupabaseClient _client = Supabase.instance.client;

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
    final tenantId = await _tenantId();
    final branchId = await _branchId(tenantId);

    final cached = await AccountsLocalStore.loadAccounts(branchId);
    if (cached.isNotEmpty) {
      unawaited(_refreshAccounts(tenantId, branchId));
      unawaited(syncOfflineMutations());
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
    final tenantId = await _tenantId();
    final branchId = await _branchId(tenantId);

    final cached = await AccountsLocalStore.loadTransactions(
      branchId,
      limit: limit,
    );
    if (cached.isNotEmpty) {
      unawaited(_refreshTransactions(tenantId, branchId, limit: limit));
      unawaited(syncOfflineMutations());
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

  Future<AccountModel> createAccount({
    required String name,
    required AccountType type,
    double openingBalance = 0,
    String? note,
  }) async {
    final tenantId = await _tenantId();
    final branchId = await _branchId(tenantId);
    final now = DateTime.now();

    final account = AccountModel(
      id: const Uuid().v4(),
      tenantId: tenantId,
      branchId: branchId,
      name: name.trim(),
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
      await OfflineStore.enqueueMutation(
        userId: _currentUser.id,
        type: 'upsert_account',
        payload: account.toMap(),
      );
      debugPrint('Account saved offline: $e');
    }

    return account;
  }

  Future<AccountTransactionModel> recordTransaction({
    required String accountId,
    required AccountTransactionDirection direction,
    required AccountTransactionType type,
    required double amount,
    String? description,
    String? referenceType,
    String? referenceId,
    DateTime? transactionAt,
  }) async {
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

    for (final mutation in mutations) {
      try {
        switch (mutation.type) {
          case 'upsert_account':
            await _client.from('accounts').upsert(mutation.payload);
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
        remaining.add(mutation);
      }
    }

    await OfflineStore.saveMutations(userId, remaining);
  }

  Future<void> _refreshAccounts(String tenantId, String branchId) async {
    try {
      await _fetchRemoteAccounts(tenantId, branchId).timeout(_networkTimeout);
    } catch (_) {}
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
      'record_account_transaction',
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
}
