import 'package:flutter/material.dart';

/// Single source of truth for PaydMex design tokens (Colors, Radius, Spacing, Layout, Shadows).
@immutable
class PxColors extends ThemeExtension<PxColors> {
  final Color bg;
  final Color surface;
  final Color surface2;
  final Color ink;
  final Color inkMuted;
  final Color line;
  final Color brand;
  final Color brandText;
  final Color onBrand;
  final Color cempasuchil;
  final Color rosa;
  final Color codi;
  final Color danger;
  final bool isHighContrast;

  const PxColors({
    required this.bg,
    required this.surface,
    required this.surface2,
    required this.ink,
    required this.inkMuted,
    required this.line,
    required this.brand,
    required this.brandText,
    required this.onBrand,
    required this.cempasuchil,
    required this.rosa,
    required this.codi,
    required this.danger,
    this.isHighContrast = false,
  });

  static const PxColors light = PxColors(
    bg: Color(0xFFFAF9F6),
    surface: Color(0xFFFFFFFF),
    surface2: Color(0xFFF1EFEA),
    ink: Color(0xFF0A0A0A),
    inkMuted: Color(0xFF5B5B57),
    line: Color(0x1A0A0A0A), // rgba(10,10,10,.10)
    brand: Color(0xFF00C853),
    brandText: Color(0xFF00763A), // >= 4.5:1 on light
    onBrand: Color(0xFF0A0A0A),
    cempasuchil: Color(0xFFFF8A1F),
    rosa: Color(0xFFE4007C),
    codi: Color(0xFF2F6BFF),
    danger: Color(0xFFD92D20),
  );

  static const PxColors dark = PxColors(
    bg: Color(0xFF0B0B0C),
    surface: Color(0x0AFFFFFF), // rgba(255,255,255,.04)
    surface2: Color(0x14FFFFFF), // rgba(255,255,255,.08)
    ink: Color(0xFFF5F4F0),
    inkMuted: Color(0xFFA3A39E),
    line: Color(0x1AFFFFFF), // rgba(255,255,255,.10)
    brand: Color(0xFF19E36B),
    brandText: Color(0xFF19E36B),
    onBrand: Color(0xFF0A0A0A),
    cempasuchil: Color(0xFFFFA04D),
    rosa: Color(0xFFFF3D9A),
    codi: Color(0xFF6C9BFF),
    danger: Color(0xFFFF6B5E),
  );

  static const PxColors lightHighContrast = PxColors(
    bg: Color(0xFFFFFFFF),
    surface: Color(0xFFFFFFFF),
    surface2: Color(0xFFE6E4DF),
    ink: Color(0xFF000000),
    inkMuted: Color(0xFF262624),
    line: Color(0x66000000),
    brand: Color(0xFF00A844),
    brandText: Color(0xFF005C2D),
    onBrand: Color(0xFF000000),
    cempasuchil: Color(0xFFC85A00),
    rosa: Color(0xFFB80062),
    codi: Color(0xFF0044D6),
    danger: Color(0xFFB41C10),
    isHighContrast: true,
  );

  static const PxColors darkHighContrast = PxColors(
    bg: Color(0xFF000000),
    surface: Color(0xFF141416),
    surface2: Color(0xFF242428),
    ink: Color(0xFFFFFFFF),
    inkMuted: Color(0xFFDCDCD6),
    line: Color(0x66FFFFFF),
    brand: Color(0xFF25F278),
    brandText: Color(0xFF25F278),
    onBrand: Color(0xFF000000),
    cempasuchil: Color(0xFFFFB370),
    rosa: Color(0xFFFF6BB0),
    codi: Color(0xFF8FB2FF),
    danger: Color(0xFFFF857A),
    isHighContrast: true,
  );

  LinearGradient get aiGradient => LinearGradient(
        colors: [rosa, cempasuchil],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );

  @override
  PxColors copyWith({
    Color? bg,
    Color? surface,
    Color? surface2,
    Color? ink,
    Color? inkMuted,
    Color? line,
    Color? brand,
    Color? brandText,
    Color? onBrand,
    Color? cempasuchil,
    Color? rosa,
    Color? codi,
    Color? danger,
    bool? isHighContrast,
  }) {
    return PxColors(
      bg: bg ?? this.bg,
      surface: surface ?? this.surface,
      surface2: surface2 ?? this.surface2,
      ink: ink ?? this.ink,
      inkMuted: inkMuted ?? this.inkMuted,
      line: line ?? this.line,
      brand: brand ?? this.brand,
      brandText: brandText ?? this.brandText,
      onBrand: onBrand ?? this.onBrand,
      cempasuchil: cempasuchil ?? this.cempasuchil,
      rosa: rosa ?? this.rosa,
      codi: codi ?? this.codi,
      danger: danger ?? this.danger,
      isHighContrast: isHighContrast ?? this.isHighContrast,
    );
  }

  @override
  PxColors lerp(ThemeExtension<PxColors>? other, double t) {
    if (other is! PxColors) return this;
    return PxColors(
      bg: Color.lerp(bg, other.bg, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surface2: Color.lerp(surface2, other.surface2, t)!,
      ink: Color.lerp(ink, other.ink, t)!,
      inkMuted: Color.lerp(inkMuted, other.inkMuted, t)!,
      line: Color.lerp(line, other.line, t)!,
      brand: Color.lerp(brand, other.brand, t)!,
      brandText: Color.lerp(brandText, other.brandText, t)!,
      onBrand: Color.lerp(onBrand, other.onBrand, t)!,
      cempasuchil: Color.lerp(cempasuchil, other.cempasuchil, t)!,
      rosa: Color.lerp(rosa, other.rosa, t)!,
      codi: Color.lerp(codi, other.codi, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      isHighContrast: t < 0.5 ? isHighContrast : other.isHighContrast,
    );
  }
}

class PxRadius {
  static const double sm = 8.0;
  static const double md = 12.0;
  static const double lg = 16.0;
  static const double input = 16.0;
  static const double xl = 24.0;
  static const double pill = 999.0;

  static const BorderRadius brSm = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius brMd = BorderRadius.all(Radius.circular(md));
  static const BorderRadius brLg = BorderRadius.all(Radius.circular(lg));
  static const BorderRadius brInput = BorderRadius.all(Radius.circular(input));
  static const BorderRadius brXl = BorderRadius.all(Radius.circular(xl));
  static const BorderRadius brPill = BorderRadius.all(Radius.circular(pill));
}

class PxSpacing {
  static const double s4 = 4.0;
  static const double s8 = 8.0;
  static const double s12 = 12.0;
  static const double s16 = 16.0;
  static const double s24 = 24.0;
  static const double s32 = 32.0;
  static const double s48 = 48.0;
  static const double s64 = 64.0;
}

class PxLayout {
  static const double minTapTarget = 48.0;
  static const double buttonMinHeight = 52.0;
  static const double railBreakpoint = 900.0;
  static const double maxContentWidth = 1120.0;
}

class PxShadows {
  static const List<BoxShadow> floating = [
    BoxShadow(
      color: Color(0x2E000000), // rgba(0,0,0,.18)
      offset: Offset(0, 8),
      blurRadius: 24,
    ),
    BoxShadow(
      color: Color(0x1F000000), // rgba(0,0,0,.12)
      offset: Offset(0, 2),
      blurRadius: 6,
    ),
  ];
}

class PxTypographyTokens {
  static const double displayMobile = 56.0;
  static const double displayWeb = 120.0;
  static const double h1Mobile = 40.0;
  static const double h1Web = 72.0;
  static const double h2Mobile = 28.0;
  static const double h2Web = 48.0;
  static const double h3Mobile = 20.0;
  static const double h3Web = 28.0;
  static const double body = 16.0;
  static const double small = 14.0;
  static const double micro = 12.0;

  static const double lineHeightDisplay = 1.0;
  static const double lineHeightHeading = 1.15;
  static const double lineHeightBody = 1.5;
}
