import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/platform_analytics.dart';

class PlatformRepository {
  final SupabaseClient _client;
  PlatformRepository({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;
  Future<PlatformAnalytics> analytics() async {
    final value = await _client.rpc('platform_get_analytics');
    return PlatformAnalytics.fromJson(Map<String, dynamic>.from(value as Map));
  }

  Future<PlatformSettings> settings() async {
    final rows = await _client.rpc('platform_get_settings') as List;
    return PlatformSettings.fromJson(
      Map<String, dynamic>.from(rows.single as Map),
    );
  }

  Future<void> save(PlatformSettings s) => _client.rpc(
    'platform_update_settings',
    params: {
      'p_trial_duration_days': s.trialDays,
      'p_grace_period_days': s.graceDays,
      'p_default_billing_cycle': s.cycle,
      'p_default_currency': s.currency,
      'p_support_email': s.email,
      'p_support_phone': s.phone,
      'p_maintenance_mode': s.maintenance,
      'p_maintenance_message': s.message,
    },
  );
}
