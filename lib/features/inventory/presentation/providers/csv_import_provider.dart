import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:mobileshop_saas/features/inventory/data/models/csv_import_model.dart';
import 'package:mobileshop_saas/features/inventory/data/repositories/inventory_repository.dart';
import 'package:mobileshop_saas/features/inventory/presentation/providers/inventory_provider.dart';
import 'package:csv/csv.dart';

final csvImportControllerProvider =
    StateNotifierProvider<CsvImportController, AsyncValue<void>>((ref) {
      return CsvImportController(ref.read(inventoryRepositoryProvider), ref);
    });
final csvImportResultProvider = StateProvider<CsvImportResult?>((ref) => null);

class CsvImportController extends StateNotifier<AsyncValue<void>> {
  final InventoryRepository _inventoryRepository;
  final Ref _ref;

  CsvImportController(this._inventoryRepository, this._ref)
    : super(const AsyncData(null));

  Future<void> pickAndImport() async {
    state = const AsyncLoading();
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
        withData: true, // file content memory mein load karo
      );
      if (result == null || result.files.isEmpty) {
        state = const AsyncData(null);
        return;
      }

      final bytes = result.files.first.bytes;
      if (bytes == null)
        throw Exception('FIle is not being loaded into memory');

      final csvString = String.fromCharCodes(bytes);

      final rows = Csv().decoder.convert(csvString);
      if (rows.isEmpty) throw Exception('CSV file empty hai');

      final importResult = await _inventoryRepository.importFromCsv(rows);
      _ref.read(csvImportResultProvider.notifier).state = importResult;

      // 6. Products refresh karo
      _ref.invalidate(productsProvider);
      _ref.invalidate(allProductsProvider);

      state = const AsyncData(null);
    } catch (e) {
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
