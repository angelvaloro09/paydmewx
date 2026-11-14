import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/theme.dart';

enum AppMode {
  cliente('cliente', 'Cliente'),
  negocio('negocio', 'Negocio');

  final String storageValue;
  final String labelEs;
  const AppMode(this.storageValue, this.labelEs);

  static AppMode fromStorage(String? value) {
    return value == 'negocio' ? AppMode.negocio : AppMode.cliente;
  }
}

class AppModeNotifier extends Notifier<AppMode> {
  static const _modeKey = 'px_app_mode';

  @override
  AppMode build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    return AppMode.fromStorage(prefs?.getString(_modeKey));
  }

  Future<void> setMode(AppMode mode) async {
    state = mode;
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs?.setString(_modeKey, mode.storageValue);
  }
}

final appModeProvider = NotifierProvider<AppModeNotifier, AppMode>(
  AppModeNotifier.new,
);
