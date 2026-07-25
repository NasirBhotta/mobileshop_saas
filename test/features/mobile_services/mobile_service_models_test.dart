import 'package:flutter_test/flutter_test.dart';
import 'package:mobileshop_saas/features/mobile_services/data/models/mobile_service_models.dart';
import 'package:mobileshop_saas/features/mobile_services/domain/mobile_service_types.dart';

void main() {
  test('provider maps database codes and archive fields', () {
    final provider = MobileServiceProviderModel.fromMap({
      'id': 'provider-1',
      'tenant_id': 'tenant-1',
      'branch_id': 'branch-1',
      'category': 'money_transfer',
      'code': 'easypaisa',
      'name': 'Main Easypaisa',
      'provider_account_id': 'wallet-1',
      'is_active': true,
      'created_by': 'user-1',
      'created_at': '2026-07-25T10:00:00Z',
      'updated_at': '2026-07-25T10:10:00Z',
      'archived_at': null,
      'archived_by': null,
    });

    expect(provider.category, MobileServiceCategory.moneyTransfer);
    expect(provider.code, MobileServiceProviderCode.easypaisa);
    expect(provider.providerAccountId, 'wallet-1');
    expect(provider.isActive, isTrue);
    expect(provider.toMap()['code'], 'easypaisa');
  });

  test('charge rule parses numeric strings and converts to domain rule', () {
    final model = MobileServiceChargeRuleModel.fromMap({
      'id': 'rule-1',
      'tenant_id': 'tenant-1',
      'branch_id': 'branch-1',
      'provider_id': 'provider-1',
      'operation': 'send',
      'calculation_method': 'full_slab',
      'rate_amount': '20.00',
      'per_amount': '1000.00',
      'minimum_fee': null,
      'maximum_fee': '100.00',
      'is_active': 1,
      'created_by': 'user-1',
      'created_at': '2026-07-25T10:00:00Z',
      'updated_at': '2026-07-25T10:10:00Z',
    });

    final rule = model.toDomainRule();

    expect(model.operation, MobileServiceOperation.send);
    expect(rule.method, ServiceChargeCalculationMethod.fullSlab);
    expect(rule.rateAmount, 20);
    expect(rule.perAmount, 1000);
    expect(rule.maximumFee, 100);
  });

  test('completed transaction round-trips through a map', () {
    final transaction = MobileServiceTransactionModel.fromMap(
      _transactionMap(),
    );
    final restored = MobileServiceTransactionModel.fromMap(transaction.toMap());

    expect(restored.operation, MobileServiceOperation.receive);
    expect(restored.serviceAmount, 800);
    expect(restored.calculatedFee, 20);
    expect(restored.customerCashAmount, 780);
    expect(restored.profitAmount, 20);
    expect(restored.status, MobileServiceTransactionStatus.completed);
    expect(restored.isVoided, isFalse);
  });

  test('voided transaction retains reversal audit details', () {
    final map =
        _transactionMap()..addAll({
          'status': 'voided',
          'cash_reversal_transaction_id': 'cash-reversal-1',
          'provider_reversal_transaction_id': 'wallet-reversal-1',
          'voided_at': '2026-07-25T12:00:00Z',
          'voided_by': 'owner-1',
          'void_reason': 'Entered twice',
        });

    final transaction = MobileServiceTransactionModel.fromMap(map);

    expect(transaction.isVoided, isTrue);
    expect(transaction.cashReversalTransactionId, 'cash-reversal-1');
    expect(transaction.voidedBy, 'owner-1');
    expect(transaction.voidReason, 'Entered twice');
  });

  test('missing required fields and unknown codes fail clearly', () {
    expect(
      () => MobileServiceProviderModel.fromMap({
        'id': 'provider-1',
        'tenant_id': 'tenant-1',
      }),
      throwsFormatException,
    );

    expect(
      () => MobileServiceOperation.fromCode('refund'),
      throwsArgumentError,
    );
  });
}

Map<String, dynamic> _transactionMap() => {
  'id': 'transaction-1',
  'tenant_id': 'tenant-1',
  'branch_id': 'branch-1',
  'provider_id': 'provider-1',
  'charge_rule_id': 'rule-1',
  'service_category': 'money_transfer',
  'operation': 'receive',
  'service_amount': '800.00',
  'calculation_method': 'full_slab',
  'applied_rate': '20.00',
  'applied_per_amount': '1000.00',
  'calculated_fee': '20.00',
  'charged_fee': '20.00',
  'customer_cash_amount': '780.00',
  'profit_amount': '20.00',
  'cash_account_id': 'cash-1',
  'provider_account_id': 'wallet-1',
  'cash_ledger_transaction_id': 'cash-ledger-1',
  'provider_ledger_transaction_id': 'wallet-ledger-1',
  'cash_reversal_transaction_id': null,
  'provider_reversal_transaction_id': null,
  'phone_number': '03001234567',
  'reference_number': 'EP-100',
  'description': null,
  'status': 'completed',
  'transaction_at': '2026-07-25T11:00:00Z',
  'created_by': 'user-1',
  'created_at': '2026-07-25T11:00:01Z',
  'voided_at': null,
  'voided_by': null,
  'void_reason': null,
};
