import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobileshop_saas/features/pos/data/models/customer_model.dart';
import 'package:mobileshop_saas/features/pos/data/repositories/pos_repository.dart';
import 'package:mobileshop_saas/features/pos/presentation/providers/pos_provider.dart';
import 'package:mobileshop_saas/features/pos/presentation/widgets/customer_attach_sheet.dart';

const customer = CustomerModel(
  id: 'customer',
  tenantId: 'tenant',
  branchId: 'branch',
  fullName: 'Ali',
  phone: '03001234567',
);

class FakeCustomers extends Fake implements PosRepository {
  int creations = 0;
  @override
  Future<CustomerModel> addCustomer({
    required String fullName,
    String? phone,
    String? email,
    String? notes,
    double? creditLimit,
  }) async {
    creations++;
    return customer;
  }
}

void main() {
  for (final create in [false, true]) {
    testWidgets(
      '${create ? 'create' : 'select'} returns real customer ID without modifying POS cart',
      (tester) async {
        final repository = FakeCustomers();
        final container = ProviderContainer(
          overrides: [
            posRepositoryProvider.overrideWithValue(repository),
            customerSearchProvider(
              'Ali',
            ).overrideWith((ref) async => [customer]),
          ],
        );
        addTearDown(container.dispose);
        CustomerModel? selected;
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              home: Consumer(
                builder:
                    (context, ref, _) => Scaffold(
                      body: TextButton(
                        child: const Text('Open'),
                        onPressed:
                            () => showModalBottomSheet<void>(
                              context: context,
                              isScrollControlled: true,
                              builder:
                                  (_) => CustomerAttachSheet(
                                    ref: ref,
                                    startWithAdd: create,
                                    onSelected: (c) => selected = c,
                                  ),
                            ),
                      ),
                    ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField).first, 'Ali');
        await tester.pumpAndSettle();
        if (create) {
          await tester.tap(find.text('Add & Attach'));
        } else {
          await tester.tap(find.text('Ali').last);
        }
        await tester.pumpAndSettle();
        expect(selected?.id, 'customer');
        expect(container.read(cartProvider).customer, isNull);
        expect(repository.creations, create ? 1 : 0);
      },
    );
  }
}
