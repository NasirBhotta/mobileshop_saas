import 'package:flutter/foundation.dart';
import 'package:mobileshop_saas/features/mobile_services/domain/mobile_service_types.dart';

enum MobileServiceTransactionStatus {
  completed,
  voided,
  pendingSync;

  String get code {
    switch (this) {
      case MobileServiceTransactionStatus.completed:
        return 'completed';
      case MobileServiceTransactionStatus.voided:
        return 'voided';
      case MobileServiceTransactionStatus.pendingSync:
        return 'pending_sync';
    }
  }

  static MobileServiceTransactionStatus fromCode(String code) {
    switch (code) {
      case 'completed':
        return MobileServiceTransactionStatus.completed;
      case 'voided':
        return MobileServiceTransactionStatus.voided;
      case 'pending_sync':
        return MobileServiceTransactionStatus.pendingSync;
      default:
        throw ArgumentError.value(code, 'code', 'Unsupported status');
    }
  }
}

@immutable
class MobileServiceProviderModel {
  final String id;
  final String tenantId;
  final String branchId;
  final MobileServiceCategory category;
  final MobileServiceProviderCode code;
  final String name;
  final String providerAccountId;
  final bool isActive;
  final String createdBy;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? archivedAt;
  final String? archivedBy;

  const MobileServiceProviderModel({
    required this.id,
    required this.tenantId,
    required this.branchId,
    required this.category,
    required this.code,
    required this.name,
    required this.providerAccountId,
    required this.isActive,
    required this.createdBy,
    required this.createdAt,
    required this.updatedAt,
    this.archivedAt,
    this.archivedBy,
  });

  factory MobileServiceProviderModel.fromMap(Map<String, dynamic> map) {
    return MobileServiceProviderModel(
      id: _requiredString(map, 'id'),
      tenantId: _requiredString(map, 'tenant_id'),
      branchId: _requiredString(map, 'branch_id'),
      category: MobileServiceCategory.fromCode(
        _requiredString(map, 'category'),
      ),
      code: MobileServiceProviderCode.fromCode(_requiredString(map, 'code')),
      name: _requiredString(map, 'name'),
      providerAccountId: _requiredString(map, 'provider_account_id'),
      isActive: _boolValue(map['is_active'], fallback: true),
      createdBy: _requiredString(map, 'created_by'),
      createdAt: _requiredDate(map, 'created_at'),
      updatedAt: _requiredDate(map, 'updated_at'),
      archivedAt: _optionalDate(map['archived_at']),
      archivedBy: _optionalString(map['archived_by']),
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'tenant_id': tenantId,
    'branch_id': branchId,
    'category': category.code,
    'code': code.code,
    'name': name,
    'provider_account_id': providerAccountId,
    'is_active': isActive,
    'created_by': createdBy,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
    'archived_at': archivedAt?.toIso8601String(),
    'archived_by': archivedBy,
  };
}

@immutable
class MobileServiceChargeRuleModel {
  final String id;
  final String tenantId;
  final String branchId;
  final String providerId;
  final MobileServiceOperation operation;
  final ServiceChargeCalculationMethod calculationMethod;
  final double rateAmount;
  final double? perAmount;
  final double? minimumFee;
  final double? maximumFee;
  final bool isActive;
  final String createdBy;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? archivedAt;
  final String? archivedBy;

  const MobileServiceChargeRuleModel({
    required this.id,
    required this.tenantId,
    required this.branchId,
    required this.providerId,
    required this.operation,
    required this.calculationMethod,
    required this.rateAmount,
    this.perAmount,
    this.minimumFee,
    this.maximumFee,
    required this.isActive,
    required this.createdBy,
    required this.createdAt,
    required this.updatedAt,
    this.archivedAt,
    this.archivedBy,
  });

  factory MobileServiceChargeRuleModel.fromMap(Map<String, dynamic> map) {
    return MobileServiceChargeRuleModel(
      id: _requiredString(map, 'id'),
      tenantId: _requiredString(map, 'tenant_id'),
      branchId: _requiredString(map, 'branch_id'),
      providerId: _requiredString(map, 'provider_id'),
      operation: MobileServiceOperation.fromCode(
        _requiredString(map, 'operation'),
      ),
      calculationMethod: ServiceChargeCalculationMethod.fromCode(
        _requiredString(map, 'calculation_method'),
      ),
      rateAmount: _requiredDouble(map, 'rate_amount'),
      perAmount: _optionalDouble(map['per_amount']),
      minimumFee: _optionalDouble(map['minimum_fee']),
      maximumFee: _optionalDouble(map['maximum_fee']),
      isActive: _boolValue(map['is_active'], fallback: true),
      createdBy: _requiredString(map, 'created_by'),
      createdAt: _requiredDate(map, 'created_at'),
      updatedAt: _requiredDate(map, 'updated_at'),
      archivedAt: _optionalDate(map['archived_at']),
      archivedBy: _optionalString(map['archived_by']),
    );
  }

  ServiceChargeRule toDomainRule() => ServiceChargeRule(
    method: calculationMethod,
    rateAmount: rateAmount,
    perAmount: perAmount,
    minimumFee: minimumFee,
    maximumFee: maximumFee,
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'tenant_id': tenantId,
    'branch_id': branchId,
    'provider_id': providerId,
    'operation': operation.code,
    'calculation_method': calculationMethod.code,
    'rate_amount': rateAmount,
    'per_amount': perAmount,
    'minimum_fee': minimumFee,
    'maximum_fee': maximumFee,
    'is_active': isActive,
    'created_by': createdBy,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
    'archived_at': archivedAt?.toIso8601String(),
    'archived_by': archivedBy,
  };
}

@immutable
class MobileServiceTransactionModel {
  final String id;
  final String tenantId;
  final String branchId;
  final String providerId;
  final String? chargeRuleId;
  final MobileServiceCategory serviceCategory;
  final MobileServiceOperation operation;
  final double serviceAmount;
  final ServiceChargeCalculationMethod calculationMethod;
  final double appliedRate;
  final double? appliedPerAmount;
  final double calculatedFee;
  final double chargedFee;
  final double customerCashAmount;
  final double profitAmount;
  final String cashAccountId;
  final String providerAccountId;
  final String cashLedgerTransactionId;
  final String providerLedgerTransactionId;
  final String? cashReversalTransactionId;
  final String? providerReversalTransactionId;
  final String? phoneNumber;
  final String? referenceNumber;
  final String? description;
  final MobileServiceTransactionStatus status;
  final DateTime transactionAt;
  final String createdBy;
  final DateTime createdAt;
  final DateTime? voidedAt;
  final String? voidedBy;
  final String? voidReason;

  const MobileServiceTransactionModel({
    required this.id,
    required this.tenantId,
    required this.branchId,
    required this.providerId,
    this.chargeRuleId,
    required this.serviceCategory,
    required this.operation,
    required this.serviceAmount,
    required this.calculationMethod,
    required this.appliedRate,
    this.appliedPerAmount,
    required this.calculatedFee,
    required this.chargedFee,
    required this.customerCashAmount,
    required this.profitAmount,
    required this.cashAccountId,
    required this.providerAccountId,
    required this.cashLedgerTransactionId,
    required this.providerLedgerTransactionId,
    this.cashReversalTransactionId,
    this.providerReversalTransactionId,
    this.phoneNumber,
    this.referenceNumber,
    this.description,
    required this.status,
    required this.transactionAt,
    required this.createdBy,
    required this.createdAt,
    this.voidedAt,
    this.voidedBy,
    this.voidReason,
  });

  bool get isVoided => status == MobileServiceTransactionStatus.voided;
  bool get isPendingSync =>
      status == MobileServiceTransactionStatus.pendingSync;

  factory MobileServiceTransactionModel.fromMap(Map<String, dynamic> map) {
    return MobileServiceTransactionModel(
      id: _requiredString(map, 'id'),
      tenantId: _requiredString(map, 'tenant_id'),
      branchId: _requiredString(map, 'branch_id'),
      providerId: _requiredString(map, 'provider_id'),
      chargeRuleId: _optionalString(map['charge_rule_id']),
      serviceCategory: MobileServiceCategory.fromCode(
        _requiredString(map, 'service_category'),
      ),
      operation: MobileServiceOperation.fromCode(
        _requiredString(map, 'operation'),
      ),
      serviceAmount: _requiredDouble(map, 'service_amount'),
      calculationMethod: ServiceChargeCalculationMethod.fromCode(
        _requiredString(map, 'calculation_method'),
      ),
      appliedRate: _requiredDouble(map, 'applied_rate'),
      appliedPerAmount: _optionalDouble(map['applied_per_amount']),
      calculatedFee: _requiredDouble(map, 'calculated_fee'),
      chargedFee: _requiredDouble(map, 'charged_fee'),
      customerCashAmount: _requiredDouble(map, 'customer_cash_amount'),
      profitAmount: _requiredDouble(map, 'profit_amount'),
      cashAccountId: _requiredString(map, 'cash_account_id'),
      providerAccountId: _requiredString(map, 'provider_account_id'),
      cashLedgerTransactionId: _requiredString(
        map,
        'cash_ledger_transaction_id',
      ),
      providerLedgerTransactionId: _requiredString(
        map,
        'provider_ledger_transaction_id',
      ),
      cashReversalTransactionId: _optionalString(
        map['cash_reversal_transaction_id'],
      ),
      providerReversalTransactionId: _optionalString(
        map['provider_reversal_transaction_id'],
      ),
      phoneNumber: _optionalString(map['phone_number']),
      referenceNumber: _optionalString(map['reference_number']),
      description: _optionalString(map['description']),
      status: MobileServiceTransactionStatus.fromCode(
        _requiredString(map, 'status'),
      ),
      transactionAt: _requiredDate(map, 'transaction_at'),
      createdBy: _requiredString(map, 'created_by'),
      createdAt: _requiredDate(map, 'created_at'),
      voidedAt: _optionalDate(map['voided_at']),
      voidedBy: _optionalString(map['voided_by']),
      voidReason: _optionalString(map['void_reason']),
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'tenant_id': tenantId,
    'branch_id': branchId,
    'provider_id': providerId,
    'charge_rule_id': chargeRuleId,
    'service_category': serviceCategory.code,
    'operation': operation.code,
    'service_amount': serviceAmount,
    'calculation_method': calculationMethod.code,
    'applied_rate': appliedRate,
    'applied_per_amount': appliedPerAmount,
    'calculated_fee': calculatedFee,
    'charged_fee': chargedFee,
    'customer_cash_amount': customerCashAmount,
    'profit_amount': profitAmount,
    'cash_account_id': cashAccountId,
    'provider_account_id': providerAccountId,
    'cash_ledger_transaction_id': cashLedgerTransactionId,
    'provider_ledger_transaction_id': providerLedgerTransactionId,
    'cash_reversal_transaction_id': cashReversalTransactionId,
    'provider_reversal_transaction_id': providerReversalTransactionId,
    'phone_number': phoneNumber,
    'reference_number': referenceNumber,
    'description': description,
    'status': status.code,
    'transaction_at': transactionAt.toIso8601String(),
    'created_by': createdBy,
    'created_at': createdAt.toIso8601String(),
    'voided_at': voidedAt?.toIso8601String(),
    'voided_by': voidedBy,
    'void_reason': voidReason,
  };
}

@immutable
class MobileServiceReportSummary {
  final int transactionCount;
  final int sendCount;
  final int receiveCount;
  final double sentAmount;
  final double receivedAmount;
  final double customerCashIn;
  final double customerCashOut;
  final double profit;

  const MobileServiceReportSummary({
    required this.transactionCount,
    required this.sendCount,
    required this.receiveCount,
    required this.sentAmount,
    required this.receivedAmount,
    required this.customerCashIn,
    required this.customerCashOut,
    required this.profit,
  });

  factory MobileServiceReportSummary.fromMap(Map<String, dynamic> map) {
    return MobileServiceReportSummary(
      transactionCount: _requiredInt(map, 'transaction_count'),
      sendCount: _requiredInt(map, 'send_count'),
      receiveCount: _requiredInt(map, 'receive_count'),
      sentAmount: _requiredDouble(map, 'sent_amount'),
      receivedAmount: _requiredDouble(map, 'received_amount'),
      customerCashIn: _requiredDouble(map, 'customer_cash_in'),
      customerCashOut: _requiredDouble(map, 'customer_cash_out'),
      profit: _requiredDouble(map, 'profit'),
    );
  }
}

@immutable
class MobileServiceProfitSummary {
  final double todayProfit;
  final double totalProfit;
  final double todayCashReceived;
  final double totalCashReceived;
  final double todayCashPaid;
  final double totalCashPaid;
  final double todayWalletIn;
  final double totalWalletIn;
  final double todayWalletOut;
  final double totalWalletOut;

  const MobileServiceProfitSummary({
    required this.todayProfit,
    required this.totalProfit,
    this.todayCashReceived = 0,
    this.totalCashReceived = 0,
    this.todayCashPaid = 0,
    this.totalCashPaid = 0,
    this.todayWalletIn = 0,
    this.totalWalletIn = 0,
    this.todayWalletOut = 0,
    this.totalWalletOut = 0,
  });

  factory MobileServiceProfitSummary.fromMap(Map<String, dynamic> map) {
    return MobileServiceProfitSummary(
      todayProfit: _requiredDouble(map, 'today_profit'),
      totalProfit: _requiredDouble(map, 'total_profit'),
      todayCashReceived: _optionalDouble(map['today_cash_received']) ?? 0,
      totalCashReceived: _optionalDouble(map['total_cash_received']) ?? 0,
      todayCashPaid: _optionalDouble(map['today_cash_paid']) ?? 0,
      totalCashPaid: _optionalDouble(map['total_cash_paid']) ?? 0,
      todayWalletIn: _optionalDouble(map['today_wallet_in']) ?? 0,
      totalWalletIn: _optionalDouble(map['total_wallet_in']) ?? 0,
      todayWalletOut: _optionalDouble(map['today_wallet_out']) ?? 0,
      totalWalletOut: _optionalDouble(map['total_wallet_out']) ?? 0,
    );
  }
}

String _requiredString(Map<String, dynamic> map, String key) {
  final value = _optionalString(map[key]);
  if (value == null) {
    throw FormatException('Missing required value: $key');
  }
  return value;
}

String? _optionalString(dynamic value) {
  if (value == null) return null;
  final text = value.toString().trim();
  return text.isEmpty ? null : text;
}

double _requiredDouble(Map<String, dynamic> map, String key) {
  final value = _optionalDouble(map[key]);
  if (value == null) {
    throw FormatException('Invalid required number: $key');
  }
  return value;
}

double? _optionalDouble(dynamic value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString());
}

int _requiredInt(Map<String, dynamic> map, String key) {
  final value = map[key];
  if (value is int) return value;
  if (value is num) return value.toInt();
  final parsed = int.tryParse(value?.toString() ?? '');
  if (parsed == null) {
    throw FormatException('Invalid required integer: $key');
  }
  return parsed;
}

bool _boolValue(dynamic value, {required bool fallback}) {
  if (value == null) return fallback;
  if (value is bool) return value;
  if (value is num) return value != 0;
  return value.toString() == 'true' || value.toString() == '1';
}

DateTime _requiredDate(Map<String, dynamic> map, String key) {
  final value = _optionalDate(map[key]);
  if (value == null) {
    throw FormatException('Invalid required date: $key');
  }
  return value;
}

DateTime? _optionalDate(dynamic value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  return DateTime.tryParse(value.toString());
}
