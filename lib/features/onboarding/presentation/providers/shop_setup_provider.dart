import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

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

  void clearStatus() {
    state = const AsyncData(null);
  }

  void setValidationError(String message) {
    state = AsyncError(Exception(message), StackTrace.current);
  }

  Future<bool> submitSetup() async {
    state = const AsyncLoading();
    try {
      final data = _ref.read(shopSetupDataProvider);
      final user = Supabase.instance.client.auth.currentUser;

      if (user == null) throw Exception('User not logged in');
      if (data.businessType.isEmpty) throw Exception('Business type required');

      final tenantId = const Uuid().v4();
      debugPrint(
        "shop name: ${data.shopName}, city: ${data.city}, address: ${data.address}, businessType: ${data.businessType}, branchCount: ${data.branchCount}",
      );

      await Supabase.instance.client.from('users').upsert({
        'id': user.id,
        'full_name': user.userMetadata?['full_name'] ?? '',
        'email': user.email ?? '',
        'phone': user.userMetadata?['phone'] ?? '',
        'role': 'owner',
        'tenant_id': tenantId,
      }, onConflict: 'id');

      // 1. Tenant (shop) create karo
      await Supabase.instance.client.from('tenants').insert({
        'id': tenantId,
        'shop_name': data.shopName,
        'city': data.city,
        'address': data.address,
        'business_type': data.businessType,
        'branch_count': data.branchCount,
        'plan': 'free',
        'status': 'active',
        'setup_complete': true,
      });

      // 2. User ko tenant se link karo. Upsert keeps setup resilient if the
      // users row was not created during signup.

      state = const AsyncData(null);
      return true;
    } catch (e, st) {
      state = AsyncError(e, st);
      return false;
    }
  }
}
