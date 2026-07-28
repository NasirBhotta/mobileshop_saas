import 'package:mobileshop_saas/core/extensions/repair_ticket_ext.dart';

enum RepairPartSource { inventory, directPurchase }

enum RepairFinancialEvent {
  ticketCreated,
  ticketCompleted,
  paymentReceived,
  ticketDelivered,
  preCompletionCancellation,
  completedCancellation,
  ticketArchived,
}

class RepairAccountingEffect {
  final int inventoryDirection;
  final int revenueDirection;
  final int directCostDirection;
  final int receivableDirection;
  final int moneyDirection;

  const RepairAccountingEffect({
    required this.inventoryDirection,
    required this.revenueDirection,
    required this.directCostDirection,
    required this.receivableDirection,
    required this.moneyDirection,
  });
}

abstract final class RepairAccountingContract {
  static const effects = <RepairFinancialEvent, RepairAccountingEffect>{
    RepairFinancialEvent.ticketCreated: RepairAccountingEffect(
      inventoryDirection: 0,
      revenueDirection: 0,
      directCostDirection: 0,
      receivableDirection: 0,
      moneyDirection: 0,
    ),
    RepairFinancialEvent.ticketCompleted: RepairAccountingEffect(
      inventoryDirection: -1,
      revenueDirection: 1,
      directCostDirection: 1,
      receivableDirection: 1,
      moneyDirection: 0,
    ),
    RepairFinancialEvent.paymentReceived: RepairAccountingEffect(
      inventoryDirection: 0,
      revenueDirection: 0,
      directCostDirection: 0,
      receivableDirection: -1,
      moneyDirection: 1,
    ),
    RepairFinancialEvent.ticketDelivered: RepairAccountingEffect(
      inventoryDirection: 0,
      revenueDirection: 0,
      directCostDirection: 0,
      receivableDirection: 0,
      moneyDirection: 0,
    ),
    RepairFinancialEvent.preCompletionCancellation: RepairAccountingEffect(
      inventoryDirection: 0,
      revenueDirection: 0,
      directCostDirection: 0,
      receivableDirection: 0,
      moneyDirection: 0,
    ),
    RepairFinancialEvent.completedCancellation: RepairAccountingEffect(
      inventoryDirection: 1,
      revenueDirection: -1,
      directCostDirection: -1,
      receivableDirection: -1,
      moneyDirection: 0,
    ),
    RepairFinancialEvent.ticketArchived: RepairAccountingEffect(
      inventoryDirection: 0,
      revenueDirection: 0,
      directCostDirection: 0,
      receivableDirection: 0,
      moneyDirection: 0,
    ),
  };

  static bool isFinanciallyFinalized(RepairTicketStatus status) =>
      status == RepairTicketStatus.completed ||
      status == RepairTicketStatus.delivered;

  static bool requiresCompensatingReversal({
    required RepairTicketStatus currentStatus,
    required RepairTicketStatus nextStatus,
  }) =>
      nextStatus == RepairTicketStatus.cancelled &&
      isFinanciallyFinalized(currentStatus);

  static bool mayDeliver(RepairTicketStatus status) =>
      status == RepairTicketStatus.completed;

  static bool mayHardDelete({required bool hasEverHadFinancialEffect}) =>
      !hasEverHadFinancialEffect;

  static double grossProfit({
    required double customerCharge,
    required double inventoryPartsCost,
    required double directPartsCost,
    double perJobCommission = 0,
    double otherDirectCost = 0,
  }) =>
      customerCharge -
      inventoryPartsCost -
      directPartsCost -
      perJobCommission -
      otherDirectCost;
}
