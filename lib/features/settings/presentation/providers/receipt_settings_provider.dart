import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:mobileshop_saas/features/settings/data/models/receipt_configuration_model.dart';
import 'package:mobileshop_saas/features/settings/data/repositories/receipt_settings_repository.dart';

final receiptSettingsRepositoryProvider = Provider<ReceiptSettingsRepository>((ref) {
  return ReceiptSettingsRepository();
});

final receiptConfigurationProvider = FutureProvider.autoDispose<ReceiptConfigurationModel>((ref) async {
  final repository = ref.watch(receiptSettingsRepositoryProvider);
  return repository.loadReceiptConfig();
});

class ReceiptSettingsController extends StateNotifier<AsyncValue<ReceiptConfigurationModel?>> {
  final ReceiptSettingsRepository _repository;
  final Ref _ref;

  ReceiptSettingsController(this._repository, this._ref)
      : super(const AsyncValue.data(null));

  Future<bool> saveConfiguration(ReceiptConfigurationModel config) async {
    state = const AsyncValue.loading();
    try {
      await _repository.saveReceiptConfig(config);
      _ref.invalidate(receiptConfigurationProvider);
      state = AsyncValue.data(config);
      return true;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      return false;
    }
  }

  Future<ReceiptConfigurationModel?> resetToDefault() async {
    state = const AsyncValue.loading();
    try {
      final config = await _repository.resetToDefault();
      _ref.invalidate(receiptConfigurationProvider);
      state = AsyncValue.data(config);
      return config;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      return null;
    }
  }

  Future<void> sync() async {
    await _repository.syncOfflineMutations();
    _ref.invalidate(receiptConfigurationProvider);
  }
}

final receiptSettingsControllerProvider =
    StateNotifierProvider<ReceiptSettingsController, AsyncValue<ReceiptConfigurationModel?>>((ref) {
  final repository = ref.watch(receiptSettingsRepositoryProvider);
  return ReceiptSettingsController(repository, ref);
});
