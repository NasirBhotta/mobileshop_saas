import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../data/models/cart_item_model.dart';
import '../../data/models/customer_model.dart';
import '../../data/models/held_cart_model.dart';
import '../../data/models/sale_model.dart';
import '../../data/models/sale_payment_model.dart';
import '../../data/repositories/pos_repository.dart';

// ── Repository Provider ──
final posRepositoryProvider = Provider<PosRepository>((ref) {
  return PosRepository();
});

// ── Cart State ──────────────────────────────────────
class CartState {
  final List<CartItemModel> items;
  final CustomerModel? customer; // attached customer
  final List<SalePaymentModel> payments;
  final String? heldCartId; // agar resume hua

  const CartState({
    this.items = const [],
    this.customer,
    this.payments = const [],
    this.heldCartId,
  });

  // ── Computed Properties ──

  // Subtotal (discounts se pehle)
  double get subtotal =>
      items.fold(0, (sum, item) => sum + (item.unitPrice * item.quantity));

  // Total discount
  double get discountAmount =>
      items.fold(0, (sum, item) => sum + (item.discountAmount * item.quantity));

  // Total tax
  double get taxAmount => items.fold(0, (sum, item) => sum + item.taxAmount);

  // Final total
  double get total => subtotal - discountAmount + taxAmount;

  // Total paid (payments se)
  double get totalPaid => payments.fold(0, (sum, p) => sum + p.amount);

  // Remaining amount
  double get remainingAmount => total - totalPaid;

  // Payment complete hai?
  bool get isPaymentComplete => (remainingAmount).abs() < 0.01;

  // Cart empty hai?
  bool get isEmpty => items.isEmpty;

  // Item count
  int get itemCount => items.fold(0, (sum, item) => sum + item.quantity);

  CartState copyWith({
    List<CartItemModel>? items,
    CustomerModel? customer,
    bool clearCustomer = false,
    List<SalePaymentModel>? payments,
    String? heldCartId,
    bool clearHeldCartId = false,
  }) {
    return CartState(
      items: items ?? this.items,
      customer: clearCustomer ? null : customer ?? this.customer,
      payments: payments ?? this.payments,
      heldCartId: clearHeldCartId ? null : heldCartId ?? this.heldCartId,
    );
  }
}

// ── Cart Provider ───────────────────────────────────
final cartProvider = StateNotifierProvider<CartNotifier, CartState>((ref) {
  return CartNotifier();
});

class CartNotifier extends StateNotifier<CartState> {
  CartNotifier() : super(const CartState());

  // ── Item Operations ──────────────────────────────

  // Product add karo cart mein
  void addItem(CartItemModel item) {
    final existing = state.items.indexWhere(
      (e) => e.productId == item.productId,
    );

    if (existing != -1) {
      // Already hai → quantity badha do
      final updated = List<CartItemModel>.from(state.items);
      updated[existing] = updated[existing].incrementQty();
      state = state.copyWith(items: updated);
    } else {
      // Naya item add karo
      state = state.copyWith(items: [...state.items, item]);
    }
  }

  // Quantity increment
  void incrementItem(String productId) {
    final updated =
        state.items.map((item) {
          return item.productId == productId ? item.incrementQty() : item;
        }).toList();
    state = state.copyWith(items: updated);
  }

  // Quantity decrement (1 se neeche gaya → remove)
  void decrementItem(String productId) {
    final updated =
        state.items.map((item) {
          return item.productId == productId ? item.decrementQty() : item;
        }).toList();
    // Agar quantity 1 pe hai aur decrement kiya → ab bhi 1 rahega
    // Remove alag method se
    state = state.copyWith(items: updated);
  }

  // Item remove karo
  void removeItem(String productId) {
    state = state.copyWith(
      items: state.items.where((item) => item.productId != productId).toList(),
    );
  }

  // Item discount set karo
  void setItemDiscount(String productId, double discount) {
    final updated =
        state.items.map((item) {
          return item.productId == productId
              ? item.copyWith(discountAmount: discount)
              : item;
        }).toList();
    state = state.copyWith(items: updated);
  }

  // Quantity directly set karo
  void setItemQuantity(String productId, int quantity) {
    if (quantity <= 0) {
      removeItem(productId);
      return;
    }
    final updated =
        state.items.map((item) {
          return item.productId == productId
              ? item.copyWith(quantity: quantity)
              : item;
        }).toList();
    state = state.copyWith(items: updated);
  }

  // ── Customer Operations ──────────────────────────

  void attachCustomer(CustomerModel customer) {
    state = state.copyWith(customer: customer);
  }

  void detachCustomer() {
    state = state.copyWith(clearCustomer: true);
  }

  // ── Payment Operations ───────────────────────────

  // Payment add karo ya update karo
  void setPayment(PaymentMethod method, double amount) {
    if (amount <= 0) {
      // Remove karo agar 0
      state = state.copyWith(
        payments: state.payments.where((p) => p.method != method).toList(),
      );
      return;
    }

    final existing = state.payments.indexWhere((p) => p.method == method);

    if (existing != -1) {
      // Update karo
      final updated = List<SalePaymentModel>.from(state.payments);
      updated[existing] = updated[existing].copyWith(amount: amount);
      state = state.copyWith(payments: updated);
    } else {
      // Add karo
      state = state.copyWith(
        payments: [
          ...state.payments,
          SalePaymentModel(method: method, amount: amount),
        ],
      );
    }
  }

  // Single payment shortcut (cash only)
  void setFullCashPayment() {
    state = state.copyWith(
      payments: [
        SalePaymentModel(method: PaymentMethod.cash, amount: state.total),
      ],
    );
  }

  // Sab payments clear karo
  void clearPayments() {
    state = state.copyWith(payments: []);
  }

  // ── Cart Operations ──────────────────────────────

  // Held cart se resume karo
  void resumeFromHeld(HeldCartModel held) {
    state = CartState(
      items: held.items,
      heldCartId: held.id,
      customer:
          held.customerId != null
              ? CustomerModel(
                id: held.customerId,
                tenantId: '',
                branchId: held.branchId,
                fullName: held.customerName ?? '',
              )
              : null,
    );
  }

  // Cart clear karo (checkout ya void ke baad)
  void clearCart() {
    state = const CartState();
  }
}

// ── Checkout Controller ─────────────────────────────
final checkoutControllerProvider =
    StateNotifierProvider<CheckoutController, AsyncValue<SaleModel?>>((ref) {
      return CheckoutController(ref.read(posRepositoryProvider), ref);
    });

class CheckoutController extends StateNotifier<AsyncValue<SaleModel?>> {
  final PosRepository _repository;
  final Ref _ref;

  CheckoutController(this._repository, this._ref)
    : super(const AsyncData(null));

  // ── Checkout ────────────────────────────────────
  Future<SaleModel?> checkout() async {
    final cart = _ref.read(cartProvider);

    if (cart.isEmpty) {
      state = AsyncError(Exception('Cart empty hai'), StackTrace.current);
      return null;
    }

    if (!cart.isPaymentComplete) {
      state = AsyncError(
        Exception(
          'Payment incomplete. '
          'Remaining: ₨${cart.remainingAmount.toStringAsFixed(0)}',
        ),
        StackTrace.current,
      );
      return null;
    }

    state = const AsyncLoading();
    try {
      final sale = await _repository.checkout(
        items: cart.items,
        payments: cart.payments,
        customerId: cart.customer?.id,
        customerName: cart.customer?.fullName,
      );

      // Held cart tha → delete karo
      if (cart.heldCartId != null) {
        await _repository.deleteHeldCart(cart.heldCartId!);
      }

      // Cart clear karo
      _ref.read(cartProvider.notifier).clearCart();

      // Sales history refresh
      _ref.invalidate(salesHistoryProvider);

      state = AsyncData(sale);
      return sale;
    } catch (e, st) {
      state = AsyncError(e, st);
      return null;
    }
  }

  // ── Hold Cart ────────────────────────────────────
  Future<bool> holdCart({String? label}) async {
    final cart = _ref.read(cartProvider);
    if (cart.isEmpty) return false;

    state = const AsyncLoading();
    try {
      await _repository.holdCart(
        items: cart.items,
        label: label,
        customerId: cart.customer?.id,
        customerName: cart.customer?.fullName,
      );

      _ref.read(cartProvider.notifier).clearCart();
      _ref.invalidate(heldCartsProvider);

      state = const AsyncData(null);
      return true;
    } catch (e, st) {
      state = AsyncError(e, st);
      return false;
    }
  }

  // ── Void Cart ────────────────────────────────────
  Future<bool> voidCart({String? reason}) async {
    final cart = _ref.read(cartProvider);
    if (cart.isEmpty) return false;

    state = const AsyncLoading();
    try {
      await _repository.voidCart(items: cart.items, reason: reason);

      _ref.read(cartProvider.notifier).clearCart();

      state = const AsyncData(null);
      return true;
    } catch (e, st) {
      state = AsyncError(e, st);
      return false;
    }
  }

  void clearResult() {
    state = const AsyncData(null);
  }
}

// ── Held Carts Provider ─────────────────────────────
final heldCartsProvider = FutureProvider<List<HeldCartModel>>((ref) {
  return ref.read(posRepositoryProvider).fetchHeldCarts();
});

// ── Sales History Provider ──────────────────────────
final salesHistoryProvider = FutureProvider<List<SaleModel>>((ref) {
  return ref.read(posRepositoryProvider).fetchSales();
});

// ── Customer Search Provider ────────────────────────
final customerSearchQueryProvider = StateProvider<String>((ref) => '');

final customerSearchProvider =
    FutureProvider.family<List<CustomerModel>, String>((ref, query) {
      if (query.isEmpty) return Future.value([]);
      return ref.read(posRepositoryProvider).searchCustomers(query);
    });

// ── Customer Add Controller ─────────────────────────
final customerControllerProvider =
    StateNotifierProvider<CustomerController, AsyncValue<void>>((ref) {
      return CustomerController(ref.read(posRepositoryProvider));
    });

class CustomerController extends StateNotifier<AsyncValue<void>> {
  final PosRepository _repository;

  CustomerController(this._repository) : super(const AsyncData(null));

  Future<CustomerModel?> addCustomer({
    required String fullName,
    String? phone,
    String? email,
  }) async {
    state = const AsyncLoading();
    try {
      final customer = await _repository.addCustomer(
        fullName: fullName,
        phone: phone,
        email: email,
      );
      state = const AsyncData(null);
      return customer;
    } catch (e, st) {
      state = AsyncError(e, st);
      return null;
    }
  }
}
