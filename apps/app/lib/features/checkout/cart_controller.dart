import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/models.dart';
import 'checkout_models.dart';

class CartNotifier extends Notifier<CartState> {
  @override
  CartState build() => const CartState();

  /// Ensures the cart is scoped to [businessId], clearing previous business lines if changed.
  void setBusiness(String businessId, {String? businessName}) {
    if (businessId.isEmpty) return;
    if (state.businessId != null && state.businessId != businessId) {
      state = CartState(
        businessId: businessId,
        businessName: businessName,
      );
      return;
    }
    if (state.businessId != businessId ||
        (businessName != null && state.businessName != businessName)) {
      state = state.copyWith(
        businessId: businessId,
        businessName: businessName ?? state.businessName,
      );
    }
  }

  /// Adds 1 unit of [product] to the cart, respecting stock limits and per-business scoping.
  void addProduct(
    Product product, {
    String? businessId,
    String? businessName,
  }) {
    if (!isVisibleCustomerProduct(product)) return;
    if (product.trackStock && product.stock <= 0) return;

    final targetBusinessId =
        businessId ?? product.businessId ?? state.businessId;
    final switchedBusiness = state.businessId != null &&
        targetBusinessId != null &&
        targetBusinessId.isNotEmpty &&
        state.businessId != targetBusinessId;

    final currentItems = switchedBusiness ? <CartItem>[] : [...state.items];
    final currentNote = switchedBusiness ? '' : state.note;
    final resolvedBusinessName = businessName ??
        (switchedBusiness ? null : state.businessName);

    final index =
        currentItems.indexWhere((item) => item.product.id == product.id);
    if (index == -1) {
      currentItems.add(CartItem(product: product, qty: 1));
    } else {
      final existing = currentItems[index];
      final nextQty = existing.qty + 1;
      final cappedQty = product.trackStock && nextQty > product.stock
          ? product.stock
          : nextQty;
      currentItems[index] = existing.copyWith(
        product: product,
        qty: cappedQty,
      );
    }

    state = CartState(
      businessId: targetBusinessId ?? state.businessId,
      businessName: resolvedBusinessName,
      items: List<CartItem>.unmodifiable(currentItems),
      note: currentNote,
    );
  }

  /// Decrements 1 unit of [productId] from the cart, removing the line at 0.
  void decrementProduct(String productId) {
    final index =
        state.items.indexWhere((item) => item.product.id == productId);
    if (index == -1) return;

    final updated = [...state.items];
    final existing = updated[index];
    if (existing.qty <= 1) {
      updated.removeAt(index);
    } else {
      updated[index] = existing.copyWith(qty: existing.qty - 1);
    }

    state = state.copyWith(items: List<CartItem>.unmodifiable(updated));
  }

  /// Removes all units of [productId] from the cart.
  void removeProduct(String productId) {
    final updated = state.items
        .where((item) => item.product.id != productId)
        .toList(growable: false);
    state = state.copyWith(items: updated);
  }

  /// Sets the optional customer note for the order.
  void setNote(String note) {
    state = state.copyWith(note: note);
  }

  /// Clears all items and notes from the cart.
  void clear() {
    state = CartState(
      businessId: state.businessId,
      businessName: state.businessName,
    );
  }
}

final cartProvider = NotifierProvider<CartNotifier, CartState>(
  CartNotifier.new,
);
