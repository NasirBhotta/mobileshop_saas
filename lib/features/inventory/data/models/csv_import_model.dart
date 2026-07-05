// Ek row ka result
class CsvRowResult {
  final int rowNumber; // CSV mein kaun si row thi
  final String? name; // product naam
  final String? sku; // SKU
  final bool isSuccess; // import hua ya nahi
  final String? errorReason; // agar reject hua → kyon

  const CsvRowResult({
    required this.rowNumber,
    this.name,
    this.sku,
    required this.isSuccess,
    this.errorReason,
  });
}

// Poore import ka summary
class CsvImportResult {
  final int totalRows; // kitni rows thi CSV mein
  final int successCount; // kitni import huin
  final int failedCount; // kitni reject huin
  final List<CsvRowResult> rows; // har row ka detail

  const CsvImportResult({
    required this.totalRows,
    required this.successCount,
    required this.failedCount,
    required this.rows,
  });

  // Sirf failed rows
  List<CsvRowResult> get failedRows => rows.where((r) => !r.isSuccess).toList();

  // Sirf successful rows
  List<CsvRowResult> get successRows => rows.where((r) => r.isSuccess).toList();
}
