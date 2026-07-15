import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:mobileshop_saas/features/inventory/data/models/csv_import_model.dart';
import 'package:mobileshop_saas/features/inventory/data/repositories/inventory_repository.dart';
import 'package:mobileshop_saas/features/inventory/presentation/providers/inventory_provider.dart';
import 'package:csv/csv.dart';
import 'package:mobileshop_saas/core/entitlements/entitlement_provider.dart';
import 'package:mobileshop_saas/features/inventory/domain/inventory_entitlement_gate.dart';

final csvImportControllerProvider =
    StateNotifierProvider<CsvImportController, AsyncValue<void>>((ref) {
      return CsvImportController(ref.read(inventoryRepositoryProvider), ref);
    });
final csvImportResultProvider = StateProvider<CsvImportResult?>((ref) => null);
final csvImportProgressProvider = StateProvider<CsvImportProgress?>(
  (ref) => null,
);

class CsvImportController extends StateNotifier<AsyncValue<void>> {
  final InventoryRepository _inventoryRepository;
  final Ref _ref;

  CsvImportController(this._inventoryRepository, this._ref)
    : super(const AsyncData(null));

  Future<void> pickAndImport() async {
    state = const AsyncLoading();
    try {
      await InventoryEntitlementGate(
        _ref.read(entitlementEvaluatorProvider),
      ).require('inventory.csv_import');
      _ref.read(csvImportResultProvider.notifier).state = null;
      _ref
          .read(csvImportProgressProvider.notifier)
          .state = const CsvImportProgress(
        totalRows: 0,
        processedRows: 0,
        successCount: 0,
        failedCount: 0,
        currentBatch: 0,
        totalBatches: 0,
        message: 'CSV file select kar rahe hain...',
      );

      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
        withData: true, // file content memory mein load karo
      );
      if (result == null || result.files.isEmpty) {
        _ref.read(csvImportProgressProvider.notifier).state = null;
        state = const AsyncData(null);
        return;
      }

      final bytes = result.files.first.bytes;
      if (bytes == null) {
        throw Exception('FIle is not being loaded into memory');
      }

      final csvString = String.fromCharCodes(bytes);

      final rows = Csv().decoder.convert(csvString);
      if (rows.isEmpty) throw Exception('CSV file is empty');

      final importResult = await _inventoryRepository.importFromCsv(
        rows,
        onProgress:
            (progress) =>
                _ref.read(csvImportProgressProvider.notifier).state = progress,
      );
      _ref.read(csvImportResultProvider.notifier).state = importResult;
      _ref.read(csvImportProgressProvider.notifier).state = null;

      // 6. Products refresh karo
      invalidateProductListProviders(_ref);
      _ref.invalidate(categoriesProvider);

      state = const AsyncData(null);
    } catch (e) {
      _ref.read(csvImportProgressProvider.notifier).state = null;
      state = AsyncError(e, StackTrace.current);
    }
  }

  String generateTemplate() {
    const headers = [
      'name',
      'sku',
      'sale_price',
      'cost_price',
      'category',
      'quantity',
    ];

    const exampleRow = [
      'Samsung Galaxy A15',
      'SAM-A15-BLK',
      '45000',
      '38000',
      'Mobile Phones',
      '10',
    ];

    final rows = [headers, exampleRow];
    return Csv().encoder.convert(rows);
  }
}
