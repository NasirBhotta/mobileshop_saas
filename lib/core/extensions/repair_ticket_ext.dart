enum RepairTicketStatus {
  received,
  diagnosed,
  inProgress,
  waitingPart,
  completed,
  delivered,
  cancelled,
}

extension RepairTicketStatusX on RepairTicketStatus {
  String get code {
    switch (this) {
      case RepairTicketStatus.received:
        return 'received';
      case RepairTicketStatus.diagnosed:
        return 'diagnosed';
      case RepairTicketStatus.inProgress:
        return 'in_progress';
      case RepairTicketStatus.waitingPart:
        return 'waiting_part';
      case RepairTicketStatus.completed:
        return 'completed';
      case RepairTicketStatus.delivered:
        return 'delivered';
      case RepairTicketStatus.cancelled:
        return 'cancelled';
    }
  }

  String get label {
    switch (this) {
      case RepairTicketStatus.received:
        return 'Received';
      case RepairTicketStatus.diagnosed:
        return 'Diagnosed';
      case RepairTicketStatus.inProgress:
        return 'In Progress';
      case RepairTicketStatus.waitingPart:
        return 'Waiting Part';
      case RepairTicketStatus.completed:
        return 'Completed';
      case RepairTicketStatus.delivered:
        return 'Delivered';
      case RepairTicketStatus.cancelled:
        return 'Cancelled';
    }
  }

  static RepairTicketStatus fromCode(String? code) {
    switch (code) {
      case 'received':
        return RepairTicketStatus.received;
      case 'diagnosed':
        return RepairTicketStatus.diagnosed;
      case 'in_progress':
        return RepairTicketStatus.inProgress;
      case 'waiting_part':
        return RepairTicketStatus.waitingPart;
      case 'completed':
        return RepairTicketStatus.completed;
      case 'delivered':
        return RepairTicketStatus.delivered;
      case 'cancelled':
        return RepairTicketStatus.cancelled;
      default:
        return RepairTicketStatus.received;
    }
  }

  bool canMoveTo(RepairTicketStatus next) {
    if (this == RepairTicketStatus.cancelled) return false;
    if (this == RepairTicketStatus.delivered) {
      return next == RepairTicketStatus.cancelled;
    }
    if (this == RepairTicketStatus.completed) {
      return next == RepairTicketStatus.delivered ||
          next == RepairTicketStatus.cancelled;
    }
    if (next == RepairTicketStatus.delivered) return false;
    if (next == RepairTicketStatus.cancelled ||
        next == RepairTicketStatus.completed) {
      return true;
    }
    return next != this;
  }
}
