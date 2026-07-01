import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/models/shop_setup_model.dart';

// ── Wizard data state ──
final shopSetupDataProvider =
    StateNotifierProvider<ShopSetupNotifier, ShopSetupModel>((ref) {
      return ShopSetupNotifier();
    });

class ShopSetupNotifier extends StateNotifier<ShopSetupModel> {
  ShopSetupNotifier() : super(const ShopSetupModel());

  void updateBasics({
    required String shopName,
    required String city,
    required String address,
  }) {
    state = state.copyWith(shopName: shopName, city: city, address: address);
  }

  void updateBusinessDetails({
    required String businessType,
    required int branchCount,
  }) {
    state = state.copyWith(
      businessType: businessType,
      branchCount: branchCount,
    );
  }
}

// ── Current step index (0, 1, 2) ──
final setupStepProvider = StateProvider<int>((ref) => 0);

// ── Submit controller ──
final setupSubmitControllerProvider =
    StateNotifierProvider<SetupSubmitController, AsyncValue<void>>((ref) {
      return SetupSubmitController(ref);
    });

class SetupSubmitController extends StateNotifier<AsyncValue<void>> {
  final Ref _ref;

  SetupSubmitController(this._ref) : super(const AsyncData(null));

  Future<bool> submitSetup() async {
    state = const AsyncLoading();
    try {
      final data = _ref.read(shopSetupDataProvider);
      final user = Supabase.instance.client.auth.currentUser;

      if (user == null) throw Exception('User not logged in');

      // 1. Tenant (shop) create karo
      final tenantResponse =
          await Supabase.instance.client
              .from('tenants')
              .insert({
                'shop_name': data.shopName,
                'city': data.city,
                'address': data.address,
                'business_type': data.businessType,
                'branch_count': data.branchCount,
                'setup_complete': true,
              })
              .select()
              .single();

      final tenantId = tenantResponse['id'];

      // 2. User ko tenant se link karo
      await Supabase.instance.client
          .from('users')
          .update({'tenant_id': tenantId})
          .eq('id', user.id);

      state = const AsyncData(null);
      return true;
    } catch (e, st) {
      state = AsyncError(e, st);
      return false;
    }
  }
}
