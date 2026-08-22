import 'dart:convert';

class CustomerPurchaseModel {
  final String id;
  final String tenantId;
  final String branchId;
  final String sellerName;
  final String sellerCnic;
  final String sellerPhone;
  final String? sellerAddress;
  final String? sellerPhotoUrl;
  final String? cnicFrontUrl;
  final String? cnicBackUrl;
  final String productId;
  final String productName;
  final String? categoryId;
  final String imei1;
  final String? imei2;
  final String? color;
  final String? storage;
  final String? deviceCondition;
  final String? accessories;
  final double purchasePrice;
  final double expectedSalePrice;
  final String? paymentAccountId;
  final String? paymentMethod;
  final String? notes;
  final bool declarationAgreed;
  final String status;
  final String createdBy;
  final DateTime createdAt;
  final DateTime? updatedAt;

  const CustomerPurchaseModel({
    required this.id,
    required this.tenantId,
    required this.branchId,
    required this.sellerName,
    required this.sellerCnic,
    required this.sellerPhone,
    this.sellerAddress,
    this.sellerPhotoUrl,
    this.cnicFrontUrl,
    this.cnicBackUrl,
    required this.productId,
    required this.productName,
    this.categoryId,
    required this.imei1,
    this.imei2,
    this.color,
    this.storage,
    this.deviceCondition,
    this.accessories,
    this.purchasePrice = 0.0,
    this.expectedSalePrice = 0.0,
    this.paymentAccountId,
    this.paymentMethod,
    this.notes,
    this.declarationAgreed = true,
    this.status = 'in_stock',
    required this.createdBy,
    required this.createdAt,
    this.updatedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'tenant_id': tenantId,
      'branch_id': branchId,
      'seller_name': sellerName,
      'seller_cnic': sellerCnic,
      'seller_phone': sellerPhone,
      'seller_address': sellerAddress,
      'seller_photo_url': sellerPhotoUrl,
      'cnic_front_url': cnicFrontUrl,
      'cnic_back_url': cnicBackUrl,
      'product_id': productId,
      'product_name': productName,
      'category_id': categoryId,
      'imei1': imei1,
      'imei2': imei2,
      'color': color,
      'storage': storage,
      'device_condition': deviceCondition,
      'accessories': accessories,
      'purchase_price': purchasePrice,
      'expected_sale_price': expectedSalePrice,
      'payment_account_id': paymentAccountId,
      'payment_method': paymentMethod,
      'notes': notes,
      'declaration_agreed': declarationAgreed ? 1 : 0,
      'status': status,
      'created_by': createdBy,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  factory CustomerPurchaseModel.fromMap(Map<String, dynamic> map) {
    return CustomerPurchaseModel(
      id: map['id']?.toString() ?? '',
      tenantId: map['tenant_id']?.toString() ?? '',
      branchId: map['branch_id']?.toString() ?? '',
      sellerName: map['seller_name']?.toString() ?? '',
      sellerCnic: map['seller_cnic']?.toString() ?? '',
      sellerPhone: map['seller_phone']?.toString() ?? '',
      sellerAddress: map['seller_address']?.toString(),
      sellerPhotoUrl: map['seller_photo_url']?.toString(),
      cnicFrontUrl: map['cnic_front_url']?.toString(),
      cnicBackUrl: map['cnic_back_url']?.toString(),
      productId: map['product_id']?.toString() ?? '',
      productName: map['product_name']?.toString() ?? '',
      categoryId: map['category_id']?.toString(),
      imei1: map['imei1']?.toString() ?? '',
      imei2: map['imei2']?.toString(),
      color: map['color']?.toString(),
      storage: map['storage']?.toString(),
      deviceCondition: map['device_condition']?.toString(),
      accessories: map['accessories']?.toString(),
      purchasePrice: (map['purchase_price'] as num?)?.toDouble() ?? 0.0,
      expectedSalePrice: (map['expected_sale_price'] as num?)?.toDouble() ?? 0.0,
      paymentAccountId: map['payment_account_id']?.toString(),
      paymentMethod: map['payment_method']?.toString(),
      notes: map['notes']?.toString(),
      declarationAgreed: map['declaration_agreed'] == 1 || map['declaration_agreed'] == true,
      status: map['status']?.toString() ?? 'in_stock',
      createdBy: map['created_by']?.toString() ?? '',
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
      updatedAt: map['updated_at'] != null
          ? DateTime.tryParse(map['updated_at'].toString())
          : null,
    );
  }

  CustomerPurchaseModel copyWith({
    String? id,
    String? tenantId,
    String? branchId,
    String? sellerName,
    String? sellerCnic,
    String? sellerPhone,
    String? sellerAddress,
    String? sellerPhotoUrl,
    String? cnicFrontUrl,
    String? cnicBackUrl,
    String? productId,
    String? productName,
    String? categoryId,
    String? imei1,
    String? imei2,
    String? color,
    String? storage,
    String? deviceCondition,
    String? accessories,
    double? purchasePrice,
    double? expectedSalePrice,
    String? paymentAccountId,
    String? paymentMethod,
    String? notes,
    bool? declarationAgreed,
    String? status,
    String? createdBy,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return CustomerPurchaseModel(
      id: id ?? this.id,
      tenantId: tenantId ?? this.tenantId,
      branchId: branchId ?? this.branchId,
      sellerName: sellerName ?? this.sellerName,
      sellerCnic: sellerCnic ?? this.sellerCnic,
      sellerPhone: sellerPhone ?? this.sellerPhone,
      sellerAddress: sellerAddress ?? this.sellerAddress,
      sellerPhotoUrl: sellerPhotoUrl ?? this.sellerPhotoUrl,
      cnicFrontUrl: cnicFrontUrl ?? this.cnicFrontUrl,
      cnicBackUrl: cnicBackUrl ?? this.cnicBackUrl,
      productId: productId ?? this.productId,
      productName: productName ?? this.productName,
      categoryId: categoryId ?? this.categoryId,
      imei1: imei1 ?? this.imei1,
      imei2: imei2 ?? this.imei2,
      color: color ?? this.color,
      storage: storage ?? this.storage,
      deviceCondition: deviceCondition ?? this.deviceCondition,
      accessories: accessories ?? this.accessories,
      purchasePrice: purchasePrice ?? this.purchasePrice,
      expectedSalePrice: expectedSalePrice ?? this.expectedSalePrice,
      paymentAccountId: paymentAccountId ?? this.paymentAccountId,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      notes: notes ?? this.notes,
      declarationAgreed: declarationAgreed ?? this.declarationAgreed,
      status: status ?? this.status,
      createdBy: createdBy ?? this.createdBy,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  String toJson() => jsonEncode(toMap());
  factory CustomerPurchaseModel.fromJson(String source) =>
      CustomerPurchaseModel.fromMap(jsonDecode(source) as Map<String, dynamic>);
}
