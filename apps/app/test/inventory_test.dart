import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paydmex_app/core/api/models.dart';
import 'package:paydmex_app/core/theme/theme.dart';
import 'package:paydmex_app/features/auth/auth_controller.dart';
import 'package:paydmex_app/features/inventory/inventory_controller.dart';
import 'package:paydmex_app/features/inventory/inventory_repository.dart';
import 'package:paydmex_app/features/inventory/inventory_screen.dart';
import 'package:paydmex_app/features/inventory/product_form_sheet.dart';
import 'package:paydmex_app/features/inventory/stock_sheet.dart';

class FakeInventoryRepository implements InventoryRepository {
  List<Product> productsToReturn;
  List<Product> lowStockToReturn;

  Map<String, dynamic>? lastCreatedPayload;
  Map<String, dynamic>? lastUpdatedPayload;
  Map<String, dynamic>? lastStockPayload;
  String? lastDeletedId;

  FakeInventoryRepository({
    this.productsToReturn = const [],
    this.lowStockToReturn = const [],
  });

  @override
  Future<List<Product>> listProducts() async => List.of(productsToReturn);

  @override
  Future<List<Product>> listLowStock({int threshold = 5}) async =>
      List.of(lowStockToReturn);

  @override
  Future<Product> createProduct({
    required String name,
    required int priceCents,
    required bool trackStock,
    required int stock,
    int? prepMinutes,
  }) async {
    lastCreatedPayload = {
      'name': name,
      'priceCents': priceCents,
      'trackStock': trackStock,
      'stock': stock,
      'prepMinutes': ?prepMinutes,
    };
    final created = Product(
      id: 'prod_new',
      name: name,
      priceCents: priceCents,
      trackStock: trackStock,
      stock: stock,
      prepMinutes: prepMinutes,
      active: true,
    );
    productsToReturn = [...productsToReturn, created];
    return created;
  }

  @override
  Future<Product> updateProduct(
    String id, {
    String? name,
    int? priceCents,
    bool? trackStock,
    int? prepMinutes,
    bool clearPrepMinutes = false,
  }) async {
    lastUpdatedPayload = {
      'id': id,
      'name': ?name,
      'priceCents': ?priceCents,
      'trackStock': ?trackStock,
      if (prepMinutes != null)
        'prepMinutes': prepMinutes
      else if (clearPrepMinutes)
        'prepMinutes': null,
    };
    return Product(
      id: id,
      name: name ?? 'Updated',
      priceCents: priceCents ?? 1000,
      trackStock: trackStock ?? true,
      stock: 5,
      prepMinutes: prepMinutes,
    );
  }

  @override
  Future<void> deleteProduct(String id) async {
    lastDeletedId = id;
    productsToReturn = productsToReturn.where((p) => p.id != id).toList();
  }

  @override
  Future<Product?> adjustStock(
    String id, {
    required int delta,
    required String reason,
  }) async {
    lastStockPayload = {
      'id': id,
      'delta': delta,
      'reason': reason,
    };
    productsToReturn = productsToReturn.map((p) {
      if (p.id == id) {
        return Product(
          id: p.id,
          name: p.name,
          priceCents: p.priceCents,
          trackStock: p.trackStock,
          stock: p.stock + delta,
          prepMinutes: p.prepMinutes,
          active: p.active,
        );
      }
      return p;
    }).toList();
    return null;
  }
}

class _FakeAuthNotifier extends AuthNotifier {
  final AuthState initial;
  _FakeAuthNotifier(this.initial);

  @override
  AuthState build() => initial;
}

Widget _wrapWithApp({
  required Widget child,
  required FakeInventoryRepository repo,
  Business? business,
}) {
  return ProviderScope(
    overrides: [
      inventoryRepositoryProvider.overrideWithValue(repo),
      authProvider.overrideWith(
        () => _FakeAuthNotifier(
          AuthState(
            status: AuthStatus.authenticated,
            user: const User(
              id: 'u1',
              email: 'owner@paydmex.mx',
              name: 'Dueño',
            ),
            business: business ??
                const Business(
                  id: 'b1',
                  name: 'Taqueria El Sol',
                  category: BusinessCategory.food,
                  prepType: PrepType.madeToOrder,
                ),
          ),
        ),
      ),
    ],
    child: MaterialApp(
      theme: PxTheme.light(),
      home: Scaffold(body: child),
    ),
  );
}

void main() {
  group('parsePesosToCents', () {
    test('parses valid integer and decimal peso strings without float math', () {
      expect(parsePesosToCents('85'), 8500);
      expect(parsePesosToCents('12.5'), 1250);
      expect(parsePesosToCents('12.50'), 1250);
      expect(parsePesosToCents('0.05'), 5);
      expect(parsePesosToCents('.50'), 50);
    });

    test('rejects zero, negative, non-numeric, and >2 decimal places', () {
      expect(parsePesosToCents('0'), isNull);
      expect(parsePesosToCents('0.00'), isNull);
      expect(parsePesosToCents('abc'), isNull);
      expect(parsePesosToCents('1.234'), isNull);
      expect(parsePesosToCents('-10'), isNull);
      expect(parsePesosToCents(''), isNull);
    });
  });

  group('InventoryScreen list & badges', () {
    testWidgets(
      'hides Cobro rapido and inactive products, sorts by name, and renders Agotado / Stock bajo badges',
      (tester) async {
        final fakeRepo = FakeInventoryRepository(
          productsToReturn: const [
            Product(
              id: 'p_quick',
              name: 'Cobro rapido',
              priceCents: 1000,
              trackStock: false,
              active: true,
            ),
            Product(
              id: 'p_inactive',
              name: 'Producto Inactivo',
              priceCents: 2000,
              trackStock: true,
              stock: 10,
              active: false,
            ),
            Product(
              id: 'p_z',
              name: 'Zopes',
              priceCents: 4500,
              trackStock: true,
              stock: 0,
              active: true,
            ),
            Product(
              id: 'p_a',
              name: 'Agua de Horchata',
              priceCents: 2500,
              trackStock: true,
              stock: 3,
              active: true,
            ),
            Product(
              id: 'p_m',
              name: 'Mulitas',
              priceCents: 3500,
              trackStock: false,
              stock: 0,
              active: true,
            ),
          ],
          lowStockToReturn: const [
            Product(
              id: 'p_z',
              name: 'Zopes',
              priceCents: 4500,
              trackStock: true,
              stock: 0,
              active: true,
            ),
            Product(
              id: 'p_a',
              name: 'Agua de Horchata',
              priceCents: 2500,
              trackStock: true,
              stock: 3,
              active: true,
            ),
          ],
        );

        await tester.pumpWidget(
          _wrapWithApp(
            repo: fakeRepo,
            child: const InventoryScreen(),
          ),
        );
        await tester.pumpAndSettle();

        // Hidden products are not shown
        expect(find.text('Cobro rapido'), findsNothing);
        expect(find.text('Producto Inactivo'), findsNothing);

        // Visible products are shown
        expect(find.text('Agua de Horchata'), findsOneWidget);
        expect(find.text('Mulitas'), findsOneWidget);
        expect(find.text('Zopes'), findsOneWidget);

        // Low stock summary strip is shown
        expect(find.text('2 con stock bajo'), findsOneWidget);

        // Stock text and badges
        expect(find.text('3 en existencia'), findsOneWidget);
        expect(find.text('0 en existencia'), findsOneWidget);
        expect(find.text('Sin control de existencias'), findsOneWidget);
        expect(find.text('Stock bajo'), findsOneWidget);
        expect(find.text('Agotado'), findsOneWidget);

        // Sorted order: Agua de Horchata appears above Mulitas, which appears above Zopes
        final aguaY = tester.getTopLeft(find.text('Agua de Horchata')).dy;
        final mulitasY = tester.getTopLeft(find.text('Mulitas')).dy;
        final zopesY = tester.getTopLeft(find.text('Zopes')).dy;
        expect(aguaY, lessThan(mulitasY));
        expect(mulitasY, lessThan(zopesY));
      },
    );
  });

  group('ProductFormSheet create flow', () {
    testWidgets('submits correct payload in centavos to fake repository',
        (tester) async {
      final fakeRepo = FakeInventoryRepository();

      await tester.pumpWidget(
        _wrapWithApp(
          repo: fakeRepo,
          child: const SingleChildScrollView(
            child: ProductFormSheet(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final textFields = find.byType(TextField);
      // Field 0: name, Field 1: price, Field 2: initial stock, Field 3: prepMinutes
      await tester.enterText(textFields.at(0), 'Taco de Suadero');
      await tester.enterText(textFields.at(1), '22.50');
      await tester.enterText(textFields.at(2), '40');
      await tester.enterText(textFields.at(3), '10');

      final submitBtn = find.text('Agregar producto');
      await tester.ensureVisible(submitBtn);
      await tester.tap(submitBtn);
      await tester.pumpAndSettle();

      expect(fakeRepo.lastCreatedPayload, isNotNull);
      expect(fakeRepo.lastCreatedPayload!['name'], 'Taco de Suadero');
      expect(fakeRepo.lastCreatedPayload!['priceCents'], 2250);
      expect(fakeRepo.lastCreatedPayload!['trackStock'], true);
      expect(fakeRepo.lastCreatedPayload!['stock'], 40);
      expect(fakeRepo.lastCreatedPayload!['prepMinutes'], 10);
    });
  });

  group('StockSheet adjust flow', () {
    testWidgets('sends signed delta and selected reason lowercase',
        (tester) async {
      const product = Product(
        id: 'p_stock_1',
        name: 'Refresco Vidrio',
        priceCents: 2800,
        trackStock: true,
        stock: 10,
      );
      final fakeRepo = FakeInventoryRepository(productsToReturn: [product]);

      await tester.pumpWidget(
        _wrapWithApp(
          repo: fakeRepo,
          child: const SingleChildScrollView(
            child: StockSheet(product: product),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap decrement twice -> delta = -2
      final decFinder = find.bySemanticsLabel('Disminuir cantidad en 1');
      await tester.tap(decFinder);
      await tester.pump();
      await tester.tap(decFinder);
      await tester.pump();

      expect(find.text('-2'), findsOneWidget);

      // Select "Merma" chip
      await tester.tap(find.text('Merma'));
      await tester.pump();

      final saveFinder = find.text('Guardar ajuste');
      await tester.ensureVisible(saveFinder);
      await tester.tap(saveFinder);
      await tester.pumpAndSettle();

      expect(fakeRepo.lastStockPayload, isNotNull);
      expect(fakeRepo.lastStockPayload!['id'], 'p_stock_1');
      expect(fakeRepo.lastStockPayload!['delta'], -2);
      expect(fakeRepo.lastStockPayload!['reason'], 'merma');
    });
  });
}
