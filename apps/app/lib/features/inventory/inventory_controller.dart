import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/api/models.dart';
import 'inventory_repository.dart';

const String kQuickChargeProductName = 'Cobro rapido';

/// Parses a pesos string (e.g. "12.5", "12.50", "85") into integer centavos
/// without floating-point math. Returns null if invalid or <= 0.
int? parsePesosToCents(String raw) {
  final trimmed = raw.trim().replaceAll(r'$', '').replaceAll(',', '').trim();
  if (trimmed.isEmpty) return null;

  final parts = trimmed.split('.');
  if (parts.length > 2) return null;

  final wholePart = parts[0];
  final fracPart = parts.length == 2 ? parts[1] : '';

  if (wholePart.isEmpty && fracPart.isEmpty) return null;

  final digitRegex = RegExp(r'^\d+$');
  if (wholePart.isNotEmpty && !digitRegex.hasMatch(wholePart)) return null;
  if (fracPart.isNotEmpty && !digitRegex.hasMatch(fracPart)) return null;
  if (fracPart.length > 2) return null;

  final wholePesos = wholePart.isEmpty ? 0 : int.tryParse(wholePart);
  if (wholePesos == null || wholePesos < 0) return null;

  int centsPart = 0;
  if (fracPart.length == 1) {
    final d = int.tryParse(fracPart);
    if (d == null) return null;
    centsPart = d * 10;
  } else if (fracPart.length == 2) {
    final d = int.tryParse(fracPart);
    if (d == null) return null;
    centsPart = d;
  }

  final totalCents = (wholePesos * 100) + centsPart;
  if (totalCents <= 0) return null;
  return totalCents;
}

/// Formats integer centavos into an editable pesos string (e.g. 1250 -> "12.50", 1200 -> "12.00").
String formatCentsForInput(int cents) {
  final whole = cents ~/ 100;
  final rem = (cents % 100).abs();
  if (rem == 0) {
    return '$whole.00';
  }
  return '$whole.${rem.toString().padLeft(2, '0')}';
}

/// Filters out inactive products and the internal "Cobro rapido" POS product,
/// then sorts alphabetically by name (case-insensitive).
List<Product> filterAndSortInventoryProducts(Iterable<Product> products) {
  final filtered = products
      .where((p) => p.active && p.name.trim() != kQuickChargeProductName)
      .toList();
  filtered.sort(
    (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
  );
  return filtered;
}

class InventoryState {
  final List<Product> products;
  final List<Product> lowStockProducts;
  final bool isLoading;
  final bool isSubmitting;
  final String? error;

  const InventoryState({
    this.products = const [],
    this.lowStockProducts = const [],
    this.isLoading = false,
    this.isSubmitting = false,
    this.error,
  });

  int get lowStockCount => lowStockProducts.length;

  InventoryState copyWith({
    List<Product>? products,
    List<Product>? lowStockProducts,
    bool? isLoading,
    bool? isSubmitting,
    String? error,
    bool clearError = false,
  }) {
    return InventoryState(
      products: products ?? this.products,
      lowStockProducts: lowStockProducts ?? this.lowStockProducts,
      isLoading: isLoading ?? this.isLoading,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class InventoryController extends Notifier<InventoryState> {
  @override
  InventoryState build() {
    ref.watch(inventoryRepositoryProvider);
    Future.microtask(load);
    return const InventoryState(isLoading: true);
  }

  Future<void> load() async {
    final repo = ref.read(inventoryRepositoryProvider);
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final results = await Future.wait([
        repo.listProducts(),
        repo.listLowStock(threshold: 5),
      ]);
      final visibleProducts = filterAndSortInventoryProducts(results[0]);
      final visibleLowStock = filterAndSortInventoryProducts(results[1]);
      state = state.copyWith(
        products: visibleProducts,
        lowStockProducts: visibleLowStock,
        isLoading: false,
        clearError: true,
      );
    } on ApiException catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.message,
      );
    } catch (_) {
      state = state.copyWith(
        isLoading: false,
        error: 'No pudimos cargar tu inventario. Intenta de nuevo.',
      );
    }
  }

  Future<void> createProduct({
    required String name,
    required int priceCents,
    required bool trackStock,
    required int stock,
    int? prepMinutes,
  }) async {
    final repo = ref.read(inventoryRepositoryProvider);
    state = state.copyWith(isSubmitting: true);
    try {
      await repo.createProduct(
        name: name,
        priceCents: priceCents,
        trackStock: trackStock,
        stock: stock,
        prepMinutes: prepMinutes,
      );
      state = state.copyWith(isSubmitting: false);
      await load();
    } catch (e) {
      state = state.copyWith(isSubmitting: false);
      rethrow;
    }
  }

  Future<void> updateProduct(
    Product original, {
    required String name,
    required int priceCents,
    required bool trackStock,
    int? prepMinutes,
  }) async {
    final repo = ref.read(inventoryRepositoryProvider);
    final trimmedName = name.trim();
    final nameChanged = trimmedName != original.name;
    final priceChanged = priceCents != original.priceCents;
    final trackStockChanged = trackStock != original.trackStock;
    final prepChanged = prepMinutes != original.prepMinutes;

    if (!nameChanged && !priceChanged && !trackStockChanged && !prepChanged) {
      return;
    }

    state = state.copyWith(isSubmitting: true);
    try {
      await repo.updateProduct(
        original.id,
        name: nameChanged ? trimmedName : null,
        priceCents: priceChanged ? priceCents : null,
        trackStock: trackStockChanged ? trackStock : null,
        prepMinutes: prepChanged ? prepMinutes : null,
        clearPrepMinutes: prepChanged && prepMinutes == null,
      );
      state = state.copyWith(isSubmitting: false);
      await load();
    } catch (e) {
      state = state.copyWith(isSubmitting: false);
      rethrow;
    }
  }

  Future<void> deleteProduct(String id) async {
    final repo = ref.read(inventoryRepositoryProvider);
    state = state.copyWith(isSubmitting: true);
    try {
      await repo.deleteProduct(id);
      state = state.copyWith(isSubmitting: false);
      await load();
    } catch (e) {
      state = state.copyWith(isSubmitting: false);
      rethrow;
    }
  }

  Future<void> adjustStock(
    String id, {
    required int delta,
    required String reason,
  }) async {
    final repo = ref.read(inventoryRepositoryProvider);
    state = state.copyWith(isSubmitting: true);
    try {
      await repo.adjustStock(id, delta: delta, reason: reason);
      state = state.copyWith(isSubmitting: false);
      await load();
    } catch (e) {
      state = state.copyWith(isSubmitting: false);
      rethrow;
    }
  }
}

final inventoryControllerProvider =
    NotifierProvider<InventoryController, InventoryState>(
  InventoryController.new,
);
