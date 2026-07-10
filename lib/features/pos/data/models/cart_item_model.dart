import 'package:mobileshop_saas/features/inventory/data/models/product_model.dart';

class CartItemModel {
  final String productId;
  final String productName;
  final String? productSku;
  final double unitPrice;
  final double? unitCost;
  final int quantity;
  final double discountAmount; // item level discount
  final double taxRate; // percentage (0-100)
  final int? availableStock;

  const CartItemModel({
    required this.productId,
    required this.productName,
    this.productSku,
    required this.unitPrice,
    this.unitCost,
    this.quantity = 1,
    this.discountAmount = 0,
    this.taxRate = 0,
    this.availableStock,
  });

  // ── Calculated Fields ──

  // Price after item discount
  double get discountedPrice => unitPrice - discountAmount;

  // Tax amount on this item
  double get taxAmount => discountedPrice * quantity * (taxRate / 100);

  // Final line total
  double get lineTotal => (discountedPrice * quantity) + taxAmount;

  bool get isAtStockLimit =>
      availableStock != null && quantity >= availableStock!;

  // ── Cart operations ──

  // Quantity badha do
  CartItemModel incrementQty() => copyWith(quantity: quantity + 1);

  // Quantity ghatao (min 1)
  CartItemModel decrementQty() =>
      copyWith(quantity: quantity > 1 ? quantity - 1 : 1);

  // Product se CartItem banao
  factory CartItemModel.fromProduct(ProductModel product) {
    return CartItemModel(
      productId: product.id,
      productName: product.name,
      productSku: product.sku,
      unitPrice: product.salePrice,
      unitCost: product.costPrice,
      availableStock: product.stock,
    );
  }

  // JSON (held cart ke liye)
  factory CartItemModel.fromMap(Map<String, dynamic> map) {
    return CartItemModel(
      productId: map['product_id'] as String,
      productName: map['product_name'] as String,
      productSku: map['product_sku'] as String?,
      unitPrice: (map['unit_price'] as num).toDouble(),
      unitCost:
          (map['unit_cost_at_sale'] as num?)?.toDouble() ??
          (map['unit_cost'] as num?)?.toDouble(),
      quantity: (map['quantity'] as num).toInt(),
      discountAmount: (map['discount_amount'] as num?)?.toDouble() ?? 0,
      taxRate: (map['tax_rate'] as num?)?.toDouble() ?? 0,
      availableStock: (map['available_stock'] as num?)?.toInt(),
    );
  }

  Map<String, dynamic> toMap() => {
    'product_id': productId,
    'product_name': productName,
    'product_sku': productSku,
    'unit_price': unitPrice,
    'unit_cost_at_sale': unitCost,
    'cogs_total': unitCost == null ? null : unitCost! * quantity,
    'quantity': quantity,
    'discount_amount': discountAmount,
    'tax_rate': taxRate,
    'line_total': lineTotal,
    'available_stock': availableStock,
  };

  CartItemModel copyWith({
    String? productId,
    String? productName,
    String? productSku,
    double? unitPrice,
    double? unitCost,
    int? quantity,
    double? discountAmount,
    double? taxRate,
    int? availableStock,
  }) {
    return CartItemModel(
      productId: productId ?? this.productId,
      productName: productName ?? this.productName,
      productSku: productSku ?? this.productSku,
      unitPrice: unitPrice ?? this.unitPrice,
      unitCost: unitCost ?? this.unitCost,
      quantity: quantity ?? this.quantity,
      discountAmount: discountAmount ?? this.discountAmount,
      taxRate: taxRate ?? this.taxRate,
      availableStock: availableStock ?? this.availableStock,
    );
  }
}
