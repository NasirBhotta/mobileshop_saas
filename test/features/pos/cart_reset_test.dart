import 'package:flutter_test/flutter_test.dart';
import 'package:mobileshop_saas/features/pos/data/models/cart_item_model.dart';
import 'package:mobileshop_saas/features/pos/data/models/customer_model.dart';
import 'package:mobileshop_saas/features/pos/data/models/held_cart_model.dart';
import 'package:mobileshop_saas/features/pos/data/models/discount_approval_model.dart';
import 'package:mobileshop_saas/features/pos/data/models/sale_payment_model.dart';
import 'package:mobileshop_saas/features/pos/presentation/providers/pos_provider.dart';

void main() {
  const first = CartItemModel(
    productId: 'first',
    productName: 'Cable',
    unitPrice: 1000,
  );
  const second = CartItemModel(
    productId: 'second',
    productName: 'Charger',
    unitPrice: 1000,
  );
  const customer = CustomerModel(
    id: 'customer',
    tenantId: 'tenant',
    branchId: 'branch',
    fullName: 'Ali',
  );
  late CartNotifier cart;
  setUp(() => cart = CartNotifier());
  tearDown(() => cart.dispose());

  for (final clear in ['remove', 'zero quantity', 'clear cart']) {
    test('$clear discards the old cash/khata split before a new item', () {
      cart.addItem(first);
      cart.attachCustomer(customer);
      cart.setItemPrice('first', 1200);
      cart.setPayment(PaymentMethod.cash, 200, accountId: 'cash-account');
      cart.setPayment(PaymentMethod.credit, 1000);
      expect(cart.state.isPaymentComplete, isTrue);

      switch (clear) {
        case 'remove':
          cart.removeItem('first');
        case 'zero quantity':
          cart.setItemQuantity('first', 0);
        case 'clear cart':
          cart.clearCart();
      }
      expect(cart.state.isEmpty, isTrue);
      expect(cart.state.payments, isEmpty);
      expect(cart.state.customer, isNull);
      cart.addItem(second);
      expect(cart.state.total, 1000);
      expect(cart.state.totalPaid, 0);
      expect(cart.state.remainingAmount, 1000);
      expect(cart.state.isPaymentComplete, isFalse);
    });
  }

  test(
    'removing one item preserves the customer and payments for remaining items',
    () {
      cart.addItem(first);
      cart.addItem(second);
      cart.attachCustomer(customer);
      cart.setPayment(PaymentMethod.cash, 200, accountId: 'cash-account');
      cart.removeItem('first');
      expect(cart.state.customer?.id, 'customer');
      expect(cart.state.totalPaid, 200);
      expect(cart.state.remainingAmount, 800);
      cart.removeItem('not-in-cart');
      expect(cart.state.items.single.productId, 'second');
      expect(cart.state.payments.single.accountId, 'cash-account');
    },
  );

  test(
    'emptying a resumed cart drops its held identity and discount approvals',
    () {
      cart.resumeFromHeld(
        HeldCartModel(
          id: 'held',
          branchId: 'branch',
          userId: 'user',
          items: const [first],
          customerId: customer.id,
          customerName: customer.fullName,
          createdAt: DateTime(2026),
        ),
      );
      cart.setItemDiscount(
        'first',
        100,
        approval: const DiscountApprovalModel(
          scope: 'item',
          productId: 'first',
          type: DiscountType.fixed,
          requestedValue: 100,
          discountAmount: 100,
        ),
      );
      cart.removeItem('first');
      expect(cart.state.heldCartId, isNull);
      expect(cart.state.discountApprovals, isEmpty);
    },
  );

  test('customer remains attached through price and payment editing', () {
    cart.addItem(first);
    cart.attachCustomer(customer);
    cart.setItemPrice('first', 750);
    cart.setItemQuantity('first', 2);
    cart.setItemDiscount('first', 50);
    cart.clearPayments();
    cart.setPayment(PaymentMethod.cash, 400, accountId: 'cash-account');
    cart.setPayment(PaymentMethod.credit, 1000);
    expect(cart.state.customer?.id, customer.id);
    expect(cart.state.isPaymentComplete, isTrue);
  });
}
