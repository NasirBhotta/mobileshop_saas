import '../models/customer_model.dart';

/// Ensures a locally attached customer exists before the sale RPC references it.
/// Only a queued customer creation may create a missing remote record.
class SaleCustomerResolver {
  final Future<String> Function(String) resolveId;
  final Future<CustomerModel?> Function(String) findRemote;
  final Future<CustomerModel?> Function(String) loadLocal;
  final Future<CustomerModel?> Function(String) findByPhone;
  final Future<Map<String, dynamic>?> Function(String) pendingCreation;
  final Future<void> Function(Map<String, dynamic>) createIfMissing;
  final Future<void> Function(String, String) rememberAlias;

  const SaleCustomerResolver({
    required this.resolveId,
    required this.findRemote,
    required this.loadLocal,
    required this.findByPhone,
    required this.pendingCreation,
    required this.createIfMissing,
    required this.rememberAlias,
  });

  Future<CustomerModel> resolve(String customerId) async {
    final id = await resolveId(customerId);
    final remote = await findRemote(id);
    if (remote != null) return remote;

    final local = await loadLocal(id);
    Future<CustomerModel?> recover() async {
      // A background sync may have inserted this same ID in the meantime.
      final byId = await findRemote(id);
      if (byId != null) return byId;
      final phone = local?.phone?.trim();
      if (phone == null || phone.isEmpty) return null;
      final byPhone = await findByPhone(phone);
      if (byPhone?.id != null) {
        await rememberAlias(id, byPhone!.id!);
      }
      return byPhone;
    }

    final existing = await recover();
    if (existing != null) return existing;
    final pending = await pendingCreation(id);
    if (pending == null) {
      final completed = await recover();
      if (completed != null) return completed;
      throw StateError(
        'Attached customer server par nahi mila. Customer list refresh karke dobara select karein.',
      );
    }
    try {
      await createIfMissing(pending);
    } catch (_) {
      // Recover only if another sync actually created/reconciled the customer.
      final raced = await recover();
      if (raced != null) return raced;
      rethrow;
    }
    final created = await recover();
    if (created == null) {
      throw StateError('Customer abhi sync nahi hua. Dobara try karein.');
    }
    return created;
  }
}
