class InventorySupplierOption {
  final String id;
  final String name;

  const InventorySupplierOption({required this.id, required this.name});

  factory InventorySupplierOption.fromMap(Map<String, dynamic> map) {
    return InventorySupplierOption(
      id: map['id'] as String,
      name: map['name'] as String,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is InventorySupplierOption && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
