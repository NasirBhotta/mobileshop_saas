import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/support_repository.dart';
import '../domain/support_models.dart';

final supportRepositoryProvider = Provider((ref) => SupportRepository());

class AuditFilters {
  final String? tenantId, action, adminId;
  final DateTime? from, to;
  const AuditFilters({
    this.tenantId,
    this.action,
    this.adminId,
    this.from,
    this.to,
  });
}

final auditFiltersProvider =
    NotifierProvider<AuditFiltersNotifier, AuditFilters>(
      AuditFiltersNotifier.new,
    );

class AuditFiltersNotifier extends Notifier<AuditFilters> {
  @override
  AuditFilters build() => const AuditFilters();
  void update(AuditFilters value) => state = value;
}

final auditLogsProvider = FutureProvider<List<AuditEntry>>((ref) {
  final f = ref.watch(auditFiltersProvider);
  return ref
      .watch(supportRepositoryProvider)
      .audits(
        tenantId: f.tenantId,
        action: f.action,
        adminId: f.adminId,
        from: f.from,
        to: f.to,
      );
});
final failedJobsProvider = FutureProvider<List<FailedJob>>(
  (ref) => ref.watch(supportRepositoryProvider).jobs(),
);
final offlineFailuresProvider = FutureProvider<List<OfflineFailure>>(
  (ref) => ref.watch(supportRepositoryProvider).failures(),
);
final tenantActivityProvider = FutureProvider.family<List<AuditEntry>, String>(
  (ref, id) => ref.watch(supportRepositoryProvider).activity(id),
);
final supportNotesProvider = FutureProvider.family<List<SupportNote>, String>(
  (ref, id) => ref.watch(supportRepositoryProvider).notes(id),
);
final supportMutationProvider = AsyncNotifierProvider<SupportMutation, void>(
  SupportMutation.new,
);

class SupportMutation extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}
  Future<bool> run(
    Future<void> Function(SupportRepository) fn, {
    String? tenantId,
  }) async {
    state = const AsyncLoading();
    try {
      await fn(ref.read(supportRepositoryProvider));
      ref.invalidate(auditLogsProvider);
      ref.invalidate(failedJobsProvider);
      ref.invalidate(offlineFailuresProvider);
      if (tenantId != null) {
        ref.invalidate(tenantActivityProvider(tenantId));
        ref.invalidate(supportNotesProvider(tenantId));
      }
      state = const AsyncData(null);
      return true;
    } catch (e, s) {
      state = AsyncError(e, s);
      return false;
    }
  }
}
