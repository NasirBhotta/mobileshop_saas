import 'package:flutter_test/flutter_test.dart';
import 'package:mobileshop_saas/core/utils/secure_rpc_compatibility.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('recognizes the named RPC missing from PostgREST schema cache', () {
    expect(
      isMissingSecureRpc(
        const PostgrestException(
          message:
              'Could not find the function public.commit_pos_return_v2(p_return) in the schema cache',
          code: 'PGRST202',
        ),
        'commit_pos_return_v2',
        argumentName: 'p_return',
      ),
      isTrue,
    );
  });

  test('does not enable legacy fallback for unrelated PGRST202 errors', () {
    expect(
      isMissingSecureRpc(
        const PostgrestException(message: 'business rule', code: 'PGRST202'),
        'commit_pos_return_v2',
        argumentName: 'p_return',
      ),
      isFalse,
    );
  });

  test('does not enable fallback when another RPC name is missing', () {
    expect(
      isMissingSecureRpc(
        const PostgrestException(
          message:
              'Could not find the function public.other_rpc(p_data) in the schema cache',
          code: 'PGRST202',
        ),
        'commit_pos_return_v2',
        argumentName: 'p_return',
      ),
      isFalse,
    );
  });

  test('permission failures never enable legacy fallback', () {
    expect(
      isMissingSecureRpc(
        const PostgrestException(message: 'permission denied', code: '42501'),
        'commit_pos_return_v2',
        argumentName: 'p_return',
      ),
      isFalse,
    );
  });

  test('does not use inventory legacy fallback for an unrelated missing RPC', () {
    expect(
      isMissingSecureRpc(
        const PostgrestException(
          message:
              'Could not find the function public.other_rpc(p_data) in the schema cache',
          code: 'PGRST202',
        ),
        'upsert_inventory_product_v2',
        argumentName: 'p_product',
      ),
      isFalse,
    );
  });

  test('does not treat a signature error as a missing inventory RPC', () {
    expect(
      isMissingSecureRpc(
        const PostgrestException(
          message:
              'Could not find the function public.adjust_inventory_stock_v2(p_wrong) in the schema cache',
          code: 'PGRST202',
        ),
        'adjust_inventory_stock_v2',
        argumentName: 'p_adjustment',
      ),
      isFalse,
    );
  });

  test('recognizes the expected inventory stock RPC argument', () {
    expect(
      isMissingSecureRpc(
        const PostgrestException(
          message:
              'Could not find the function public.adjust_inventory_stock_v2(p_adjustment) in the schema cache',
          code: 'PGRST202',
        ),
        'adjust_inventory_stock_v2',
        argumentName: 'p_adjustment',
      ),
      isTrue,
    );
  });
}
