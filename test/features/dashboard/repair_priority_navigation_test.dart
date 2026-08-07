import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobileshop_saas/core/extensions/repair_ticket_ext.dart';
import 'package:mobileshop_saas/features/repairs/data/models/repair_ticket_model.dart';
import 'package:mobileshop_saas/features/repairs/presentation/screens/repairs_list_screen.dart';

void main() {
  test('repairs screen accepts an exact priority ticket target', () {
    const ticket = RepairTicketModel(
      id: 'priority-ticket',
      tenantId: 'tenant',
      branchId: 'branch',
      customerName: 'Customer',
      deviceBrand: 'Brand',
      deviceModel: 'Model',
      faultDescription: 'Fault',
      status: RepairTicketStatus.inProgress,
      createdBy: 'owner',
    );

    const screen = RepairsListScreen(
      initialTicket: ticket,
      initialTicketId: 'priority-ticket',
    );

    expect(screen.initialTicket, same(ticket));
    expect(screen.initialTicketId, ticket.id);
  });

  test('dashboard priority tile carries ticket id and model', () {
    final dashboard =
        File(
          'lib/features/dashboard/presentation/screens/dashboard_screen.dart',
        ).readAsStringSync();

    expect(dashboard, contains("queryParameters: {'ticket': ticket.id}"));
    expect(dashboard, contains('extra: ticket'));
  });
}
