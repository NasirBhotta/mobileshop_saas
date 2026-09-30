import 'package:flutter_test/flutter_test.dart';
import 'package:mobileshop_saas/features/pos/data/models/cart_item_model.dart';
import 'package:mobileshop_saas/features/pos/presentation/providers/pos_provider.dart';

void main() {
  late CartNotifier cart;

  setUp(() => cart = CartNotifier());
  tearDown(() => cart.dispose());

  group('CartNotifier Unit Item / IMEI serialization', () {
    test('normal product increments quantity when re-added', () {
      const normalProduct = CartItemModel(
        productId: 'prod-charger',
        productName: 'Fast Charger',
        unitPrice: 1500,
        quantity: 1,
      );

      cart.addItem(normalProduct);
      expect(cart.state.items.length, 1);
      expect(cart.state.items.first.quantity, 1);

      // Re-add same product
      cart.addItem(normalProduct);
      expect(cart.state.items.length, 1);
      expect(cart.state.items.first.quantity, 2);
    });

    test('serialized phone unit with IMEI is kept separate and locks quantity to 1', () {
      const phoneUnit1 = CartItemModel(
        productId: 'prod-iphone13',
        productName: 'iPhone 13 128GB',
        unitPrice: 145000,
        quantity: 1,
        imei: '356892110293847',
        deviceDetails: 'Midnight • 89% Battery',
        unitId: 'unit-1',
      );

      cart.addItem(phoneUnit1);
      expect(cart.state.items.length, 1);
      expect(cart.state.items.first.quantity, 1);
      expect(cart.state.items.first.isUnitItem, isTrue);

      // Attempting to increment should be ignored for unit items
      cart.incrementItem(phoneUnit1.cartKey);
      expect(cart.state.items.first.quantity, 1);

      // Attempting to add the exact same IMEI item again should be ignored (duplicate prevented)
      cart.addItem(phoneUnit1);
      expect(cart.state.items.length, 1);
      expect(cart.state.items.first.quantity, 1);

      // Adding a DIFFERENT unit/IMEI of the SAME product model
      const phoneUnit2 = CartItemModel(
        productId: 'prod-iphone13',
        productName: 'iPhone 13 128GB',
        unitPrice: 140000,
        quantity: 1,
        imei: '864209123456789',
        deviceDetails: 'Blue • 85% Battery',
        unitId: 'unit-2',
      );

      cart.addItem(phoneUnit2);

      // Should create 2 separate line items in cart, NOT merge quantities!
      expect(cart.state.items.length, 2);
      expect(cart.state.items[0].imei, '356892110293847');
      expect(cart.state.items[0].quantity, 1);
      expect(cart.state.items[1].imei, '864209123456789');
      expect(cart.state.items[1].quantity, 1);
      expect(cart.state.total, 285000);

      // Removing unit 1 removes it from cart
      cart.removeItem(phoneUnit1.cartKey);
      expect(cart.state.items.length, 1);
      expect(cart.state.items.first.imei, '864209123456789');
    });
  });
}
