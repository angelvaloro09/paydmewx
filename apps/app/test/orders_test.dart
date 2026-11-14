import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:paydmex_app/core/api/api_exception.dart';
import 'package:paydmex_app/core/api/models.dart';
import 'package:paydmex_app/core/theme/theme.dart';
import 'package:paydmex_app/features/auth/auth_controller.dart';
import 'package:paydmex_app/features/orders/orders_controller.dart';
import 'package:paydmex_app/features/orders/orders_repository.dart';
import 'package:paydmex_app/features/orders/orders_screen.dart';

class FakeOrdersRepository implements OrdersRepository {
  List<Order> businessOrders;
  List<Order> customerOrders;
  ApiException? errorToThrow;
  OrdersRole? lastRequestedRole;
  final List<(String orderId, OrderStatus status)> statusUpdates = [];

  FakeOrdersRepository({
    List<Order>? businessOrders,
    List<Order>? customerOrders,
    this.errorToThrow,
  })  : businessOrders = businessOrders ?? <Order>[],
        customerOrders = customerOrders ?? <Order>[];

  @override
  Future<List<Order>> listOrders({required OrdersRole role}) async {
    lastRequestedRole = role;
    if (errorToThrow != null) {
      throw errorToThrow!;
    }
    final source =
        role == OrdersRole.business ? businessOrders : customerOrders;
    final copy = [...source]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return copy;
  }

  @override
  Future<Order?> updateOrderStatus({
    required String orderId,
    required OrderStatus status,
  }) async {
    if (errorToThrow != null) {
      throw errorToThrow!;
    }
    statusUpdates.add((orderId, status));

    Order? updated;
    businessOrders = businessOrders.map((order) {
      if (order.id == orderId) {
        updated = order.copyWith(status: status);
        return updated!;
      }
      return order;
    }).toList();

    customerOrders = customerOrders.map((order) {
      if (order.id == orderId) {
        updated = order.copyWith(status: status);
        return updated!;
      }
      return order;
    }).toList();

    return updated;
  }
}

class _FixedAuthNotifier extends AuthNotifier {
  final AuthState initial;
  _FixedAuthNotifier(this.initial);

  @override
  AuthState build() => initial;
}

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  group('OrderItem display & Order summary', () {
    test('maps "Cobro rapido" to "Cobro en caja" without quantity', () {
      const quickItem = OrderItem(
        name: 'Cobro rapido',
        priceCents: 8500,
        qty: 1,
      );
      expect(quickItem.isQuickCharge, isTrue);
      expect(quickItem.displayLabel, 'Cobro en caja');
      expect(
        formatOrderItemDisplay(name: 'Cobro rapido', qty: 3),
        'Cobro en caja',
      );
    });

    test('formats regular product items with "<qty> x <name>"', () {
      const regularItem = OrderItem(
        name: 'Taco al pastor',
        priceCents: 2500,
        qty: 2,
      );
      expect(regularItem.isQuickCharge, isFalse);
      expect(regularItem.displayLabel, '2 x Taco al pastor');
    });

    test('builds order itemsSummary and uppercase 6-char shortCode', () {
      const order = Order(
        id: '01j9abcxyz1234ef',
        businessId: 'biz_1',
        status: OrderStatus.paid,
        totalCents: 13500,
        createdAt: 1700000000,
        items: [
          OrderItem(name: 'Taco al pastor', priceCents: 2500, qty: 2),
          OrderItem(name: 'Agua de horchata', priceCents: 3500, qty: 1),
        ],
      );

      expect(order.shortCode, '1234EF');
      expect(order.itemsSummary, '2 x Taco al pastor, 1 x Agua de horchata');
    });
  });

  group('OrderStatus labels & badges', () {
    test('maps every API status to expected Spanish label', () {
      expect(OrderStatus.fromApi('pending_payment').labelEs, 'Por pagar');
      expect(OrderStatus.fromApi('paid').labelEs, 'Pagado');
      expect(OrderStatus.fromApi('preparing').labelEs, 'Preparando');
      expect(OrderStatus.fromApi('ready').labelEs, 'Listo');
      expect(OrderStatus.fromApi('delivered').labelEs, 'Entregado');
      expect(OrderStatus.fromApi('cancelled').labelEs, 'Cancelado');
      expect(OrderStatus.fromApi('expired').labelEs, 'Expirado');
    });

    test('marks paid and preparing as LIVE', () {
      expect(OrderStatus.paid.isLive, isTrue);
      expect(OrderStatus.preparing.isLive, isTrue);
      expect(OrderStatus.pendingPayment.isLive, isFalse);
      expect(OrderStatus.ready.isLive, isFalse);
      expect(OrderStatus.delivered.isLive, isFalse);
      expect(OrderStatus.cancelled.isLive, isFalse);
      expect(OrderStatus.expired.isLive, isFalse);
    });
  });

  group('Valid action per status, role, and prepType', () {
    test('business role with PrepType.madeToOrder transitions', () {
      final pendingAction = validActionForOrder(
        status: OrderStatus.pendingPayment,
        role: OrdersRole.business,
        prepType: PrepType.madeToOrder,
      );
      expect(pendingAction?.label, 'Cancelar');
      expect(pendingAction?.targetStatus, OrderStatus.cancelled);

      final paidAction = validActionForOrder(
        status: OrderStatus.paid,
        role: OrdersRole.business,
        prepType: PrepType.madeToOrder,
      );
      expect(paidAction?.label, 'Preparar');
      expect(paidAction?.targetStatus, OrderStatus.preparing);

      final preparingAction = validActionForOrder(
        status: OrderStatus.preparing,
        role: OrdersRole.business,
        prepType: PrepType.madeToOrder,
      );
      expect(preparingAction?.label, 'Marcar listo');
      expect(preparingAction?.targetStatus, OrderStatus.ready);
      expect(preparingAction?.announcement, 'Pedido listo');

      final readyAction = validActionForOrder(
        status: OrderStatus.ready,
        role: OrdersRole.business,
        prepType: PrepType.madeToOrder,
      );
      expect(readyAction?.label, 'Entregar');
      expect(readyAction?.targetStatus, OrderStatus.delivered);

      expect(
        validActionForOrder(
          status: OrderStatus.delivered,
          role: OrdersRole.business,
          prepType: PrepType.madeToOrder,
        ),
        isNull,
      );
      expect(
        validActionForOrder(
          status: OrderStatus.cancelled,
          role: OrdersRole.business,
          prepType: PrepType.madeToOrder,
        ),
        isNull,
      );
      expect(
        validActionForOrder(
          status: OrderStatus.expired,
          role: OrdersRole.business,
          prepType: PrepType.madeToOrder,
        ),
        isNull,
      );
    });

    test('business role with PrepType.instant skips preparing/ready', () {
      final paidAction = validActionForOrder(
        status: OrderStatus.paid,
        role: OrdersRole.business,
        prepType: PrepType.instant,
      );
      expect(paidAction?.label, 'Entregar');
      expect(paidAction?.targetStatus, OrderStatus.delivered);
    });

    test('customer role only allows Cancelar on pending_payment', () {
      final pendingAction = validActionForOrder(
        status: OrderStatus.pendingPayment,
        role: OrdersRole.customer,
      );
      expect(pendingAction?.label, 'Cancelar');
      expect(pendingAction?.targetStatus, OrderStatus.cancelled);

      for (final status in [
        OrderStatus.paid,
        OrderStatus.preparing,
        OrderStatus.ready,
        OrderStatus.delivered,
        OrderStatus.cancelled,
        OrderStatus.expired,
      ]) {
        expect(
          validActionForOrder(
            status: status,
            role: OrdersRole.customer,
          ),
          isNull,
        );
      }
    });
  });

  group('OrdersController with FakeOrdersRepository', () {
    test('loads orders sorted newest first and updates status', () async {
      final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final fakeRepo = FakeOrdersRepository(
        businessOrders: [
          Order(
            id: 'ord_older_111111',
            businessId: 'biz_1',
            status: OrderStatus.pendingPayment,
            totalCents: 4500,
            createdAt: nowSec - 300,
            items: const [
              OrderItem(name: 'Cobro rapido', priceCents: 4500, qty: 1),
            ],
          ),
          Order(
            id: 'ord_newer_222222',
            businessId: 'biz_1',
            status: OrderStatus.preparing,
            totalCents: 9000,
            createdAt: nowSec - 60,
            items: const [
              OrderItem(name: 'Taco al pastor', priceCents: 4500, qty: 2),
            ],
          ),
        ],
      );

      final container = ProviderContainer(
        overrides: [
          ordersRepositoryProvider.overrideWithValue(fakeRepo),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(ordersControllerProvider.notifier);
      await notifier.refresh(role: OrdersRole.business);

      var state = container.read(ordersControllerProvider);
      expect(fakeRepo.lastRequestedRole, OrdersRole.business);
      expect(state.isLoading, isFalse);
      expect(state.orders.map((e) => e.id).toList(), [
        'ord_newer_222222',
        'ord_older_111111',
      ]);
      expect(state.todaySummary().paidCount, 1);
      expect(state.todaySummary().totalCents, 9000);

      final ok = await notifier.changeStatus(
        orderId: 'ord_newer_222222',
        status: OrderStatus.ready,
      );

      expect(ok, isTrue);
      expect(
        fakeRepo.statusUpdates,
        [('ord_newer_222222', OrderStatus.ready)],
      );

      state = container.read(ordersControllerProvider);
      expect(state.orders.first.status, OrderStatus.ready);
      expect(state.lastAnnouncement, 'Pedido listo');
    });
  });

  group('OrdersScreen widget tests', () {
    testWidgets(
      'renders business timeline, LIVE badge, today stats, and handles action at 390x844 @ 200% text scale',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        final fakeRepo = FakeOrdersRepository(
          businessOrders: [
            Order(
              id: '01hxyzab12cd34ef',
              businessId: 'biz_1',
              status: OrderStatus.paid,
              totalCents: 8500,
              createdAt: nowSec - 120,
              items: const [
                OrderItem(name: 'Cobro rapido', priceCents: 8500, qty: 1),
              ],
            ),
          ],
        );

        const authState = AuthState(
          status: AuthStatus.authenticated,
          business: Business(
            id: 'biz_1',
            name: 'Taquería El Sol',
            category: BusinessCategory.food,
            prepType: PrepType.madeToOrder,
          ),
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              ordersRepositoryProvider.overrideWithValue(fakeRepo),
              authProvider.overrideWith(() => _FixedAuthNotifier(authState)),
            ],
            child: MaterialApp(
              theme: PxTheme.light(),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: const TextScaler.linear(2.0),
                ),
                child: Scaffold(body: child),
              ),
              home: const OrdersScreen(role: OrdersRole.business),
            ),
          ),
        );

        await tester.pumpAndSettle();

        expect(find.text('PEDIDOS'), findsOneWidget);
        expect(find.text('CD34EF'), findsOneWidget);
        expect(find.text('Cobro en caja'), findsOneWidget);
        expect(find.text('LIVE'), findsOneWidget);
        expect(find.text('Pagado'), findsOneWidget);
        expect(find.text('Preparar'), findsOneWidget);

        await tester.ensureVisible(find.text('Preparar'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Preparar'));
        await tester.pumpAndSettle();

        expect(
          fakeRepo.statusUpdates,
          [('01hxyzab12cd34ef', OrderStatus.preparing)],
        );
        expect(find.text('Preparando'), findsOneWidget);
        expect(find.text('Marcar listo'), findsOneWidget);
      },
    );

    testWidgets('renders empty state when there are no orders', (tester) async {
      final fakeRepo = FakeOrdersRepository();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ordersRepositoryProvider.overrideWithValue(fakeRepo),
          ],
          child: MaterialApp(
            theme: PxTheme.light(),
            home: const Scaffold(
              body: OrdersScreen(role: OrdersRole.customer),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.text('Aún no hay pedidos'), findsOneWidget);
    });
  });
}
