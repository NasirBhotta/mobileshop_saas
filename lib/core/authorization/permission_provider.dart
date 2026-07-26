import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'permission_evaluator.dart';
import 'supabase_permission_data_source.dart';

final permissionDataSourceProvider = Provider<PermissionDataSource>((ref) {
  return SupabasePermissionDataSource();
});

final permissionEvaluatorProvider = Provider<PermissionEvaluator>((ref) {
  return PermissionEvaluator(
    dataSource: ref.watch(permissionDataSourceProvider),
  );
});

final permissionRevisionProvider = NotifierProvider<PermissionRevision, int>(
  PermissionRevision.new,
);

class PermissionRevision extends Notifier<int> {
  @override
  int build() => 0;

  void refresh() {
    ref.read(permissionEvaluatorProvider).invalidateAll();
    state++;
  }
}

final permissionAccessProvider =
    FutureProvider.family<PermissionAccessResult, String>((ref, key) {
      ref.watch(permissionRevisionProvider);
      return ref.watch(permissionEvaluatorProvider).can(key);
    });

final permissionRealtimeRefreshProvider = Provider<void>((ref) {
  final client = Supabase.instance.client;
  final channel = client.channel('role-permission-refresh');

  void refresh(PostgresChangePayload _) {
    ref.read(permissionRevisionProvider.notifier).refresh();
  }

  for (final table in const [
    'roles',
    'role_permissions',
    'user_role_assignments',
  ]) {
    channel.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: table,
      callback: refresh,
    );
  }

  channel.subscribe((status, error) {
    if (status == RealtimeSubscribeStatus.subscribed) {
      ref.read(permissionRevisionProvider.notifier).refresh();
    }
  });
  ref.onDispose(() => client.removeChannel(channel));
});
