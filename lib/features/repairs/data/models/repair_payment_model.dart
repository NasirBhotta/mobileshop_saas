class RepairPaymentModel {
  final String id;
  final String tenantId;
  final String branchId;
  final String ticketId;
  final double amount;
  final String method;
  final String accountId;
  final String ledgerTransactionId;
  final String? note;
  final String receivedBy;
  final DateTime receivedAt;
  final DateTime createdAt;

  const RepairPaymentModel({
    required this.id,
    required this.tenantId,
    required this.branchId,
    required this.ticketId,
    required this.amount,
    required this.method,
    required this.accountId,
    required this.ledgerTransactionId,
    required this.receivedBy,
    required this.receivedAt,
    required this.createdAt,
    this.note,
  });

  factory RepairPaymentModel.fromMap(Map<String, dynamic> map) {
    return RepairPaymentModel(
      id: map['id'] as String,
      tenantId: map['tenant_id'] as String,
      branchId: map['branch_id'] as String,
      ticketId: map['ticket_id'] as String,
      amount: (map['amount'] as num).toDouble(),
      method: map['method'] as String,
      accountId: map['account_id'] as String,
      ledgerTransactionId: map['ledger_transaction_id'] as String,
      note: map['note'] as String?,
      receivedBy: map['received_by'] as String,
      receivedAt: DateTime.parse(map['received_at'].toString()),
      createdAt: DateTime.parse(map['created_at'].toString()),
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'tenant_id': tenantId,
    'branch_id': branchId,
    'ticket_id': ticketId,
    'amount': amount,
    'method': method,
    'account_id': accountId,
    'ledger_transaction_id': ledgerTransactionId,
    'note': note,
    'received_by': receivedBy,
    'received_at': receivedAt.toIso8601String(),
    'created_at': createdAt.toIso8601String(),
  };
}
