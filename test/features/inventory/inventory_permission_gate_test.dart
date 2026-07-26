import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('inventory module and navigation use branch-aware view permission', () {
    final screen =
        File(
          'lib/features/inventory/presentation/screens/inventory_screen.dart',
        ).readAsStringSync();
    final desktop =
        File('lib/shared/widgets/desktop_nav.dart').readAsStringSync();
    final mobile =
        File('lib/shared/widgets/mobile_nav.dart').readAsStringSync();

    for (final source in [screen, desktop, mobile]) {
      expect(
        source,
        contains("branchAwarePermissionProvider('inventory.product.view')"),
      );
    }
    expect(screen, contains("moduleName: 'Inventory'"));
  });

  test('inventory actions use canonical branch-aware permissions', () {
    final inventory =
        File(
          'lib/features/inventory/presentation/screens/inventory_screen.dart',
        ).readAsStringSync();
    final categories =
        File(
          'lib/features/inventory/presentation/screens/categories_screen.dart',
        ).readAsStringSync();
    final router = File('lib/config/router/app_router.dart').readAsStringSync();

    expect(inventory, contains("'inventory.product.create'"));
    expect(inventory, contains("'inventory.product.update'"));
    expect(inventory, contains("'inventory.category.view'"));
    expect(inventory, contains("'inventory.stock.adjust'"));
    expect(categories, contains("'inventory.category.manage'"));

    expect(router, contains("permissionKey: 'inventory.product.create'"));
    expect(router, contains("permissionKey: 'inventory.product.update'"));
    expect(router, contains("permissionKey: 'inventory.category.view'"));
    expect(router, contains("permissionKey: 'inventory.stock.adjust'"));
  });

  test('inventory entitlement checks remain in place', () {
    final inventory =
        File(
          'lib/features/inventory/presentation/screens/inventory_screen.dart',
        ).readAsStringSync();
    final productCard =
        File(
          'lib/features/inventory/presentation/widgets/product_card.dart',
        ).readAsStringSync();

    expect(inventory, contains("'inventory.csv_import'"));
    expect(inventory, contains("'inventory.bulk_pricing'"));
    expect(productCard, contains("'inventory.stock_adjustments'"));
  });
}
