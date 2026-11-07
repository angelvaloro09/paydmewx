import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/router/app_router.dart';
import 'core/theme/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
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
