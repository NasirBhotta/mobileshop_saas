import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobileshop_saas/features/inventory/presentation/providers/inventory_provider.dart';

void main() {
  test('supplier participates in paged inventory request identity', () {
    const all = InventoryProductsRequest(query: 'keypad');
    const supplierA = InventoryProductsRequest(
      query: 'keypad',
      supplierId: 'supplier-a',
    );
    const supplierB = InventoryProductsRequest(
      query: 'keypad',
      supplierId: 'supplier-b',
    );

    expect(all, isNot(supplierA));
    expect(supplierA, isNot(supplierB));
    expect(supplierA.hashCode, isNot(supplierB.hashCode));
  });

  test('supplier filter is server-side and preserves inventory controls', () {
    final repository = File(
      'lib/features/inventory/data/repositories/inventory_repository.dart',
    ).readAsStringSync();
    final screen = File(
      'lib/features/inventory/presentation/screens/inventory_screen.dart',
    ).readAsStringSync();
    final migration = File(
      'supabase/migrations/20260808000100_supplier_inventory_filter.sql',
    ).readAsStringSync();

    expect(repository, contains(".eq('supplier_id', supplierId)"));
    expect(repository, contains('categoryId: categoryId'));
    expect(repository, contains('queryText: normalizedQuery'));
    expect(repository, contains('lowStockOnly: lowStockOnly'));
    expect(screen, contains("Text('All suppliers')"));
    expect(screen, contains('supplierId: _selectedSupplierId'));
    expect(migration, contains('security_invoker = true'));
    expect(migration, contains('supplier_products'));
  });
}
