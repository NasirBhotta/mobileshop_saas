import 'customer_model.dart';
import 'sale_model.dart';

class CustomerSettlementModel {
  final String id;
  final String customerId;
  final String branchId;
  final String userId;
  final double amount;
  final String method;
  final String? accountId;
  final String? ledgerTransactionId;
  final String? notes;
  final String? syncError;
  final DateTime createdAt;

  const CustomerSettlementModel({
    required this.id,
    required this.customerId,
    required this.branchId,
    required this.userId,
    required this.amount,
    required this.method,
    this.accountId,
    this.ledgerTransactionId,
    this.notes,
    this.syncError,
    required this.createdAt,
  });

  factory CustomerSettlementModel.fromMap(Map<String, dynamic> map) {
    return CustomerSettlementModel(
      id: map['id'] as String,
      customerId: map['customer_id'] as String,
      branchId: map['branch_id'] as String,
      userId: map['user_id'] as String,
      amount: (map['amount'] as num).toDouble(),
      method: map['method'] as String,
      accountId: map['account_id'] as String?,
      ledgerTransactionId: map['ledger_transaction_id'] as String?,
      notes: map['notes'] as String?,
      syncError: map['sync_error'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}

enum CustomerLedgerEntryType { charge, credit }

class CustomerLedgerEntryModel {
  final String id;
  final String customerId;
  final String branchId;
  final String userId;
  final CustomerLedgerEntryType type;
  final double amount;
  final String reason;
  final DateTime createdAt;

  const CustomerLedgerEntryModel({
    required this.id,
    required this.customerId,
    required this.branchId,
    required this.userId,
    required this.type,
    required this.amount,
    required this.reason,
    required this.createdAt,
  });

  double get outstandingDelta =>
      type == CustomerLedgerEntryType.charge ? amount : -amount;

  factory CustomerLedgerEntryModel.fromMap(Map<String, dynamic> map) {
    return CustomerLedgerEntryModel(
      id: map['id'] as String,
      customerId: map['customer_id'] as String,
      branchId: map['branch_id'] as String,
      userId: map['user_id'] as String,
      type: CustomerLedgerEntryType.values.byName(map['entry_type'] as String),
      amount: (map['amount'] as num).toDouble(),
      reason: map['reason'] as String,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'customer_id': customerId,
    'branch_id': branchId,
    'user_id': userId,
    'entry_type': type.name,
    'amount': amount,
    'reason': reason,
    'created_at': createdAt.toIso8601String(),
  };
}

class CustomerDashboardModel {
  final CustomerModel customer;
  final double lifetimeValue;
  final double outstandingDues;
  final int activeRepairTickets;
  final List<SaleModel> purchases;
  final List<CustomerSettlementModel> settlements;
  final List<CustomerLedgerEntryModel> ledgerEntries;
  final bool syncPending;

  const CustomerDashboardModel({
    required this.customer,
    required this.lifetimeValue,
    required this.outstandingDues,
    required this.activeRepairTickets,
    this.purchases = const [],
    this.settlements = const [],
    this.ledgerEntries = const [],
    this.syncPending = false,
  });
}
