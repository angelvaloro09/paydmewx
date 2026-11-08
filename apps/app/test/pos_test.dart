import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paydmex_app/core/api/models.dart';
import 'package:paydmex_app/core/theme/theme.dart';
import 'package:paydmex_app/core/ui/px_numpad.dart';
import 'package:paydmex_app/features/auth/auth_controller.dart';
import 'package:paydmex_app/features/pos/pos_controller.dart';
import 'package:paydmex_app/features/pos/pos_models.dart';
import 'package:paydmex_app/features/pos/pos_repository.dart';
import 'package:paydmex_app/features/pos/pos_screen.dart';

class _TestAuthNotifier extends AuthNotifier {
  @override
  AuthState build() {
    return const AuthState(
      status: AuthStatus.authenticated,
      user: User(id: 'u_test', email: 'owner@paydmex.mx', name: 'Taqueria Sol'),
      business: Business(
        id: 'biz_test_01',
        name: 'Taqueria Sol',
        category: BusinessCategory.food,
        prepType: PrepType.instant,
      ),
    );
  }
}

class FakePosRepository extends PosRepository {
  int ensureProductCalls = 0;
  int createOrderCalls = 0;
  int createQrCalls = 0;
  int getOrderCalls = 0;
  int cancelOrderCalls = 0;

  PosOrderStatus currentOrderStatus = PosOrderStatus.pendingPayment;
  int expiresInSeconds = 300;
  final int fixedNow;
  Completer<void>? createOrderGate;

  FakePosRepository({this.fixedNow = 1700000000}) : super(Dio());

  @override
  Future<String> ensureQuickChargeProduct() async {
    ensureProductCalls += 1;
    return 'prod_cobro_rapido';
  }

  @override
  Future<PosOrder> createOrder({
    required String businessId,
    required String productId,
    required int amountCents,
  }) async {
    createOrderCalls += 1;
    if (createOrderGate != null) {
      await createOrderGate!.future;
    }
    return PosOrder(
      id: 'ord_test_1',
      totalCents: amountCents,
      status: PosOrderStatus.pendingPayment,
    );
  }

  @override
  Future<PosPayResponse> createPaymentQr(String orderId) async {
    createQrCalls += 1;
    return PosPayResponse(
      qrString: '00020101021229370016MX.CODI.TEST$orderId',
      codiQrId: 'codi_qr_1',
      expiresAt: fixedNow + expiresInSeconds,
      amountCents: 8500,
    );
  }

  @override
  Future<PosOrder> getOrder(String orderId) async {
    getOrderCalls += 1;
    return PosOrder(
      id: orderId,
      totalCents: 8500,
      status: currentOrderStatus,
    );
  }

  @override
  Future<void> cancelOrder(String orderId) async {
    cancelOrderCalls += 1;
  }
}

ProviderContainer _createContainer({
  required FakePosRepository fakeRepo,
  int fixedNow = 1700000000,
}) {
  return ProviderContainer(
    overrides: [
      authProvider.overrideWith(_TestAuthNotifier.new),
      posRepositoryProvider.overrideWithValue(fakeRepo),
      posClockProvider.overrideWithValue(() => fixedNow),
    ],
  );
}

void main() {
  group('POS numpad digit entry, backspace, clear, and cap logic', () {
    test('shifts digits like a calculator and handles backspace/clear/cap', () {
      final fakeRepo = FakePosRepository();
      final container = _createContainer(fakeRepo: fakeRepo);
      addTearDown(container.dispose);

      final notifier = container.read(posProvider.notifier);

      expect(container.read(posProvider).amountCents, 0);
      expect(container.read(posProvider).canCharge, isFalse);

      // Leading zeros do not change 0
      notifier.inputDigit('0');
      notifier.inputDigit('00');
      expect(container.read(posProvider).amountCents, 0);

      // Typing 1, 2, 5 -> 125 centavos ($1.25)
      notifier.inputDigit('1');
      notifier.inputDigit('2');
      notifier.inputDigit('5');
      expect(container.read(posProvider).amountCents, 125);
      expect(container.read(posProvider).canCharge, isTrue);

      // Typing '00' shifts two places -> 12500 ($125.00)
      notifier.inputDigit('00');
      expect(container.read(posProvider).amountCents, 12500);

      // Backspace removes last digit -> 1250 ($12.50)
      notifier.backspace();
      expect(container.read(posProvider).amountCents, 1250);

      // Clear resets to 0
      notifier.clear();
      expect(container.read(posProvider).amountCents, 0);
      expect(container.read(posProvider).canCharge, isFalse);

      // Cap at 5,000,000 centavos ($50,000.00)
      for (final d in ['9', '9', '9', '9', '9', '9', '9']) {
        notifier.inputDigit(d);
      }
      expect(container.read(posProvider).amountCents, kMaxPosAmountCents);

      // Additional digits stay capped at 5,000,000
      notifier.inputDigit('5');
      notifier.inputDigit('00');
      expect(container.read(posProvider).amountCents, kMaxPosAmountCents);
    });
  });

  group('POS controller state flows', () {
    test(
      'happy path transitions entry -> creating -> waiting -> paid and caches product id',
      () async {
        final fakeRepo = FakePosRepository()
          ..createOrderGate = Completer<void>();
        final container = _createContainer(fakeRepo: fakeRepo);
        addTearDown(container.dispose);

        final notifier = container.read(posProvider.notifier);

        // Enter $85.00 (8500 centavos)
        notifier.inputDigit('8');
        notifier.inputDigit('5');
        notifier.inputDigit('00');
        expect(container.read(posProvider).amountCents, 8500);
        expect(container.read(posProvider).phase, PosPhase.entry);

        // Start charge -> creating
        final chargeFuture = notifier.startCharge();
        await Future<void>.delayed(Duration.zero);
        expect(container.read(posProvider).phase, PosPhase.creating);
        expect(
          container.read(posProvider).lastAnnouncement,
          'Generando código QR',
        );

        // Complete order + QR creation -> waiting
        fakeRepo.createOrderGate!.complete();
        await chargeFuture;

        final waitingState = container.read(posProvider);
        expect(waitingState.phase, PosPhase.waiting);
        expect(waitingState.orderId, 'ord_test_1');
        expect(waitingState.qrString, isNotEmpty);
        expect(waitingState.remainingSeconds, 300);
        expect(waitingState.fastChargeProductId, 'prod_cobro_rapido');
        expect(fakeRepo.ensureProductCalls, 1);

        // Simulate payment received on poll -> paid
        fakeRepo.currentOrderStatus = PosOrderStatus.paid;
        await notifier.pollOrderStatus();

        final paidState = container.read(posProvider);
        expect(paidState.phase, PosPhase.paid);
        expect(paidState.lastAnnouncement, 'Pago recibido por 85 pesos');

        // Start a new charge and verify product id remains cached
        notifier.newCharge();
        expect(container.read(posProvider).phase, PosPhase.entry);
        expect(container.read(posProvider).amountCents, 0);
        expect(
          container.read(posProvider).fastChargeProductId,
          'prod_cobro_rapido',
        );
      },
    );

    test('expired path transitions waiting -> expired when order expires',
        () async {
      final fakeRepo = FakePosRepository();
      final container = _createContainer(fakeRepo: fakeRepo);
      addTearDown(container.dispose);

      final notifier = container.read(posProvider.notifier);
      notifier.inputDigit('5');
      notifier.inputDigit('0');
      notifier.inputDigit('00');

      await notifier.startCharge();
      expect(container.read(posProvider).phase, PosPhase.waiting);

      // Server reports expired
      fakeRepo.currentOrderStatus = PosOrderStatus.expired;
      await notifier.pollOrderStatus();

      expect(container.read(posProvider).phase, PosPhase.expired);
      expect(container.read(posProvider).remainingSeconds, 0);

      // Retry returns to entry keeping amount so owner can retry immediately
      notifier.retryFromTerminal();
      expect(container.read(posProvider).phase, PosPhase.entry);
      expect(container.read(posProvider).amountCents, 5000);
    });
  });

  group('PxNumpad semantics and interaction', () {
    testWidgets('exposes Spanish semantic labels for all 12 keys',
        (tester) async {
      final semanticsHandle = tester.ensureSemantics();

      final digits = <String>[];
      var backspaces = 0;
      var clears = 0;

      await tester.pumpWidget(
        MaterialApp(
          theme: PxTheme.light(),
          home: Scaffold(
            body: PxNumpad(
              onDigit: digits.add,
              onBackspace: () => backspaces += 1,
              onClear: () => clears += 1,
            ),
          ),
        ),
      );

      const expectedLabels = [
        'uno',
        'dos',
        'tres',
        'cuatro',
        'cinco',
        'seis',
        'siete',
        'ocho',
        'nueve',
        'doble cero',
        'cero',
        'borrar',
      ];

      for (final label in expectedLabels) {
        expect(
          find.bySemanticsLabel(label),
          findsOneWidget,
          reason: 'Expected semantics label "$label" on PxNumpad',
        );
      }

      await tester.tap(find.bySemanticsLabel('ocho'));
      await tester.tap(find.bySemanticsLabel('cinco'));
      await tester.tap(find.bySemanticsLabel('doble cero'));
      expect(digits, ['8', '5', '00']);

      await tester.tap(find.bySemanticsLabel('borrar'));
      expect(backspaces, 1);

      await tester.longPress(find.bySemanticsLabel('borrar'));
      expect(clears, 1);

      semanticsHandle.dispose();
    });

    testWidgets('PosScreen renders at 200% text scale without overflow',
        (tester) async {
      final fakeRepo = FakePosRepository();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authProvider.overrideWith(_TestAuthNotifier.new),
            posRepositoryProvider.overrideWithValue(fakeRepo),
          ],
          child: MaterialApp(
            theme: PxTheme.light(),
            home: const MediaQuery(
              data: MediaQueryData(
                size: Size(390, 844),
                textScaler: TextScaler.linear(2.0),
              ),
              child: Scaffold(
                body: PosScreen(),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Cobrar \$0.00'), findsOneWidget);
    });
  });
}
