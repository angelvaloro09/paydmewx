import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mocktail/mocktail.dart';
import 'package:paydmex_app/core/api/api_client.dart';
import 'package:paydmex_app/core/api/api_exception.dart';
import 'package:paydmex_app/core/api/formatters.dart';
import 'package:paydmex_app/core/api/models.dart';
import 'package:paydmex_app/core/theme/theme.dart';
import 'package:paydmex_app/core/theme/tokens.dart';
import 'package:paydmex_app/core/ui/px_ui.dart';
import 'package:paydmex_app/main.dart';

class MockApiClient extends Mock implements ApiClient {}

class MockDio extends Mock implements Dio {}

Widget _wrapWithTheme(Widget child) {
  return MaterialApp(
    theme: PxTheme.light(),
    home: Scaffold(
      body: Center(child: child),
    ),
  );
}

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  group('formatMxn', () {
    test('formats centavos to MXN string with 2 decimals and commas', () {
      expect(formatMxn(0), r'$0.00');
      expect(formatMxn(50), r'$0.50');
      expect(formatMxn(8500), r'$85.00');
      expect(formatMxn(123450), r'$1,234.50');
      expect(formatMxn(100000000), r'$1,000,000.00');
      expect(formatMxn(-2550), r'-$25.50');
    });
  });

  group('ApiException mapping', () {
    test('maps {error:{code,message}} payload to es-MX user message', () {
      final ex = ApiException.fromPayload(
        {
          'error': {
            'code': 'INVALID_CREDENTIALS',
            'message': 'Invalid email or password',
          },
        },
        statusCode: 401,
      );

      expect(ex.code, 'INVALID_CREDENTIALS');
      expect(ex.serverMessage, 'Invalid email or password');
      expect(ex.statusCode, 401);
      expect(ex.message, contains('Correo o contraseña incorrectos'));
    });

    test('maps PEY_ERROR and EMAIL_TAKEN codes to friendly es-MX messages', () {
      final peyEx = ApiException.fromPayload(
        {
          'error': {
            'code': 'PEY_ERROR',
            'message': 'upstream error',
          },
        },
        statusCode: 502,
      );
      expect(peyEx.code, 'PEY_ERROR');
      expect(peyEx.message, contains('CoDi'));

      final conflictEx = ApiException.fromPayload(
        {
          'error': {
            'code': 'EMAIL_TAKEN',
            'message': 'Email already registered',
          },
        },
        statusCode: 409,
      );
      expect(conflictEx.code, 'EMAIL_TAKEN');
      expect(conflictEx.message, contains('ya está registrado'));
    });

    test('ApiClient maps DioException with error payload to ApiException',
        () async {
      final mockDio = MockDio();
      when(() => mockDio.interceptors).thenReturn(Interceptors());
      final requestOptions = RequestOptions(path: '/auth/login');
      when(
        () => mockDio.post<Map<String, dynamic>>(
          '/auth/login',
          data: any(named: 'data'),
        ),
      ).thenThrow(
        DioException(
          requestOptions: requestOptions,
          response: Response<Map<String, dynamic>>(
            requestOptions: requestOptions,
            statusCode: 401,
            data: {
              'error': {
                'code': 'INVALID_CREDENTIALS',
                'message': 'Bad credentials',
              },
            },
          ),
          type: DioExceptionType.badResponse,
        ),
      );

      final client = ApiClient(dio: mockDio);
      expect(
        () => client.login(email: 'a@b.mx', password: 'password123'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.code, 'code', 'INVALID_CREDENTIALS')
              .having(
                (e) => e.message,
                'message',
                contains('Correo o contraseña incorrectos'),
              ),
        ),
      );
    });
  });

  group('PxButton', () {
    testWidgets('has semantics label, min tap size >= 52h / >= 48w, and taps',
        (tester) async {
      final handle = tester.ensureSemantics();
      var tapped = false;

      await tester.pumpWidget(
        _wrapWithTheme(
          PxButton(
            label: 'Cobrar ahora',
            semanticLabel: 'Botón cobrar ahora',
            onPressed: () => tapped = true,
          ),
        ),
      );

      final buttonFinder = find.byType(PxButton);
      final size = tester.getSize(buttonFinder);
      expect(size.height, greaterThanOrEqualTo(PxLayout.buttonMinHeight));
      expect(size.width, greaterThanOrEqualTo(PxLayout.minTapTarget));

      expect(
        tester.getSemantics(buttonFinder),
        matchesSemantics(
          label: 'Botón cobrar ahora',
          isButton: true,
          isEnabled: true,
          hasEnabledState: true,
        ),
      );

      await tester.tap(buttonFinder);
      await tester.pump();
      expect(tapped, isTrue);

      handle.dispose();
    });

    testWidgets('loading state disables tap and announces cargando',
        (tester) async {
      final handle = tester.ensureSemantics();
      var tapped = false;

      await tester.pumpWidget(
        _wrapWithTheme(
          PxButton(
            label: 'Guardar',
            loading: true,
            onPressed: () => tapped = true,
          ),
        ),
      );

      final buttonFinder = find.byType(PxButton);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(
        tester.getSemantics(buttonFinder),
        matchesSemantics(
          label: 'Guardar, cargando',
          isButton: true,
          isEnabled: false,
          hasEnabledState: true,
        ),
      );

      await tester.tap(buttonFinder);
      await tester.pump();
      expect(tapped, isFalse);

      handle.dispose();
    });
  });

  group('PxSegmented', () {
    testWidgets('renders options and notifies onChanged when tapped',
        (tester) async {
      var selected = 'cliente';

      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) {
            return _wrapWithTheme(
              PxSegmented<String>(
                semanticGroupLabel: 'Selector de modo',
                value: selected,
                options: const [
                  PxSegmentOption(value: 'cliente', label: 'Cliente'),
                  PxSegmentOption(value: 'negocio', label: 'Negocio'),
                ],
                onChanged: (val) => setState(() => selected = val),
              ),
            );
          },
        ),
      );

      expect(find.text('Cliente'), findsOneWidget);
      expect(find.text('Negocio'), findsOneWidget);

      await tester.tap(find.text('Negocio'));
      await tester.pumpAndSettle();

      expect(selected, 'negocio');
    });
  });

  group('Router redirect', () {
    testWidgets('redirects unauthenticated user from / to /login',
        (tester) async {
      final mockApi = MockApiClient();
      when(() => mockApi.hasToken).thenReturn(false);
      when(() => mockApi.token).thenReturn(null);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiClientProvider.overrideWithValue(mockApi),
          ],
          child: const PaydMexApp(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Entra a tu cuenta'), findsOneWidget);
      expect(find.text('Iniciar sesión'), findsOneWidget);
    });

    testWidgets('authenticated user lands on shell with DiscoverScreen',
        (tester) async {
      final mockApi = MockApiClient();
      when(() => mockApi.hasToken).thenReturn(true);
      when(() => mockApi.token).thenReturn('fake-jwt');
      when(() => mockApi.getMe()).thenAnswer(
        (_) async => const MeResponse(
          user: User(id: 'u1', email: 'ana@test.mx', name: 'Ana'),
          business: null,
        ),
      );
      when(
        () => mockApi.listBusinesses(
          category: any(named: 'category'),
          prepType: any(named: 'prepType'),
          query: any(named: 'query'),
        ),
      ).thenAnswer(
        (_) async => const [
          Business(
            id: 'b1',
            name: 'Tacos El Güero',
            category: BusinessCategory.food,
            prepType: PrepType.instant,
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiClientProvider.overrideWithValue(mockApi),
          ],
          child: const PaydMexApp(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Descubre negocios locales'), findsOneWidget);
      expect(find.text('Tacos El Güero'), findsOneWidget);
    });
  });
}
