import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/platform_repository.dart';
import '../domain/platform_analytics.dart';

final platformRepositoryProvider = Provider((ref) => PlatformRepository());
final platformAnalyticsProvider = FutureProvider<PlatformAnalytics>(
  (ref) => ref.watch(platformRepositoryProvider).analytics(),
);
final platformSettingsProvider = FutureProvider<PlatformSettings>(
  (ref) => ref.watch(platformRepositoryProvider).settings(),
);
final settingsMutationProvider = AsyncNotifierProvider<SettingsMutation, void>(
  SettingsMutation.new,
);

class SettingsMutation extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}
  Future<bool> save(PlatformSettings value) async {
    state = const AsyncLoading();
    try {
      await ref.read(platformRepositoryProvider).save(value);
      ref.invalidate(platformSettingsProvider);
      state = const AsyncData(null);
      return true;
    } catch (e, s) {
      state = AsyncError(e, s);
      return false;
    }
  }
}
