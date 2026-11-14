import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/api/api_client.dart';
import 'core/router/app_router.dart';
import 'core/theme/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
    ],
  );
  // Wake the API (Render free tier cold start) without blocking first paint.
  unawaited(container.read(apiClientProvider).warmUp());
  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const PaydMexApp(),
    ),
  );
}

class PaydMexApp extends ConsumerWidget {
  const PaydMexApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeSettings = ref.watch(themeSettingsProvider);
    final router = ref.watch(appRouterProvider);

    return MaterialApp.router(
      title: 'PaydMex',
      debugShowCheckedModeBanner: false,
      themeMode: themeSettings.themeMode,
      theme: PxTheme.light(highContrast: themeSettings.highContrast),
      darkTheme: PxTheme.dark(highContrast: themeSettings.highContrast),
      highContrastTheme: PxTheme.light(highContrast: true),
      highContrastDarkTheme: PxTheme.dark(highContrast: true),
      routerConfig: router,
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        return MediaQuery(
          data: PxTheme.preserveAccessibleTextScale(mq),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
  }
}
