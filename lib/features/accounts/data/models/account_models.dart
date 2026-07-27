import 'package:flutter/foundation.dart';

enum AccountType {
  cash,
  bank,
  mobileWallet,
  card,
  other;

  String get code {
    switch (this) {
      case AccountType.cash:
        return 'cash';
      case AccountType.bank:
        return 'bank';
      case AccountType.mobileWallet:
        return 'mobile_wallet';
      case AccountType.card:
        return 'card';
      case AccountType.other:
        return 'other';
    }
  }

  String get label {
    switch (this) {
      case AccountType.cash:
        return 'Cash';
      case AccountType.bank:
        return 'Bank';
      case AccountType.mobileWallet:
        return 'Mobile Wallet';
      case AccountType.card:
        return 'Card';
      case AccountType.other:
        return 'Other';
    }
  }

  static AccountType fromCode(String? code) {
    switch (code) {
      case 'bank':
        return AccountType.bank;
      case 'mobile_wallet':
        return AccountType.mobileWallet;
      case 'card':
        return AccountType.card;
      case 'other':
        return AccountType.other;
      case 'cash':
      default:
        return AccountType.cash;
    }
  }
}

enum AccountTransactionDirection {
  moneyIn,
  moneyOut;

  String get code {
    switch (this) {
      case AccountTransactionDirection.moneyIn:
        return 'in';
      case AccountTransactionDirection.moneyOut:
        return 'out';
    }
  }

  String get label {
    switch (this) {
      case AccountTransactionDirection.moneyIn:
        return 'Money In';
      case AccountTransactionDirection.moneyOut:
        return 'Money Out';
    }
  }

  double signedAmount(double amount) {
    switch (this) {
      case AccountTransactionDirection.moneyIn:
        return amount.abs();
      case AccountTransactionDirection.moneyOut:
        return -amount.abs();
    }
  }

  static AccountTransactionDirection fromCode(String? code) {
    switch (code) {
      case 'out':
        return AccountTransactionDirection.moneyOut;
      case 'in':
      default:
        return AccountTransactionDirection.moneyIn;
    }
  }
}

enum AccountTransactionType {
  openingBalance,
  sale,
  customerPayment,
  supplierPayment,
  expense,
  purchase,
  transferIn,
  transferOut,
  adjustment,
  other;

  String get code {
    switch (this) {
      case AccountTransactionType.openingBalance:
        return 'opening_balance';
      case AccountTransactionType.sale:
        return 'sale';
      case AccountTransactionType.customerPayment:
        return 'customer_payment';
      case AccountTransactionType.supplierPayment:
        return 'supplier_payment';
      case AccountTransactionType.expense:
        return 'expense';
      case AccountTransactionType.purchase:
        return 'purchase';
      case AccountTransactionType.transferIn:
        return 'transfer_in';
      case AccountTransactionType.transferOut:
        return 'transfer_out';
      case AccountTransactionType.adjustment:
        return 'adjustment';
      case AccountTransactionType.other:
        return 'other';
    }
  }

  String get label {
    switch (this) {
      case AccountTransactionType.openingBalance:
        return 'Opening Balance';
      case AccountTransactionType.sale:
        return 'Sale';
      case AccountTransactionType.customerPayment:
        return 'Customer Payment';
      case AccountTransactionType.supplierPayment:
        return 'Supplier Payment';
      case AccountTransactionType.expense:
        return 'Expense';
      case AccountTransactionType.purchase:
        return 'Purchase';
      case AccountTransactionType.transferIn:
        return 'Transfer In';
      case AccountTransactionType.transferOut:
        return 'Transfer Out';
      case AccountTransactionType.adjustment:
        return 'Adjustment';
      case AccountTransactionType.other:
        return 'Other';
    }
  }

  static AccountTransactionType fromCode(String? code) {
    switch (code) {
      case 'opening_balance':
        return AccountTransactionType.openingBalance;
      case 'sale':
        return AccountTransactionType.sale;
      case 'customer_payment':
        return AccountTransactionType.customerPayment;
      case 'supplier_payment':
        return AccountTransactionType.supplierPayment;
      case 'expense':
        return AccountTransactionType.expense;
      case 'purchase':
        return AccountTransactionType.purchase;
      case 'transfer_in':
        return AccountTransactionType.transferIn;
      case 'transfer_out':
        return AccountTransactionType.transferOut;
      case 'adjustment':
        return AccountTransactionType.adjustment;
      case 'other':
      default:
        return AccountTransactionType.other;
    }
  }
}

@immutable
class AccountModel {
  final String id;
  final String tenantId;
  final String branchId;
  final String name;
  final AccountType type;
  final double openingBalance;
  final double currentBalance;
  final bool isDefault;
  final bool isActive;
  final String? note;
  final String? createdBy;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const AccountModel({
    required this.id,
    required this.tenantId,
    required this.branchId,
    required this.name,
    this.type = AccountType.cash,
    this.openingBalance = 0,
    this.currentBalance = 0,
    this.isDefault = false,
    this.isActive = true,
    this.note,
    this.createdBy,
    this.createdAt,
    this.updatedAt,
  });

  factory AccountModel.fromMap(Map<String, dynamic> map) {
    return AccountModel(
      id: map['id'] as String,
      tenantId: map['tenant_id'] as String,
      branchId: map['branch_id'] as String,
      name: map['name'] as String,
      type: AccountType.fromCode(map['account_type'] as String?),
      openingBalance: _doubleValue(map['opening_balance']),
      currentBalance: _doubleValue(map['current_balance']),
      isDefault: _boolValue(map['is_default']),
      isActive: _boolValue(map['is_active'], fallback: true),
      note: map['note'] as String?,
      createdBy: map['created_by'] as String?,
      createdAt: _dateTimeOrNull(map['created_at']),
      updatedAt: _dateTimeOrNull(map['updated_at']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'tenant_id': tenantId,
      'branch_id': branchId,
      'name': name,
      'account_type': type.code,
      'opening_balance': openingBalance,
      'current_balance': currentBalance,
      'is_default': isDefault,
      'is_active': isActive,
      'note': note,
      'created_by': createdBy,
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  AccountModel copyWith({
    String? id,
    String? tenantId,
    String? branchId,
    String? name,
    AccountType? type,
    double? openingBalance,
    double? currentBalance,
    bool? isDefault,
    bool? isActive,
    String? note,
    String? createdBy,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return AccountModel(
      id: id ?? this.id,
      tenantId: tenantId ?? this.tenantId,
      branchId: branchId ?? this.branchId,
      name: name ?? this.name,
      type: type ?? this.type,
      openingBalance: openingBalance ?? this.openingBalance,
      currentBalance: currentBalance ?? this.currentBalance,
      isDefault: isDefault ?? this.isDefault,
      isActive: isActive ?? this.isActive,
      note: note ?? this.note,
      createdBy: createdBy ?? this.createdBy,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

@immutable
class AccountTransactionModel {
  final String id;
  final String tenantId;
  final String branchId;
  final String accountId;
  final String? relatedAccountId;
  final String? transferGroupId;
  final AccountTransactionType type;
  final AccountTransactionDirection direction;
  final double amount;
  final String? description;
  final String? referenceType;
  final String? referenceId;
  final String? sourceEventKey;
  final String? reversalOfTransactionId;
  final DateTime transactionAt;
  final String? createdBy;
  final DateTime? createdAt;

  const AccountTransactionModel({
    required this.id,
    required this.tenantId,
    required this.branchId,
    required this.accountId,
    this.relatedAccountId,
    this.transferGroupId,
    required this.type,
    required this.direction,
    required this.amount,
    this.description,
    this.referenceType,
    this.referenceId,
    this.sourceEventKey,
    this.reversalOfTransactionId,
    required this.transactionAt,
    this.createdBy,
    this.createdAt,
  });

  double get signedAmount => direction.signedAmount(amount);

  factory AccountTransactionModel.fromMap(Map<String, dynamic> map) {
    return AccountTransactionModel(
      id: map['id'] as String,
      tenantId: map['tenant_id'] as String,
      branchId: map['branch_id'] as String,
      accountId: map['account_id'] as String,
      relatedAccountId: map['related_account_id'] as String?,
      transferGroupId: map['transfer_group_id'] as String?,
      type: AccountTransactionType.fromCode(map['transaction_type'] as String?),
      direction: AccountTransactionDirection.fromCode(
        map['direction'] as String?,
      ),
      amount: _doubleValue(map['amount']),
      description: map['description'] as String?,
      referenceType: map['reference_type'] as String?,
      referenceId: map['reference_id'] as String?,
      sourceEventKey: map['source_event_key'] as String?,
      reversalOfTransactionId: map['reversal_of_transaction_id'] as String?,
      transactionAt: _dateTimeRequired(map['transaction_at']),
      createdBy: map['created_by'] as String?,
      createdAt: _dateTimeOrNull(map['created_at']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'tenant_id': tenantId,
      'branch_id': branchId,
      'account_id': accountId,
      'related_account_id': relatedAccountId,
      'transfer_group_id': transferGroupId,
      'transaction_type': type.code,
      'direction': direction.code,
      'amount': amount,
      'description': description,
      'reference_type': referenceType,
      'reference_id': referenceId,
      'source_event_key': sourceEventKey,
      'reversal_of_transaction_id': reversalOfTransactionId,
      'transaction_at': transactionAt.toIso8601String(),
      'created_by': createdBy,
      'created_at': createdAt?.toIso8601String(),
    };
  }
}

@immutable
class AccountLedgerReconciliation {
  final String accountId;
  final String accountName;
  final double openingBalance;
  final double storedBalance;
  final double expectedBalance;
  final int ledgerEntryCount;

  const AccountLedgerReconciliation({
    required this.accountId,
    required this.accountName,
    required this.openingBalance,
    required this.storedBalance,
    required this.expectedBalance,
    required this.ledgerEntryCount,
  });

  double get difference => storedBalance - expectedBalance;

  bool get isReconciled => difference.abs() <= 0.005;

  factory AccountLedgerReconciliation.fromMap(Map<String, dynamic> map) {
    return AccountLedgerReconciliation(
      accountId: map['account_id'] as String,
      accountName: map['account_name'] as String,
      openingBalance: _doubleValue(map['opening_balance']),
      storedBalance: _doubleValue(map['stored_balance']),
      expectedBalance: _doubleValue(map['expected_balance']),
      ledgerEntryCount: _intValue(map['ledger_entry_count']),
    );
  }
}

double _doubleValue(dynamic value) {
  if (value == null) return 0;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString()) ?? 0;
}

int _intValue(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

bool _boolValue(dynamic value, {bool fallback = false}) {
  if (value == null) return fallback;
  if (value is bool) return value;
  if (value is num) return value != 0;
  return value.toString() == 'true' || value.toString() == '1';
}

DateTime? _dateTimeOrNull(dynamic value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  return DateTime.tryParse(value.toString());
}

DateTime _dateTimeRequired(dynamic value) {
  final parsed = _dateTimeOrNull(value);
  if (parsed == null) {
    throw FormatException('Invalid required date: $value');
  }
  return parsed;
}
