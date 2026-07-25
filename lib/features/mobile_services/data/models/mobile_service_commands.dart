import 'package:mobileshop_saas/features/mobile_services/domain/mobile_service_types.dart';
import 'package:uuid/uuid.dart';

class SaveMobileServiceProviderCommand {
  final String? providerId;
  final String branchId;
  final MobileServiceProviderCode code;
  final String name;
  final String providerAccountId;

  const SaveMobileServiceProviderCommand({
    this.providerId,
    required this.branchId,
    required this.code,
    required this.name,
    required this.providerAccountId,
  });

  Map<String, dynamic> toRpcParams() => {
    'p_provider_id': providerId,
    'p_branch_id': branchId,
    'p_code': code.code,
    'p_name': name.trim(),
    'p_provider_account_id': providerAccountId,
  };
}

class SaveMobileServiceChargeRuleCommand {
  final String? ruleId;
  final String providerId;
  final MobileServiceOperation operation;
  final ServiceChargeCalculationMethod calculationMethod;
  final double rateAmount;
  final double? perAmount;
  final double? minimumFee;
  final double? maximumFee;

  const SaveMobileServiceChargeRuleCommand({
    this.ruleId,
    required this.providerId,
    required this.operation,
    required this.calculationMethod,
    required this.rateAmount,
    this.perAmount,
    this.minimumFee,
    this.maximumFee,
  });

  Map<String, dynamic> toRpcParams() => {
    'p_rule_id': ruleId,
    'p_provider_id': providerId,
    'p_operation': operation.code,
    'p_calculation_method': calculationMethod.code,
    'p_rate_amount': rateAmount,
    'p_per_amount': perAmount,
    'p_minimum_fee': minimumFee,
    'p_maximum_fee': maximumFee,
  };
}

class RecordMobileServiceTransactionCommand {
  final String transactionId;
  final String cashLedgerTransactionId;
  final String providerLedgerTransactionId;
  final String providerId;
  final String cashAccountId;
  final MobileServiceOperation operation;
  final double serviceAmount;
  final double? chargedFee;
  final String? phoneNumber;
  final String? referenceNumber;
  final String? description;
  final DateTime transactionAt;

  const RecordMobileServiceTransactionCommand({
    required this.transactionId,
    required this.cashLedgerTransactionId,
    required this.providerLedgerTransactionId,
    required this.providerId,
    required this.cashAccountId,
    required this.operation,
    required this.serviceAmount,
    this.chargedFee,
    this.phoneNumber,
    this.referenceNumber,
    this.description,
    required this.transactionAt,
  });

  factory RecordMobileServiceTransactionCommand.create({
    required String providerId,
    required String cashAccountId,
    required MobileServiceOperation operation,
    required double serviceAmount,
    double? chargedFee,
    String? phoneNumber,
    String? referenceNumber,
    String? description,
    DateTime? transactionAt,
    Uuid uuid = const Uuid(),
  }) {
    return RecordMobileServiceTransactionCommand(
      transactionId: uuid.v4(),
      cashLedgerTransactionId: uuid.v4(),
      providerLedgerTransactionId: uuid.v4(),
      providerId: providerId,
      cashAccountId: cashAccountId,
      operation: operation,
      serviceAmount: serviceAmount,
      chargedFee: chargedFee,
      phoneNumber: _clean(phoneNumber),
      referenceNumber: _clean(referenceNumber),
      description: _clean(description),
      transactionAt: transactionAt ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toRpcParams() => {
    'p_transaction_id': transactionId,
    'p_cash_ledger_transaction_id': cashLedgerTransactionId,
    'p_provider_ledger_transaction_id': providerLedgerTransactionId,
    'p_provider_id': providerId,
    'p_cash_account_id': cashAccountId,
    'p_operation': operation.code,
    'p_service_amount': serviceAmount,
    'p_charged_fee': chargedFee,
    'p_phone_number': phoneNumber,
    'p_reference_number': referenceNumber,
    'p_description': description,
    'p_transaction_at': transactionAt.toIso8601String(),
  };
}

class VoidMobileServiceTransactionCommand {
  final String transactionId;
  final String cashReversalTransactionId;
  final String providerReversalTransactionId;
  final String reason;

  const VoidMobileServiceTransactionCommand({
    required this.transactionId,
    required this.cashReversalTransactionId,
    required this.providerReversalTransactionId,
    required this.reason,
  });

  factory VoidMobileServiceTransactionCommand.create({
    required String transactionId,
    required String reason,
    Uuid uuid = const Uuid(),
  }) {
    return VoidMobileServiceTransactionCommand(
      transactionId: transactionId,
      cashReversalTransactionId: uuid.v4(),
      providerReversalTransactionId: uuid.v4(),
      reason: reason.trim(),
    );
  }

  Map<String, dynamic> toRpcParams() => {
    'p_transaction_id': transactionId,
    'p_cash_reversal_transaction_id': cashReversalTransactionId,
    'p_provider_reversal_transaction_id': providerReversalTransactionId,
    'p_reason': reason,
  };
}

String? _clean(String? value) {
  final text = value?.trim();
  return text == null || text.isEmpty ? null : text;
}
