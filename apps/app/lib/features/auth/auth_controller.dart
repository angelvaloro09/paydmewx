import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_exception.dart';
import '../../core/api/models.dart';

enum AuthStatus { unauthenticated, authenticated }

class AuthState {
  final AuthStatus status;
  final User? user;
  final Business? business;
  final bool isLoading;
  final String? error;
  final bool splashSeen;

  const AuthState({
    this.status = AuthStatus.unauthenticated,
    this.user,
    this.business,
    this.isLoading = false,
    this.error,
    this.splashSeen = true,
  });

  bool get isAuthenticated => status == AuthStatus.authenticated;
  bool get hasBusiness => business != null;

  AuthState copyWith({
    AuthStatus? status,
    User? user,
    Business? business,
    bool clearBusiness = false,
    bool? isLoading,
    String? error,
    bool clearError = false,
    bool? splashSeen,
  }) {
    return AuthState(
      status: status ?? this.status,
      user: user ?? this.user,
      business: clearBusiness ? null : (business ?? this.business),
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
      splashSeen: splashSeen ?? this.splashSeen,
    );
  }
}

class AuthNotifier extends Notifier<AuthState> {
  @override
  AuthState build() {
    final api = ref.watch(apiClientProvider);
    if (api.hasToken) {
      Future.microtask(refreshMe);
      return const AuthState(
        status: AuthStatus.authenticated,
        splashSeen: true,
      );
    }
    return const AuthState(
      status: AuthStatus.unauthenticated,
      splashSeen: true,
    );
  }

  void markSplashSeen() {
    state = state.copyWith(splashSeen: true);
  }

  Future<void> refreshMe() async {
    final api = ref.read(apiClientProvider);
    if (!api.hasToken) return;
    try {
      final me = await api.getMe();
      state = state.copyWith(
        status: AuthStatus.authenticated,
        user: me.user,
        business: me.business,
        clearError: true,
      );
    } on ApiException catch (e) {
      if (e.statusCode == 401 || e.code == 'UNAUTHORIZED') {
        await api.setToken(null);
        state = const AuthState(
          status: AuthStatus.unauthenticated,
          splashSeen: true,
        );
      }
    } catch (_) {
      // Keep current session state on transient network error
    }
  }

  Future<bool> login({
    required String email,
    required String password,
  }) async {
    final api = ref.read(apiClientProvider);
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final auth = await api.login(email: email, password: password);
      Business? business;
      User user = auth.user;
      try {
        final me = await api.getMe();
        user = me.user.id.isNotEmpty ? me.user : auth.user;
        business = me.business;
      } catch (_) {
        // Fallback to login user if /me is unavailable
      }
      state = state.copyWith(
        status: AuthStatus.authenticated,
        user: user,
        business: business,
        isLoading: false,
        clearError: true,
      );
      return true;
    } on ApiException catch (e) {
      state = state.copyWith(isLoading: false, error: e.message);
      return false;
    } catch (_) {
      state = state.copyWith(
        isLoading: false,
        error: 'No pudimos iniciar sesión. Intenta de nuevo.',
      );
      return false;
    }
  }

  Future<bool> register({
    required String name,
    required String email,
    required String password,
  }) async {
    final api = ref.read(apiClientProvider);
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final auth = await api.register(
        email: email,
        password: password,
        name: name,
      );
      state = state.copyWith(
        status: AuthStatus.authenticated,
        user: auth.user,
        clearBusiness: true,
        isLoading: false,
        clearError: true,
      );
      return true;
    } on ApiException catch (e) {
      state = state.copyWith(isLoading: false, error: e.message);
      return false;
    } catch (_) {
      state = state.copyWith(
        isLoading: false,
        error: 'No pudimos crear tu cuenta. Intenta de nuevo.',
      );
      return false;
    }
  }

  void setBusiness(Business business) {
    state = state.copyWith(business: business);
  }

  Future<void> logout() async {
    final api = ref.read(apiClientProvider);
    await api.setToken(null);
    state = const AuthState(
      status: AuthStatus.unauthenticated,
      splashSeen: true,
    );
  }
}

final authProvider = NotifierProvider<AuthNotifier, AuthState>(
  AuthNotifier.new,
);
