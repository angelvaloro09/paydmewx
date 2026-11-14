import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:paydmex_app/core/api/api_exception.dart';
import 'package:paydmex_app/core/api/models.dart';
import 'package:paydmex_app/core/theme/theme.dart';
import 'package:paydmex_app/core/ui/px_qr_card.dart';
import 'package:paydmex_app/features/auth/auth_controller.dart';
import 'package:paydmex_app/features/checkout/cart_controller.dart';
import 'package:paydmex_app/features/checkout/checkout_controller.dart';
import 'package:paydmex_app/features/checkout/checkout_models.dart';
import 'package:paydmex_app/features/checkout/checkout_repository.dart';
import 'package:paydmex_app/features/checkout/checkout_sheet.dart';
import 'package:paydmex_app/features/discover/business_detail_screen.dart';
import 'package:paydmex_app/features/discover/discover_controller.dart';

class FakeCheckoutRepository implements CheckoutRepository {
  Completer<CheckoutOrder>? createOrderCompleter;
  CheckoutOrder nextCreatedOrder = const CheckoutOrder(
    id: 'ord_test_1',
    totalCents: 7500,
    status: CheckoutOrderStatus.pendingPayment,
  );
  CheckoutPayResponse nextPayResponse = const CheckoutPayResponse(
    qrString: '00020101021226580010MX.CODI.QR0136ord_test_1',
    codiQrId: 'idc_test_1',
    expiresAt: 1600,
    amountCents: 7500,
  );
  CheckoutOrder nextPolledOrder = const CheckoutOrder(
    id: 'ord_test_1',
    totalCents: 7500,
    status: CheckoutOrderStatus.pendingPayment,
  );

  ApiException? createOrderError;
  String? lastBusinessId;
  List<CheckoutOrderItemInput> lastItems = const [];
  String? lastNote;
  int cancelCalls = 0;
  int simulatePaidCalls = 0;

  @override
  Future<CheckoutOrder> createOrder({
    required String businessId,
    required List<CheckoutOrderItemInput> items,
    String? note,
  }) async {
    lastBusinessId = businessId;
    lastItems = items;
    lastNote = note;
    if (createOrderError != null) {
      throw createOrderError!;
    }
    if (createOrderCompleter != null) {
      return createOrderCompleter!.future;
    }
    return nextCreatedOrder;
  }

  @override
  Future<CheckoutPayResponse> createPaymentQr(String orderId) async {
    return nextPayResponse;
  }

  @override
  Future<CheckoutOrder> getOrder(String orderId) async {
    return nextPolledOrder;
  }

  @override
  Future<void> cancelOrder(String orderId) async {
    cancelCalls += 1;
  }

  @override
  Future<void> simulatePaid(String orderId) async {
    simulatePaidCalls += 1;
    nextPolledOrder = CheckoutOrder(
      id: orderId,
      totalCents: nextPayResponse.amountCents,
      status: CheckoutOrderStatus.paid,
    );
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

  const tacoPastor = Product(
    id: 'prod_taco',
    businessId: 'biz_1',
    name: 'Taco al pastor',
    priceCents: 2500,
    trackStock: true,
    stock: 3,
    prepMinutes: 10,
  );

  const aguaHorchata = Product(
    id: 'prod_agua',
    businessId: 'biz_1',
    name: 'Agua de horchata',
    priceCents: 3000,
    trackStock: false,
    stock: 0,
  );

  const flanAgotado = Product(
    id: 'prod_flan',
    businessId: 'biz_1',
    name: 'Flan casero',
    priceCents: 4000,
    trackStock: true,
    stock: 0,
  );

  const cobroRapido = Product(
    id: 'prod_fast',
    businessId: 'biz_1',
    name: 'Cobro rapido',
    priceCents: 1,
    trackStock: false,
    stock: 0,
  );

  const testBusiness = Business(
    id: 'biz_1',
    ownerId: 'owner_1',
    name: 'Taquería El Sol',
    category: BusinessCategory.food,
    prepType: PrepType.madeToOrder,
    description: 'Tacos al carbón y aguas frescas',
  );

  group('CartNotifier & checkout models', () {
    test('cart add/remove/cap by stock/total in centavos and business switch',
        () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(cartProvider.notifier);

      // Add Taco al pastor (2500c, stock 3) four times -> capped at 3
      notifier.addProduct(tacoPastor, businessId: 'biz_1');
      notifier.addProduct(tacoPastor, businessId: 'biz_1');
      notifier.addProduct(tacoPastor, businessId: 'biz_1');
      notifier.addProduct(tacoPastor, businessId: 'biz_1');

      var state = container.read(cartProvider);
      expect(state.qtyForProduct(tacoPastor.id), 3);
      expect(state.totalItems, 3);
      expect(state.totalCents, 7500);

      // Add Agua de horchata (3000c, trackStock: false)
      notifier.addProduct(aguaHorchata, businessId: 'biz_1');
      state = container.read(cartProvider);
      expect(state.totalItems, 4);
      expect(state.totalCents, 10500);

      // Out of stock product cannot be added
      notifier.addProduct(flanAgotado, businessId: 'biz_1');
      expect(container.read(cartProvider).qtyForProduct(flanAgotado.id), 0);

      // Internal 'Cobro rapido' cannot be added and is filtered out
      notifier.addProduct(cobroRapido, businessId: 'biz_1');
      expect(container.read(cartProvider).qtyForProduct(cobroRapido.id), 0);
      final visible = filterVisibleCustomerProducts([
        tacoPastor,
        aguaHorchata,
        flanAgotado,
        cobroRapido,
      ]);
      expect(visible.map((p) => p.name), isNot(contains('Cobro rapido')));
      expect(visible.length, 3);

      // Decrement Taco al pastor from 3 -> 2
      notifier.decrementProduct(tacoPastor.id);
      state = container.read(cartProvider);
      expect(state.qtyForProduct(tacoPastor.id), 2);
      expect(state.totalCents, 8000);

      // Decrement Agua de horchata from 1 -> removed
      notifier.decrementProduct(aguaHorchata.id);
      state = container.read(cartProvider);
      expect(state.qtyForProduct(aguaHorchata.id), 0);
      expect(state.totalCents, 5000);

      // Switching business clears the previous business cart
      notifier.setNote('Sin cebolla');
      notifier.setBusiness('biz_2', businessName: 'Panadería Luna');
      state = container.read(cartProvider);
      expect(state.isEmpty, isTrue);
      expect(state.businessId, 'biz_2');
      expect(state.note, isEmpty);
    });
  });

  group('CheckoutNotifier', () {
    test('happy path: creating -> waiting -> paid clears cart and announces',
        () async {
      final fakeRepo = FakeCheckoutRepository()
        ..createOrderCompleter = Completer<CheckoutOrder>();

      final container = ProviderContainer(
        overrides: [
          checkoutRepositoryProvider.overrideWithValue(fakeRepo),
          checkoutClockProvider.overrideWithValue(() => 1000),
        ],
      );
      addTearDown(container.dispose);

      // Populate cart: 3 tacos = 7500 centavos ($75.00)
      final cartNotifier = container.read(cartProvider.notifier);
      cartNotifier.addProduct(tacoPastor, businessId: 'biz_1');
      cartNotifier.addProduct(tacoPastor, businessId: 'biz_1');
      cartNotifier.addProduct(tacoPastor, businessId: 'biz_1');
      cartNotifier.setNote('Con todo');

      final checkoutNotifier = container.read(checkoutProvider.notifier);
      final startFuture = checkoutNotifier.startCheckout(businessId: 'biz_1');

      // Immediately enters creating phase
      expect(container.read(checkoutProvider).phase, CheckoutPhase.creating);
      expect(container.read(checkoutProvider).amountCents, 7500);

      // Complete order creation -> transitions to waiting
      fakeRepo.createOrderCompleter!.complete(
        const CheckoutOrder(
          id: 'ord_test_1',
          totalCents: 7500,
          status: CheckoutOrderStatus.pendingPayment,
        ),
      );
      await startFuture;

      final waitingState = container.read(checkoutProvider);
      expect(waitingState.phase, CheckoutPhase.waiting);
      expect(waitingState.orderId, 'ord_test_1');
      expect(waitingState.qrString, isNotEmpty);
      expect(waitingState.remainingSeconds, 600);
      expect(fakeRepo.lastBusinessId, 'biz_1');
      expect(fakeRepo.lastNote, 'Con todo');
      expect(fakeRepo.lastItems.single.productId, tacoPastor.id);
      expect(fakeRepo.lastItems.single.qty, 3);

      // Poll returns paid -> transitions to paid, clears cart, sets announcement
      fakeRepo.nextPolledOrder = const CheckoutOrder(
        id: 'ord_test_1',
        totalCents: 7500,
        status: CheckoutOrderStatus.paid,
      );
      await checkoutNotifier.pollOrderStatus();

      final paidState = container.read(checkoutProvider);
      expect(paidState.phase, CheckoutPhase.paid);
      expect(paidState.lastAnnouncement, 'Pago recibido por 75 pesos');
      expect(container.read(cartProvider).isEmpty, isTrue);
    });

    test('expired path when QR expires or poll returns expired', () async {
      final fakeRepo = FakeCheckoutRepository()
        ..nextPayResponse = const CheckoutPayResponse(
          qrString: 'CODI_EXPIRED_QR',
          codiQrId: 'idc_exp_1',
          expiresAt: 1005,
          amountCents: 2500,
        );

      final container = ProviderContainer(
        overrides: [
          checkoutRepositoryProvider.overrideWithValue(fakeRepo),
          checkoutClockProvider.overrideWithValue(() => 1000),
        ],
      );
      addTearDown(container.dispose);

      container
          .read(cartProvider.notifier)
          .addProduct(tacoPastor, businessId: 'biz_1');

      final notifier = container.read(checkoutProvider.notifier);
      await notifier.startCheckout(businessId: 'biz_1');
      expect(container.read(checkoutProvider).phase, CheckoutPhase.waiting);

      // Server reports expired on poll
      fakeRepo.nextPolledOrder = const CheckoutOrder(
        id: 'ord_test_1',
        totalCents: 2500,
        status: CheckoutOrderStatus.expired,
      );
      await notifier.pollOrderStatus();

      final expiredState = container.read(checkoutProvider);
      expect(expiredState.phase, CheckoutPhase.expired);
      expect(expiredState.remainingSeconds, 0);
      // Cart remains intact so user can retry
      expect(container.read(cartProvider).totalCents, 2500);
    });

    test('409 stock conflict surfaces API serverMessage', () async {
      final fakeRepo = FakeCheckoutRepository()
        ..createOrderError = ApiException.fromPayload(
          const {
            'error': {
              'code': 'CONFLICT',
              'message': 'Solo quedan 2 unidades de Taco al pastor',
            },
          },
          statusCode: 409,
        );

      final container = ProviderContainer(
        overrides: [
          checkoutRepositoryProvider.overrideWithValue(fakeRepo),
        ],
      );
      addTearDown(container.dispose);

      container
          .read(cartProvider.notifier)
          .addProduct(tacoPastor, businessId: 'biz_1');

      await container
          .read(checkoutProvider.notifier)
          .startCheckout(businessId: 'biz_1');

      final errState = container.read(checkoutProvider);
      expect(errState.phase, CheckoutPhase.error);
      expect(
        errState.errorMessage,
        'Solo quedan 2 unidades de Taco al pastor',
      );
    });
  });

  group('BusinessDetailScreen, CartSheet & CheckoutSheet widgets', () {
    testWidgets(
        'hides Cobro rapido, shows Agotado badge, steppers update cart bar, opens cart & checkout sheets',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final fakeRepo = FakeCheckoutRepository();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            businessDetailProvider('biz_1').overrideWith(
              (ref) async => const BusinessDetailData(
                business: testBusiness,
                products: [
                  tacoPastor,
                  aguaHorchata,
                  flanAgotado,
                  cobroRapido,
                ],
              ),
            ),
            checkoutRepositoryProvider.overrideWithValue(fakeRepo),
            checkoutClockProvider.overrideWithValue(() => 1000),
          ],
          child: MaterialApp(
            theme: PxTheme.light(),
            home: const BusinessDetailScreen(businessId: 'biz_1'),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // 'Cobro rapido' is hidden
      expect(find.text('Cobro rapido'), findsNothing);
      // Visible products are shown
      expect(find.text('Taco al pastor'), findsOneWidget);
      expect(find.text('Agua de horchata'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('Flan casero'),
        150,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Flan casero'), findsOneWidget);
      // Out of stock product shows 'Agotado' badge
      expect(find.text('Agotado'), findsOneWidget);

      // Floating cart bar is hidden when cart is empty
      expect(find.textContaining('Ver pedido'), findsNothing);

      // Tap '+ Agregar Taco al pastor' twice
      final addTacoFinder = find.bySemanticsLabel('Agregar Taco al pastor');
      expect(addTacoFinder, findsOneWidget);
      await tester.tap(addTacoFinder);
      await tester.pump();
      await tester.tap(addTacoFinder);
      await tester.pump();

      // Floating cart bar appears with 'Ver pedido (2) - $50.00'
      final cartBarFinder = find.text('Ver pedido (2) - \$50.00');
      expect(cartBarFinder, findsOneWidget);

      // Tap floating bar to open CartSheet
      await tester.tap(cartBarFinder);
      await tester.pumpAndSettle();

      expect(find.text('Pagar con CoDi'), findsOneWidget);
      expect(find.text('Nota para el negocio (opcional)'), findsOneWidget);

      // Tap 'Pagar con CoDi' -> opens CheckoutSheet with PxQrCard
      await tester.tap(find.text('Pagar con CoDi'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      expect(find.byType(CheckoutSheet), findsOneWidget);
      expect(find.byType(PxQrCard), findsOneWidget);
    });

    testWidgets('business owner viewing their own business sees no steppers',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authProvider.overrideWith(
              () => _FixedAuthNotifier(
                const AuthState(
                  status: AuthStatus.authenticated,
                  business: testBusiness,
                ),
              ),
            ),
            businessDetailProvider('biz_1').overrideWith(
              (ref) async => const BusinessDetailData(
                business: testBusiness,
                products: [tacoPastor, aguaHorchata],
              ),
            ),
          ],
          child: MaterialApp(
            theme: PxTheme.light(),
            home: const BusinessDetailScreen(businessId: 'biz_1'),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Taco al pastor'), findsOneWidget);
      expect(find.bySemanticsLabel('Agregar Taco al pastor'), findsNothing);
      expect(find.bySemanticsLabel('Quitar Taco al pastor'), findsNothing);
    });
  });
}
