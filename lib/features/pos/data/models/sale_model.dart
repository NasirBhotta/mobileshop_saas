import 'cart_item_model.dart';
import 'sale_payment_model.dart';

// Sale status
enum SaleStatus { completed, held, voided }

extension SaleStatusX on SaleStatus {
  String get code {
    switch (this) {
      case SaleStatus.completed:
        return 'completed';
      case SaleStatus.held:
        return 'held';
      case SaleStatus.voided:
        return 'voided';
    }
  }

  static SaleStatus fromCode(String code) {
    switch (code) {
      case 'held':
        return SaleStatus.held;
      case 'voided':
        return SaleStatus.voided;
      default:
        return SaleStatus.completed;
    }
  }
}

class SaleModel {
  final String? id;
  final String branchId;
  final String? customerId;
  final String? customerName;
  final String userId;
  final SaleStatus status;
  final double subtotal;
  final double discountAmount;
  final double taxAmount;
  final double total;
  final String? notes;
  final String? voidReason;
  final List<CartItemModel> items;
  final List<SalePaymentModel> payments;
  final DateTime? createdAt;

  const SaleModel({
    this.id,
    required this.branchId,
    this.customerId,
    this.customerName,
    required this.userId,
    this.status = SaleStatus.completed,
    required this.subtotal,
    required this.discountAmount,
    required this.taxAmount,
    required this.total,
    this.notes,
    this.voidReason,
    this.items = const [],
    this.payments = const [],
    this.createdAt,
  });

  factory SaleModel.fromMap(Map<String, dynamic> map) {
    final customer = map['customers'] as Map<String, dynamic>?;

    final itemsList = map['sale_items'] as List<dynamic>? ?? [];
    final paymentsList = map['sale_payments'] as List<dynamic>? ?? [];

    return SaleModel(
      id: map['id'] as String?,
      branchId: map['branch_id'] as String,
      customerId: map['customer_id'] as String?,
      customerName: customer?['full_name'] as String?,
      userId: map['user_id'] as String,
      status: SaleStatusX.fromCode(map['status'] as String),
      subtotal: (map['subtotal'] as num).toDouble(),
      discountAmount: (map['discount_amount'] as num).toDouble(),
      taxAmount: (map['tax_amount'] as num).toDouble(),
      total: (map['total'] as num).toDouble(),
      notes: map['notes'] as String?,
      voidReason: map['void_reason'] as String?,
      items:
          itemsList
              .map((e) => CartItemModel.fromMap(e as Map<String, dynamic>))
              .toList(),
      payments:
          paymentsList
              .map((e) => SalePaymentModel.fromMap(e as Map<String, dynamic>))
              .toList(),
      createdAt:
          map['created_at'] != null
              ? DateTime.parse(map['created_at'] as String)
              : null,
    );
  }
}
