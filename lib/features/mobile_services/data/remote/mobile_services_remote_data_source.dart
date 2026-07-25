import 'package:supabase_flutter/supabase_flutter.dart';

abstract interface class MobileServicesRemoteDataSource {
  Future<List<Map<String, dynamic>>> fetchProviders(String branchId);

  Future<List<Map<String, dynamic>>> fetchChargeRules(String branchId);

  Future<List<Map<String, dynamic>>> fetchTransactions(
    String branchId, {
    required int limit,
  });

  Future<String> invokeUuidRpc(
    String functionName,
    Map<String, dynamic> params,
  );

  Future<Map<String, dynamic>> fetchTransactionById(String transactionId);

  Future<Map<String, dynamic>> invokeMapRpc(
    String functionName,
    Map<String, dynamic> params,
  );

  Future<void> invokeVoidRpc(String functionName, Map<String, dynamic> params);
}

class SupabaseMobileServicesRemoteDataSource
    implements MobileServicesRemoteDataSource {
  final SupabaseClient _client;

  SupabaseMobileServicesRemoteDataSource({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  @override
  Future<List<Map<String, dynamic>>> fetchProviders(String branchId) async {
    final rows = await _client
        .from('mobile_service_providers')
        .select()
        .eq('branch_id', branchId)
        .order('name');
    return _mapRows(rows);
  }

  @override
  Future<List<Map<String, dynamic>>> fetchChargeRules(String branchId) async {
    final rows = await _client
        .from('mobile_service_charge_rules')
        .select()
        .eq('branch_id', branchId)
        .order('provider_id')
        .order('operation');
    return _mapRows(rows);
  }

  @override
  Future<List<Map<String, dynamic>>> fetchTransactions(
    String branchId, {
    required int limit,
  }) async {
    final rows = await _client
        .from('mobile_service_transactions')
        .select()
        .eq('branch_id', branchId)
        .order('transaction_at', ascending: false)
        .limit(limit);
    return _mapRows(rows);
  }

  @override
  Future<String> invokeUuidRpc(
    String functionName,
    Map<String, dynamic> params,
  ) async {
    final result = await _client.rpc(functionName, params: params);
    if (result is! String || result.trim().isEmpty) {
      throw FormatException('$functionName did not return a UUID.');
    }
    return result;
  }

  @override
  Future<Map<String, dynamic>> fetchTransactionById(
    String transactionId,
  ) async {
    final row =
        await _client
            .from('mobile_service_transactions')
            .select()
            .eq('id', transactionId)
            .single();
    return Map<String, dynamic>.from(row);
  }

  @override
  Future<Map<String, dynamic>> invokeMapRpc(
    String functionName,
    Map<String, dynamic> params,
  ) async {
    final result = await _client.rpc(functionName, params: params);
    if (result is! Map) {
      throw FormatException('$functionName did not return an object.');
    }
    return Map<String, dynamic>.from(result);
  }

  @override
  Future<void> invokeVoidRpc(
    String functionName,
    Map<String, dynamic> params,
  ) async {
    await _client.rpc(functionName, params: params);
  }

  List<Map<String, dynamic>> _mapRows(dynamic rows) {
    return (rows as List)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
  }
}
