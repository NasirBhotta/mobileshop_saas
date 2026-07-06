import 'cart_item_model.dart';

class HeldCartModel {
  final String? id;
  final String branchId;
  final String userId;
  final String? label; // "Customer 1", "Walk-in" etc.
  final List<CartItemModel> items;
  final String? customerId;
  final String? customerName;
  final DateTime createdAt;
  final DateTime? expiresAt;

  const HeldCartModel({
    this.id,
    required this.branchId,
    required this.userId,
    this.label,
    required this.items,
    this.customerId,
    this.customerName,
    required this.createdAt,
    this.expiresAt,
  });

  factory HeldCartModel.fromMap(Map<String, dynamic> map) {
    final cartData = map['cart_data'] as Map<String, dynamic>;
    final itemsList = cartData['items'] as List<dynamic>? ?? [];

    return HeldCartModel(
      id: map['id'] as String?,
      branchId: map['branch_id'] as String,
      userId: map['user_id'] as String,
      label: map['label'] as String?,
      customerId: cartData['customer_id'] as String?,
      customerName: cartData['customer_name'] as String?,
      items:
          itemsList
              .map((e) => CartItemModel.fromMap(e as Map<String, dynamic>))
              .toList(),
      createdAt: DateTime.parse(map['created_at'] as String),
      expiresAt:
          map['expires_at'] != null
              ? DateTime.parse(map['expires_at'] as String)
              : null,
    );
  }

  // Cart ko JSON mein save karo (held_carts.cart_data)
  Map<String, dynamic> toCartData() => {
    'items': items.map((e) => e.toMap()).toList(),
    'customer_id': customerId,
    'customer_name': customerName,
  };
}
