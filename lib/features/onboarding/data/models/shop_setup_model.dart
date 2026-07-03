class BranchInputModel {
  final String? id;
  final String name;
  final String address;
  final String city;

  const BranchInputModel({
    this.id,
    this.name = '',
    this.address = '',
    this.city = '',
  });

  BranchInputModel copyWith({
    String? id,
    String? name,
    String? address,
    String? city,
  }) {
    return BranchInputModel(
      id: id ?? this.id,
      name: name ?? this.name,
      address: address ?? this.address,
      city: city ?? this.city,
    );
  }

  factory BranchInputModel.fromMap(Map<String, dynamic> map) {
    return BranchInputModel(
      id: map['id'] as String?,
      name: (map['name'] as String?) ?? '',
      address: (map['address'] as String?) ?? '',
      city: (map['city'] as String?) ?? '',
    );
  }

  Map<String, dynamic> toCacheMap() => {
    'id': id,
    'name': name,
    'address': address,
    'city': city,
  };
}

class ShopSetupModel {
  final String shopName; // tenant group naam
  final String city;
  final String address;
  final String businessType;
  final int branchCount;
  final List<BranchInputModel> branches; // ← new

  const ShopSetupModel({
    this.shopName = '',
    this.city = '',
    this.address = '',
    this.businessType = '',
    this.branchCount = 1,
    this.branches = const [], // ← new
  });

  ShopSetupModel copyWith({
    String? shopName,
    String? city,
    String? address,
    String? businessType,
    int? branchCount,
    List<BranchInputModel>? branches,
  }) {
    return ShopSetupModel(
      shopName: shopName ?? this.shopName,
      city: city ?? this.city,
      address: address ?? this.address,
      businessType: businessType ?? this.businessType,
      branchCount: branchCount ?? this.branchCount,
      branches: branches ?? this.branches,
    );
  }
}
