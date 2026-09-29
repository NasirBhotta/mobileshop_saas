import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobileshop_saas/core/local/local_database.dart';
import 'package:mobileshop_saas/core/local/local_store.dart';
import 'package:mobileshop_saas/core/offline/offline_store.dart';
import 'package:mobileshop_saas/features/pos/data/models/customer_model.dart';

const _pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory databaseDirectory;

  setUpAll(() async {
    databaseDirectory = Directory.systemTemp.createTempSync('customer-multibranch-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathProviderChannel, (call) async {
          if (call.method == 'getApplicationSupportDirectory') {
            return databaseDirectory.path;
          }
          return null;
        });
    await LocalDatabase.initialize();
  });

  setUp(() async {
    await LocalDatabase.clearAllTables();
  });

  tearDownAll(() async {
    try {
      databaseDirectory.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('loadCustomers with tenantId returns customers across all branches of the tenant', () async {
    const tenantId = 'tenant-test-123';
    const branch1 = 'branch-main-bazar';
    const branch2 = 'branch-gandy-nala';

    final customerAmir = CustomerModel(
      id: 'cust-amir',
      tenantId: tenantId,
      branchId: branch1,
      fullName: 'amir',
      phone: '03448002467',
      outstandingBalance: 5100,
      createdAt: DateTime.now(),
    );

    final customerAli = CustomerModel(
      id: 'cust-ali',
      tenantId: tenantId,
      branchId: branch2,
      fullName: 'ali muhammad',
      phone: '0315789469',
      outstandingBalance: 500,
      createdAt: DateTime.now(),
    );

    // Save both customers locally
    await LocalStore.saveCustomer(customerAmir);
    await LocalStore.saveCustomer(customerAli);

    // When loading by tenantId, both Amir and Ali Muhammad must be returned
    final tenantCustomers = await OfflineStore.loadCustomers(
      tenantId: tenantId,
    );

    expect(tenantCustomers.length, 2);
    final names = tenantCustomers.map((c) => c.fullName).toList();
    expect(names, contains('amir'));
    expect(names, contains('ali muhammad'));

    // Searching across tenant
    final searchAmir = await OfflineStore.searchCustomers(
      tenantId: tenantId,
      query: 'amir',
    );
    expect(searchAmir.length, 1);
    expect(searchAmir.first.fullName, 'amir');

    final searchAli = await OfflineStore.searchCustomers(
      tenantId: tenantId,
      query: 'ali',
    );
    expect(searchAli.length, 1);
    expect(searchAli.first.fullName, 'ali muhammad');
  });
}
