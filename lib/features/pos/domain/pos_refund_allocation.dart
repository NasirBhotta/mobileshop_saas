class RefundablePaymentLeg {
  final String paymentId;
  final String accountId;
  final double paidAmount;
  final double alreadyRefunded;

  const RefundablePaymentLeg({
    required this.paymentId,
    required this.accountId,
    required this.paidAmount,
    this.alreadyRefunded = 0,
  });

  double get available =>
      (paidAmount - alreadyRefunded).clamp(0, double.infinity).toDouble();
}

class PosRefundAllocation {
  final String paymentId;
  final String accountId;
  final double amount;

  const PosRefundAllocation({
    required this.paymentId,
    required this.accountId,
    required this.amount,
  });
}

class PosRefundAllocator {
  const PosRefundAllocator._();

  static List<PosRefundAllocation> allocate({
    required double refundAmount,
    required Iterable<RefundablePaymentLeg> payments,
  }) {
    if (refundAmount <= 0) return const [];
    final ordered =
        payments.toList()
          ..sort((left, right) => left.paymentId.compareTo(right.paymentId));
    var remaining = refundAmount;
    final allocations = <PosRefundAllocation>[];

    for (final payment in ordered) {
      if (remaining <= 0.005) break;
      final amount =
          payment.available < remaining ? payment.available : remaining;
      if (amount <= 0) continue;
      allocations.add(
        PosRefundAllocation(
          paymentId: payment.paymentId,
          accountId: payment.accountId,
          amount: amount,
        ),
      );
      remaining -= amount;
    }

    if (remaining > 0.01) {
      throw StateError(
        'Cash refund original non-credit payments se zyada hai.',
      );
    }
    return allocations;
  }
}
