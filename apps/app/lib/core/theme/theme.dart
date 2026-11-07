import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'tokens.dart';

class ThemeSettings {
  final ThemeMode themeMode;
  final bool highContrast;

  const ThemeSettings({
    this.themeMode = ThemeMode.system,
    this.highContrast = false,
  });

  ThemeSettings copyWith({
    ThemeMode? themeMode,
    bool? highContrast,
  }) {
    return ThemeSettings(
      themeMode: themeMode ?? this.themeMode,
      highContrast: highContrast ?? this.highContrast,
    );
  }
}

final sharedPreferencesProvider = Provider<SharedPreferences?>((ref) => null);

class ThemeSettingsNotifier extends Notifier<ThemeSettings> {
  static const _themeModeKey = 'px_theme_mode';
  static const _highContrastKey = 'px_high_contrast';

  @override
  ThemeSettings build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    if (prefs == null) {
      return const ThemeSettings();
    }
    final modeStr = prefs.getString(_themeModeKey);
    final hc = prefs.getBool(_highContrastKey) ?? false;
    final mode = switch (modeStr) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
    return ThemeSettings(themeMode: mode, highContrast: hc);
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    state = state.copyWith(themeMode: mode);
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs?.setString(_themeModeKey, mode.name);
  }

  Future<void> setHighContrast(bool enabled) async {
    state = state.copyWith(highContrast: enabled);
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs?.setBool(_highContrastKey, enabled);
  }
}

final themeSettingsProvider =
    NotifierProvider<ThemeSettingsNotifier, ThemeSettings>(
  ThemeSettingsNotifier.new,
);

class PxTheme {
  static TextStyle monoStyle({
    double fontSize = PxTypographyTokens.micro,
    FontWeight fontWeight = FontWeight.w500,
    Color? color,
    double letterSpacing = 0.0,
    bool tabular = true,
  }) {
    return GoogleFonts.jetBrainsMono(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      letterSpacing: letterSpacing,
      fontFeatures: tabular ? const [FontFeature.tabularFigures()] : null,
    );
  }

  static TextStyle eyebrowStyle(Color color) {
    return GoogleFonts.jetBrainsMono(
      fontSize: PxTypographyTokens.micro,
      fontWeight: FontWeight.w500,
      color: color,
      letterSpacing: PxTypographyTokens.micro * 0.08,
      height: 1.2,
    );
  }

  static TextStyle moneyStyle({
    required double fontSize,
    required Color color,
    FontWeight fontWeight = FontWeight.w600,
  }) {
    return GoogleFonts.jetBrainsMono(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      height: 1.1,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
  }

  static TextTheme buildTextTheme(PxColors colors, {bool isWebWide = false}) {
    return TextTheme(
      displayLarge: GoogleFonts.instrumentSans(
        fontSize: isWebWide
            ? PxTypographyTokens.displayWeb
            : PxTypographyTokens.displayMobile,
        fontWeight: FontWeight.w400,
        height: PxTypographyTokens.lineHeightDisplay,
        color: colors.ink,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
      headlineLarge: GoogleFonts.instrumentSans(
        fontSize:
            isWebWide ? PxTypographyTokens.h1Web : PxTypographyTokens.h1Mobile,
        fontWeight: FontWeight.w600,
        height: PxTypographyTokens.lineHeightHeading,
        color: colors.ink,
      ),
      headlineMedium: GoogleFonts.instrumentSans(
        fontSize:
            isWebWide ? PxTypographyTokens.h2Web : PxTypographyTokens.h2Mobile,
        fontWeight: FontWeight.w600,
        height: PxTypographyTokens.lineHeightHeading,
        color: colors.ink,
      ),
      headlineSmall: GoogleFonts.instrumentSans(
        fontSize:
            isWebWide ? PxTypographyTokens.h3Web : PxTypographyTokens.h3Mobile,
        fontWeight: FontWeight.w600,
        height: 1.25,
        color: colors.ink,
      ),
      titleLarge: GoogleFonts.instrumentSans(
        fontSize: PxTypographyTokens.h3Mobile,
        fontWeight: FontWeight.w600,
        height: 1.3,
        color: colors.ink,
      ),
      titleMedium: GoogleFonts.instrumentSans(
        fontSize: PxTypographyTokens.body,
        fontWeight: FontWeight.w600,
        height: 1.4,
        color: colors.ink,
      ),
      bodyLarge: GoogleFonts.instrumentSans(
        fontSize: PxTypographyTokens.body,
        fontWeight: FontWeight.w400,
        height: PxTypographyTokens.lineHeightBody,
        color: colors.ink,
      ),
      bodyMedium: GoogleFonts.instrumentSans(
        fontSize: PxTypographyTokens.small,
        fontWeight: FontWeight.w400,
        height: PxTypographyTokens.lineHeightBody,
        color: colors.ink,
      ),
      bodySmall: GoogleFonts.instrumentSans(
        fontSize: PxTypographyTokens.micro,
        fontWeight: FontWeight.w400,
        height: 1.4,
        color: colors.inkMuted,
      ),
      labelLarge: GoogleFonts.instrumentSans(
        fontSize: PxTypographyTokens.body,
        fontWeight: FontWeight.w600,
        height: 1.2,
        color: colors.ink,
      ),
      labelSmall: eyebrowStyle(colors.inkMuted),
    );
  }

  static ThemeData light({bool highContrast = false}) {
    final c = highContrast ? PxColors.lightHighContrast : PxColors.light;
    return _fromColors(c, Brightness.light);
  }

  static ThemeData dark({bool highContrast = false}) {
    final c = highContrast ? PxColors.darkHighContrast : PxColors.dark;
    return _fromColors(c, Brightness.dark);
  }

  static ThemeData _fromColors(PxColors c, Brightness brightness) {
    final surfaceSolid = brightness == Brightness.dark
        ? Color.alphaBlend(c.surface, c.bg)
        : c.surface;
    final colorScheme = ColorScheme(
      brightness: brightness,
      primary: c.brand,
      onPrimary: c.onBrand,
      secondary: c.codi,
      onSecondary: brightness == Brightness.dark ? c.onBrand : Colors.white,
      tertiary: c.rosa,
      onTertiary: Colors.white,
      error: c.danger,
      onError: Colors.white,
      surface: surfaceSolid,
      onSurface: c.ink,
      onSurfaceVariant: c.inkMuted,
      outline: c.line,
    );

    final textTheme = buildTextTheme(c);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: c.bg,
      colorScheme: colorScheme,
      textTheme: textTheme,
      extensions: [c],
      dividerColor: c.line,
      splashFactory: NoSplash.splashFactory,
      appBarTheme: AppBarTheme(
        backgroundColor: c.bg,
        foregroundColor: c.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: surfaceSolid,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: PxRadius.brXl,
          side: BorderSide(color: c.line, width: c.isHighContrast ? 1.5 : 1),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surfaceSolid,
        indicatorColor: c.brand.withValues(alpha: 0.2),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return GoogleFonts.instrumentSans(
            fontSize: PxTypographyTokens.micro,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            color: selected ? c.ink : c.inkMuted,
          );
        }),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: surfaceSolid,
        indicatorColor: c.brand.withValues(alpha: 0.2),
        selectedIconTheme: IconThemeData(color: c.ink),
        unselectedIconTheme: IconThemeData(color: c.inkMuted),
        selectedLabelTextStyle: GoogleFonts.instrumentSans(
          fontSize: PxTypographyTokens.small,
          fontWeight: FontWeight.w600,
          color: c.ink,
        ),
        unselectedLabelTextStyle: GoogleFonts.instrumentSans(
          fontSize: PxTypographyTokens.small,
          fontWeight: FontWeight.w500,
          color: c.inkMuted,
        ),
      ),
    );
  }

  /// Ensures MediaQuery.textScaler is never clamped below 2.0 (200%).
  static MediaQueryData preserveAccessibleTextScale(MediaQueryData mq) {
    return mq;
  }
}

extension PxThemeContext on BuildContext {
  PxColors get pxColors =>
      Theme.of(this).extension<PxColors>() ?? PxColors.light;
  TextTheme get pxText => Theme.of(this).textTheme;
}
