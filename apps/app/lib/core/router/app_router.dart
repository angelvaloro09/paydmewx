import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/auth_controller.dart';
import '../../features/auth/login_screen.dart';
import '../../features/auth/register_screen.dart';
import '../../features/convert/convert_screen.dart';
import '../../features/discover/business_detail_screen.dart';
import '../../features/home/home_shell_screen.dart';
import '../ui/px_splash.dart';

class _RouterRefreshNotifier extends ChangeNotifier {
  _RouterRefreshNotifier(Ref ref) {
    ref.listen<AuthState>(authProvider, (_, _) {
      notifyListeners();
    });
  }
}

final appRouterProvider = Provider<GoRouter>((ref) {
  final refreshNotifier = _RouterRefreshNotifier(ref);
  ref.onDispose(refreshNotifier.dispose);

  return GoRouter(
    initialLocation: '/',
    refreshListenable: refreshNotifier,
    redirect: (context, state) {
      final auth = ref.read(authProvider);
      final location = state.matchedLocation;

      if (!auth.splashSeen) {
        return location == '/splash' ? null : '/splash';
      }

      final isAuthRoute = location == '/login' || location == '/register';
      final isSplashRoute = location == '/splash';

      if (!auth.isAuthenticated) {
        if (isAuthRoute || isSplashRoute) return null;
        return '/login';
      }

      if (isAuthRoute) {
        return '/';
      }

      return null;
    },
    routes: [
      GoRoute(
        path: '/splash',
        builder: (context, state) => PxSplash(
          onFinished: () {
            ref.read(authProvider.notifier).markSplashSeen();
            final isAuthed = ref.read(authProvider).isAuthenticated;
            context.go(isAuthed ? '/' : '/login');
          },
        ),
      ),
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/register',
        builder: (context, state) => const RegisterScreen(),
      ),
      GoRoute(
        path: '/',
        builder: (context, state) => const HomeShellScreen(),
      ),
      GoRoute(
        path: '/b/:businessId',
        builder: (context, state) {
          final id = state.pathParameters['businessId'] ?? '';
          return BusinessDetailScreen(businessId: id);
        },
      ),
      GoRoute(
        path: '/convert',
        builder: (context, state) => const ConvertBusinessScreen(),
      ),
    ],
  );
});
