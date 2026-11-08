import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:paydmex_app/core/api/api_client.dart';
import 'package:paydmex_app/core/api/api_exception.dart';
import 'package:paydmex_app/core/api/models.dart';
import 'package:paydmex_app/core/theme/theme.dart';
import 'package:paydmex_app/core/ui/px_ai_orb.dart';
import 'package:paydmex_app/features/ai/ai_assistant_screen.dart';
import 'package:paydmex_app/features/ai/ai_controller.dart';
import 'package:paydmex_app/features/ai/ai_models.dart';
import 'package:paydmex_app/features/ai/ai_repository.dart';
import 'package:paydmex_app/features/auth/auth_controller.dart';
import 'package:paydmex_app/features/checkout/checkout_controller.dart';
import 'package:paydmex_app/features/checkout/checkout_models.dart';
import 'package:paydmex_app/features/checkout/checkout_repository.dart';

class _RecordedAssistCall {
  final String message;
  final List<AiMessage> history;

  const _RecordedAssistCall({
    required this.message,
    required this.history,
  });
}

class _FakeAiRepository implements AiRepository {
  final List<_RecordedAssistCall> calls = [];
  Future<AiAssistResponse> Function(String message, List<AiMessage> history)?
      handler;

  @override
  Future<AiAssistResponse> assist({
    required String message,
    List<AiMessage> history = const [],
  }) {
    calls.add(
      _RecordedAssistCall(
        message: message,
        history: List<AiMessage>.unmodifiable(history),
      ),
    );
    if (handler != null) {
      return handler!(message, history);
    }
    return Future.value(
      AiAssistResponse(reply: 'Respuesta para: $message'),
    );
  }
}

class _FakeAuthNotifier extends AuthNotifier {
  final AuthState initialState;

  _FakeAuthNotifier(this.initialState);

  @override
  AuthState build() => initialState;
}

class _FakeCheckoutRepository implements CheckoutRepository {
  int createOrderCalls = 0;
  final List<String> paidOrderIds = [];

  @override
  Future<CheckoutOrder> createOrder({
    required String businessId,
    required List<CheckoutOrderItemInput> items,
    String? note,
  }) async {
    createOrderCalls++;
    return const CheckoutOrder(
      id: 'ord_should_not_be_called',
      totalCents: 5000,
      status: CheckoutOrderStatus.pendingPayment,
    );
  }

  @override
  Future<CheckoutPayResponse> createPaymentQr(String orderId) async {
    paidOrderIds.add(orderId);
    return const CheckoutPayResponse(
      qrString: '00020101021240340010A00000080201160123456789ABCDEF',
      codiQrId: 'idc_ai_01',
      expiresAt: 2000,
      amountCents: 9000,
    );
  }

  @override
  Future<CheckoutOrder> getOrder(String orderId) async {
    return CheckoutOrder(
      id: orderId,
      totalCents: 9000,
      status: CheckoutOrderStatus.pendingPayment,
    );
  }

  @override
  Future<void> cancelOrder(String orderId) async {}

  @override
  Future<void> simulatePaid(String orderId) async {}
}

const User _testUser = User(
  id: 'usr_01',
  email: 'tacos@paydmex.mx',
  name: 'Taqueria El Sol',
);

const Business _testBusiness = Business(
  id: 'biz_01',
  ownerId: 'usr_01',
  name: 'Taqueria El Sol',
  category: BusinessCategory.food,
  prepType: PrepType.instant,
  active: true,
);

Widget _buildTestHarness({
  required Widget child,
  required _FakeAiRepository aiRepo,
  required AuthState authState,
  _FakeCheckoutRepository? checkoutRepo,
  bool disableAnimations = false,
  double textScale = 1.0,
}) {
  return ProviderScope(
    key: UniqueKey(),
    overrides: [
      apiClientProvider.overrideWithValue(ApiClient()),
      aiRepositoryProvider.overrideWithValue(aiRepo),
      authProvider.overrideWith(() => _FakeAuthNotifier(authState)),
      checkoutRepositoryProvider.overrideWithValue(
        checkoutRepo ?? _FakeCheckoutRepository(),
      ),
      checkoutClockProvider.overrideWithValue(() => 1400),
    ],
    child: MaterialApp(
      theme: PxTheme.light(),
      builder: (context, appChild) {
        final mq = MediaQuery.of(context);
        return MediaQuery(
          data: mq.copyWith(
            disableAnimations: disableAnimations,
            textScaler: TextScaler.linear(textScale),
          ),
          child: Scaffold(body: appChild),
        );
      },
      home: child,
    ),
  );
}

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  group('AiNotifier & history', () {
    test(
      'send flow appends user message, sets loading, appends assistant reply, trimmed history to 10, and clears on logout',
      () async {
        final fakeRepo = _FakeAiRepository();
        final container = ProviderContainer(
          overrides: [
            apiClientProvider.overrideWithValue(ApiClient()),
            aiRepositoryProvider.overrideWithValue(fakeRepo),
            authProvider.overrideWith(
              () => _FakeAuthNotifier(
                const AuthState(
                  status: AuthStatus.authenticated,
                  user: _testUser,
                  business: _testBusiness,
                ),
              ),
            ),
          ],
        );
        addTearDown(container.dispose);

        final notifier = container.read(aiProvider.notifier);

        // Send 6 user messages (6 user + 6 assistant = 12 messages in state).
        for (var i = 1; i <= 6; i++) {
          fakeRepo.handler = (msg, history) async {
            return AiAssistResponse(reply: 'Respuesta $i');
          };
          await notifier.sendMessage('Mensaje $i');
        }

        expect(container.read(aiProvider).messages.length, 12);

        // 7th send: prior state has 12 messages, history sent to repository must be trimmed to last 10.
        final completer = Completer<AiAssistResponse>();
        fakeRepo.handler = (msg, history) => completer.future;

        final future = notifier.sendMessage('Mensaje 7');

        // While in flight: user message is already appended and isSending is true.
        final sendingState = container.read(aiProvider);
        expect(sendingState.isSending, isTrue);
        expect(sendingState.messages.last.role, AiRole.user);
        expect(sendingState.messages.last.content, 'Mensaje 7');

        expect(fakeRepo.calls.last.message, 'Mensaje 7');
        expect(fakeRepo.calls.last.history.length, 10);
        // First 2 messages ('Mensaje 1' and 'Respuesta 1') were trimmed out; starts at 'Mensaje 2'.
        expect(fakeRepo.calls.last.history.first.content, 'Mensaje 2');
        expect(fakeRepo.calls.last.history.last.content, 'Respuesta 6');

        completer.complete(
          const AiAssistResponse(
            reply: 'Respuesta 7',
            actions: [
              AiAction.stockAdjusted(productId: 'prd_1', newStock: 15),
            ],
          ),
        );
        await future;

        final finalState = container.read(aiProvider);
        expect(finalState.isSending, isFalse);
        expect(finalState.messages.last.role, AiRole.assistant);
        expect(finalState.messages.last.content, 'Respuesta 7');
        expect(finalState.messages.last.actions.single.type,
            AiActionType.stockAdjusted);
        expect(finalState.lastAnnouncement, 'Respuesta 7');

        // Logout clears conversation via authProvider listener.
        await container.read(authProvider.notifier).logout();
        expect(container.read(aiProvider).messages, isEmpty);
      },
    );

    test('error message mapping maps 429, 503 LLM_BUSY, 503 AI_NOT_CONFIGURED, 502 LLM_ERROR cleanly', () {
      final busyError = ApiException.fromPayload(
        {
          'error': {
            'code': 'LLM_BUSY',
            'message': 'upstream provider saturated',
          },
        },
        statusCode: 503,
      );
      expect(
        resolveAiErrorMessage(busyError),
        'El asistente esta ocupado, intenta de nuevo en unos segundos',
      );

      final notConfiguredError = ApiException.fromPayload(
        {
          'error': {
            'code': 'AI_NOT_CONFIGURED',
            'message': 'missing LLM_API_KEY',
          },
        },
        statusCode: 503,
      );
      expect(
        resolveAiErrorMessage(notConfiguredError),
        'El asistente no esta disponible en este momento. Intenta mas tarde.',
      );

      final llmError = ApiException.fromPayload(
        {
          'error': {
            'code': 'LLM_ERROR',
            'message': '{"raw":"stacktrace"}',
          },
        },
        statusCode: 502,
      );
      expect(
        resolveAiErrorMessage(llmError),
        'No pudimos obtener respuesta del asistente. Intenta de nuevo en unos segundos.',
      );

      final rateLimitedError = ApiException.fromPayload(
        {
          'error': {
            'code': 'RATE_LIMITED',
            'message': 'too many requests',
          },
        },
        statusCode: 429,
      );
      expect(
        resolveAiErrorMessage(rateLimitedError),
        'Hiciste demasiados intentos seguidos. Espera unos segundos e intenta de nuevo.',
      );
    });
  });

  group('AiAssistantScreen widget tests', () {
    testWidgets(
      'empty state shows greeting and role chips; tapping a chip sends it and shows typing indicator then reply',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final fakeRepo = _FakeAiRepository();
        final completer = Completer<AiAssistResponse>();
        fakeRepo.handler = (msg, history) => completer.future;

        await tester.pumpWidget(
          _buildTestHarness(
            aiRepo: fakeRepo,
            authState: const AuthState(
              status: AuthStatus.authenticated,
              user: _testUser,
              business: _testBusiness,
            ),
            disableAnimations: true,
            child: const AiAssistantScreen(),
          ),
        );

        expect(find.text('Hola, soy tu asistente de PaydMex'), findsOneWidget);
        expect(find.text('Vendi 2 tacos'), findsOneWidget);
        expect(find.text('Que productos tengo?'), findsOneWidget);
        expect(find.text('Cuanto vendi hoy?'), findsOneWidget);

        // Tap suggested prompt chip.
        await tester.tap(find.text('Vendi 2 tacos'));
        await tester.pump();

        expect(fakeRepo.calls.length, 1);
        expect(fakeRepo.calls.single.message, 'Vendi 2 tacos');

        // User bubble and typing indicator are visible while waiting.
        expect(find.text('Vendi 2 tacos'), findsOneWidget);
        expect(find.text('El asistente esta escribiendo'), findsOneWidget);

        completer.complete(
          const AiAssistResponse(
            reply: 'Listo, registre la venta de 2 tacos por \$90.00.',
            actions: [
              AiAction.stockAdjusted(productId: 'prd_taco', newStock: 18),
              AiAction.productCreated(productId: 'prd_new'),
            ],
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('El asistente esta escribiendo'), findsNothing);
        expect(
          find.text('Listo, registre la venta de 2 tacos por \$90.00.'),
          findsOneWidget,
        );
        expect(find.text('Existencias actualizadas'), findsOneWidget);
        expect(find.text('Producto creado'), findsOneWidget);

        // Clear conversation button resets back to empty state.
        await tester.tap(find.bySemanticsLabel('Nueva conversacion'));
        await tester.pumpAndSettle();
        expect(find.text('Hola, soy tu asistente de PaydMex'), findsOneWidget);
      },
    );

    testWidgets(
      'customer empty state shows customer chips, and order_created action renders Cobrar con QR only for owners',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final fakeRepo = _FakeAiRepository();
        fakeRepo.handler = (msg, history) async {
          return const AiAssistResponse(
            reply: 'Tu pedido fue creado.',
            actions: [
              AiAction.orderCreated(
                orderId: 'ord_ai_99',
                totalCents: 9000,
              ),
            ],
          );
        };

        // 1. Customer role (no business):
        await tester.pumpWidget(
          _buildTestHarness(
            aiRepo: fakeRepo,
            authState: const AuthState(
              status: AuthStatus.authenticated,
              user: _testUser,
            ),
            disableAnimations: true,
            child: const AiAssistantScreen(),
          ),
        );

        expect(find.text('Busca comida cerca'), findsOneWidget);
        expect(find.text('Repite mi ultimo pedido'), findsOneWidget);
        expect(find.text('Que negocios hay?'), findsOneWidget);

        await tester.tap(find.text('Repite mi ultimo pedido'));
        await tester.pumpAndSettle();

        expect(find.text('Orden creada por \$90.00'), findsOneWidget);
        expect(find.text('Cobrar con QR'), findsNothing);

        // 2. Owner role (with business):
        final fakeCheckoutRepo = _FakeCheckoutRepository();
        await tester.pumpWidget(
          _buildTestHarness(
            aiRepo: fakeRepo,
            checkoutRepo: fakeCheckoutRepo,
            authState: const AuthState(
              status: AuthStatus.authenticated,
              user: _testUser,
              business: _testBusiness,
            ),
            disableAnimations: true,
            child: const AiAssistantScreen(),
          ),
        );

        // Send message via text field + Enter on web.
        await tester.enterText(find.byType(TextField), 'Vendi 2 tacos');
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();

        expect(find.text('Orden creada por \$90.00'), findsOneWidget);
        expect(find.text('Cobrar con QR'), findsOneWidget);

        // Tapping "Cobrar con QR" skips POST /orders and calls POST /orders/:id/pay directly.
        await tester.tap(find.text('Cobrar con QR'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(fakeCheckoutRepo.createOrderCalls, 0);
        expect(fakeCheckoutRepo.paidOrderIds, ['ord_ai_99']);
      },
    );

    testWidgets(
      'displays friendly es-MX error message on LLM_BUSY and survives 390x844 at 200% text scale',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final fakeRepo = _FakeAiRepository();
        fakeRepo.handler = (msg, history) async {
          throw ApiException.fromPayload(
            {
              'error': {
                'code': 'LLM_BUSY',
                'message': 'rate limit exceeded on upstream',
              },
            },
            statusCode: 503,
          );
        };

        await tester.pumpWidget(
          _buildTestHarness(
            aiRepo: fakeRepo,
            authState: const AuthState(
              status: AuthStatus.authenticated,
              user: _testUser,
              business: _testBusiness,
            ),
            disableAnimations: true,
            textScale: 2.0,
            child: const AiAssistantScreen(),
          ),
        );

        await tester.enterText(find.byType(TextField), 'Hola');
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('ai_send_button')));
        await tester.pumpAndSettle();

        expect(
          find.text('El asistente esta ocupado, intenta de nuevo en unos segundos'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'PxAiOrb animates normally and stays static under reduced motion',
      (tester) async {
        // Normal motion: controller is animating.
        await tester.pumpWidget(
          MaterialApp(
            theme: PxTheme.light(),
            home: const MediaQuery(
              data: MediaQueryData(disableAnimations: false),
              child: Scaffold(
                body: Center(
                  child: PxAiOrb(size: 96, thinking: true),
                ),
              ),
            ),
          ),
        );

        final activeState = tester.state<PxAiOrbState>(find.byType(PxAiOrb));
        expect(activeState.isAnimating, isTrue);

        // Reduced motion: controller stops and scale stays static at 1.0.
        await tester.pumpWidget(
          MaterialApp(
            theme: PxTheme.light(),
            home: const MediaQuery(
              data: MediaQueryData(disableAnimations: true),
              child: Scaffold(
                body: Center(
                  child: PxAiOrb(size: 96, thinking: true),
                ),
              ),
            ),
          ),
        );

        final staticState = tester.state<PxAiOrbState>(find.byType(PxAiOrb));
        expect(staticState.isAnimating, isFalse);

        final coreBefore = tester.widget<Transform>(
          find.byKey(const ValueKey('px_ai_orb_core')),
        );
        final scaleBefore = coreBefore.transform.getMaxScaleOnAxis();

        await tester.pump(const Duration(milliseconds: 900));

        final coreAfter = tester.widget<Transform>(
          find.byKey(const ValueKey('px_ai_orb_core')),
        );
        final scaleAfter = coreAfter.transform.getMaxScaleOnAxis();

        expect(scaleBefore, 1.0);
        expect(scaleAfter, 1.0);
      },
    );
  });
}
