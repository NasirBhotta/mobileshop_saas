import 'package:flutter_test/flutter_test.dart';
import 'package:mobileshop_saas/core/extensions/repair_ticket_ext.dart';
import 'package:mobileshop_saas/features/dashboard/presentation/providers/dashboard_provider.dart';
import 'package:mobileshop_saas/features/repairs/data/models/repair_ticket_model.dart';

void main() {
  RepairTicketModel ticket(
    String id,
    RepairTicketStatus status, {
    DateTime? due,
    DateTime? completedAt,
  }) {
    return RepairTicketModel(
      id: id,
      tenantId: 'tenant',
      branchId: 'branch',
      customerName: 'Customer',
      deviceBrand: 'Brand',
      deviceModel: 'Model',
      faultDescription: 'Fault',
      status: status,
      estimatedCompletionAt: due,
      completedAt: completedAt,
      createdBy: 'owner',
    );
  }

  test('completed undelivered is first, due dates sort, no date is last', () {
    final now = DateTime(2026, 7, 21, 12);
    final result = selectPriorityRepairTickets([
      ticket('no-date', RepairTicketStatus.received),
      ticket(
        'later',
        RepairTicketStatus.inProgress,
        due: now.add(const Duration(days: 2)),
      ),
      ticket('ready', RepairTicketStatus.completed, completedAt: now),
      ticket(
        'near',
        RepairTicketStatus.diagnosed,
        due: now.add(const Duration(hours: 2)),
      ),
      ticket('delivered', RepairTicketStatus.delivered, due: now),
      ticket('cancelled', RepairTicketStatus.cancelled, due: now),
    ]);

    expect(result.map((item) => item.id), [
      'ready',
      'near',
      'later',
      'no-date',
    ]);
  });

  test('dashboard priority list is limited', () {
    final result = selectPriorityRepairTickets(
      List.generate(
        8,
        (index) => ticket('$index', RepairTicketStatus.received),
      ),
    );

    expect(result, hasLength(5));
  });
}
