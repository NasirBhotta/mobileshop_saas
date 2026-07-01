class ShopSetupModel {
  final String shopName;
  final String city;
  final String address;
  final String businessType;
  final int branchCount;

  const ShopSetupModel({
    this.shopName = '',
    this.city = '',
    this.address = '',
    this.businessType = '',
    this.branchCount = 1,
  });

  ShopSetupModel copyWith({
    String? shopName,
    String? city,
    String? address,
    String? businessType,
    int? branchCount,
  }) {
    return ShopSetupModel(
      shopName: shopName ?? this.shopName,
      city: city ?? this.city,
      address: address ?? this.address,
      businessType: businessType ?? this.businessType,
      branchCount: branchCount ?? this.branchCount,
    );
  }
}
