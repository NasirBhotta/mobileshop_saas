class CustomerActivityPage {
  final List<Map<String, dynamic>> entries;
  final Map<String, dynamic> totals;
  final bool cached;

  const CustomerActivityPage(this.entries, this.totals, {this.cached = false});

  factory CustomerActivityPage.fromMap(
    Map<String, dynamic> map, {
    bool cached = false,
  }) => CustomerActivityPage(
    (map['entries'] as List? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList(),
    map,
    cached: cached,
  );

  double amount(String key) => (totals[key] as num? ?? 0).toDouble();
  int get count => (totals['count'] as num? ?? 0).toInt();
}
