import 'package:flutter_test/flutter_test.dart';
import 'package:mobileshop_saas/features/mobile_services/data/models/mobile_service_models.dart';
import 'package:mobileshop_saas/features/mobile_services/data/remote/mobile_services_remote_data_source.dart';
import 'package:mobileshop_saas/features/mobile_services/data/repositories/mobile_services_repository.dart';
import 'package:mobileshop_saas/features/mobile_services/domain/mobile_service_types.dart';
import 'package:mobileshop_saas/features/mobile_services/presentation/providers/mobile_services_provider.dart';

void main() {
  late List<MobileServiceProviderModel> providers;
  late List<MobileServiceChargeRuleModel> rules;
  late MobileServiceFormController controller;

  setUp(() {
    providers = [MobileServiceProviderModel.fromMap(_providerMap())];
    rules = [MobileServiceChargeRuleModel.fromMap(_ruleMap())];
    controller = MobileServiceFormController(
      repository: MobileServicesRepository(remote: _NoopRemote()),
      readProviders: () => providers,
      readRules: () => rules,
    );
  });

  tearDown(() => controller.dispose());

  test('provider and amount selection creates a send preview', () {
    controller.selectProvider('provider-1');
    controller.enterAmount(800);

    expect(controller.state.canSubmit, isTrue);
    expect(controller.state.preview?.calculatedFee, 20);
    expect(controller.state.preview?.customerCashAmount, 820);
    expect(controller.state.preview?.cashDirection, MoneyDirection.moneyIn);
  });

  test('operation change selects its own rule', () {
    rules.add(
      MobileServiceChargeRuleModel.fromMap({
        ..._ruleMap(),
        'id': 'receive-rule-1',
        'operation': 'receive',
        'rate_amount': 25,
      }),
    );
    controller.selectProvider('provider-1');
    controller.enterAmount(800);

    controller.selectOperation(MobileServiceOperation.receive);

    expect(controller.state.canSubmit, isTrue);
    expect(controller.state.preview?.chargedFee, 25);
    expect(controller.state.preview?.customerCashAmount, 775);
    expect(
      controller.state.preview?.providerWalletDirection,
      MoneyDirection.moneyIn,
    );
  });

  test('missing operation rule produces a useful validation message', () {
    controller.selectProvider('provider-1');
    controller.enterAmount(800);

    controller.selectOperation(MobileServiceOperation.receive);

    expect(controller.state.canSubmit, isFalse);
    expect(
      controller.state.validationMessage,
      'Configure a charge rule for this operation.',
    );
  });

  test('fee override recalculates cash and profit', () {
    controller.selectProvider('provider-1');
    controller.enterAmount(800);

    controller.overrideFee(15);

    expect(controller.state.preview?.calculatedFee, 20);
    expect(controller.state.preview?.chargedFee, 15);
    expect(controller.state.preview?.customerCashAmount, 815);
    expect(controller.state.preview?.profitAmount, 15);
  });

  test('reset keeps provider and operation but clears entered money', () {
    controller.selectProvider('provider-1');
    controller.enterAmount(800);

    controller.reset();

    expect(controller.state.providerId, 'provider-1');
    expect(controller.state.operation, MobileServiceOperation.send);
    expect(controller.state.serviceAmount, isNull);
    expect(controller.state.preview, isNull);
    expect(controller.state.canSubmit, isFalse);
  });
}

class _NoopRemote implements MobileServicesRemoteDataSource {
  Never _unused() => throw UnimplementedError();

  @override
  Future<List<Map<String, dynamic>>> fetchChargeRules(String branchId) =>
      _unused();

  @override
  Future<List<Map<String, dynamic>>> fetchProviders(String branchId) =>
      _unused();

  @override
  Future<Map<String, dynamic>> fetchTransactionById(String transactionId) =>
      _unused();

  @override
  Future<List<Map<String, dynamic>>> fetchTransactions(
    String branchId, {
    required int limit,
  }) => _unused();

  @override
  Future<Map<String, dynamic>> invokeMapRpc(
    String functionName,
    Map<String, dynamic> params,
  ) => _unused();

  @override
  Future<String> invokeUuidRpc(
    String functionName,
    Map<String, dynamic> params,
  ) => _unused();

  @override
  Future<void> invokeVoidRpc(
    String functionName,
    Map<String, dynamic> params,
  ) => _unused();
}

Map<String, dynamic> _providerMap() => {
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
  'updated_at': '2026-07-25T10:00:00Z',
};

Map<String, dynamic> _ruleMap() => {
  'id': 'rule-1',
  'tenant_id': 'tenant-1',
  'branch_id': 'branch-1',
  'provider_id': 'provider-1',
  'operation': 'send',
  'calculation_method': 'full_slab',
  'rate_amount': 20,
  'per_amount': 1000,
  'minimum_fee': null,
  'maximum_fee': null,
  'is_active': true,
  'created_by': 'user-1',
  'created_at': '2026-07-25T10:00:00Z',
  'updated_at': '2026-07-25T10:00:00Z',
};
