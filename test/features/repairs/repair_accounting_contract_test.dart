import 'package:flutter_test/flutter_test.dart';
import 'package:mobileshop_saas/core/extensions/repair_ticket_ext.dart';
import 'package:mobileshop_saas/features/repairs/domain/repair_accounting_contract.dart';

void main() {
  test('completion recognizes economics but never moves money', () {
    final effect =
        RepairAccountingContract.effects[RepairFinancialEvent.ticketCompleted]!;
    expect(effect.inventoryDirection, -1);
    expect(effect.revenueDirection, 1);
    expect(effect.directCostDirection, 1);
    expect(effect.receivableDirection, 1);
    expect(effect.moneyDirection, 0);
  });

  test('only payment moves a money account', () {
    final effect =
        RepairAccountingContract.effects[RepairFinancialEvent.paymentReceived]!;
    expect(effect.inventoryDirection, 0);
    expect(effect.revenueDirection, 0);
    expect(effect.moneyDirection, 1);
  });

  test('completed cancellation requires a compensating reversal', () {
    expect(
      RepairAccountingContract.requiresCompensatingReversal(
        currentStatus: RepairTicketStatus.completed,
        nextStatus: RepairTicketStatus.cancelled,
      ),
      isTrue,
    );
    expect(
      RepairAccountingContract.requiresCompensatingReversal(
        currentStatus: RepairTicketStatus.received,
        nextStatus: RepairTicketStatus.cancelled,
      ),
      isFalse,
    );
  });

  test('delivery is completion-only and has no second financial effect', () {
    expect(
      RepairAccountingContract.mayDeliver(RepairTicketStatus.completed),
      isTrue,
    );
    expect(
      RepairAccountingContract.mayDeliver(RepairTicketStatus.received),
      isFalse,
    );
    final effect =
        RepairAccountingContract.effects[RepairFinancialEvent.ticketDelivered]!;
    expect(effect.inventoryDirection, 0);
    expect(effect.revenueDirection, 0);
    expect(effect.moneyDirection, 0);
  });

  test('financial history cannot be hard deleted', () {
    expect(
      RepairAccountingContract.mayHardDelete(hasEverHadFinancialEffect: true),
      isFalse,
    );
    expect(
      RepairAccountingContract.mayHardDelete(hasEverHadFinancialEffect: false),
      isTrue,
    );
  });

  test('hybrid profit uses snapshots from both part sources', () {
    expect(
      RepairAccountingContract.grossProfit(
        customerCharge: 10000,
        inventoryPartsCost: 4000,
        directPartsCost: 1000,
        perJobCommission: 500,
      ),
      4500,
    );
  });
}
