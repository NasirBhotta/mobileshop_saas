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

  // ── Exact Unit Tracking (Used Phones & IMEI Serialized Devices) ──
  final String? imei;
  final String? deviceDetails; // e.g., specs, condition, color from description or buyin
  final String? unitId; // inventory_unit ID or customer_purchase ID

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
    this.imei,
    this.deviceDetails,
    this.unitId,
  });

  /// Unique key in cart: units with unique IMEI get unique cart key
  String get cartKey => (imei != null && imei!.isNotEmpty) ? '${productId}_$imei' : productId;

  /// True if this represents a unique serialized device / phone unit
  bool get isUnitItem => imei != null && imei!.isNotEmpty;

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

  // Quantity badha do (locked to 1 for unique serialized phone units)
  CartItemModel incrementQty() =>
      isUnitItem ? this : copyWith(quantity: quantity + 1);

  // Quantity ghatao (min 1)
  CartItemModel decrementQty() =>
      copyWith(quantity: quantity > 1 ? quantity - 1 : 1);

  // Product se CartItem banao
  factory CartItemModel.fromProduct(
    ProductModel product, {
    String? imei,
    String? deviceDetails,
    String? unitId,
  }) {
    return CartItemModel(
      productId: product.id,
      productName: product.name,
      productSku: product.sku,
      unitPrice: product.salePrice,
      unitCost: product.costPrice,
      availableStock: product.stock,
      imei: imei,
      deviceDetails: deviceDetails ??
          (product.description?.trim().isNotEmpty == true
              ? product.description!.trim()
              : null),
      unitId: unitId,
    );
  }

  // JSON (held cart ke liye & local SQLite storage)
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
      imei: map['imei'] as String?,
      deviceDetails: map['device_details'] as String?,
      unitId: map['unit_id'] as String?,
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
    'imei': imei,
    'device_details': deviceDetails,
    'unit_id': unitId,
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
    String? imei,
    String? deviceDetails,
    String? unitId,
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
      imei: imei ?? this.imei,
      deviceDetails: deviceDetails ?? this.deviceDetails,
      unitId: unitId ?? this.unitId,
    );
  }
}
