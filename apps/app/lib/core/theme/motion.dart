import 'package:flutter/widgets.dart';

/// Motion tokens from docs/DESIGN_SYSTEM.md
class PxMotion {
  /// cubic-bezier(.215, .61, .355, 1) — entrances (Cash App reference)
  static const Curve easeOut = Cubic(0.215, 0.61, 0.355, 1.0);

  /// cubic-bezier(.4, 0, .2, 1) — state changes (Luma/Optimus reference)
  static const Curve easeStd = Cubic(0.4, 0.0, 0.2, 1.0);

  static const Duration fast = Duration(milliseconds: 150);
  static const Duration base = Duration(milliseconds: 300);
  static const Duration slow = Duration(milliseconds: 600);
  static const Duration hero = Duration(milliseconds: 1000);
  static const Duration splashMax = Duration(milliseconds: 1200);

  /// Returns true when the OS/MediaQuery requests reduced motion.
  static bool reduceMotion(BuildContext context) {
    return MediaQuery.maybeDisableAnimationsOf(context) ?? false;
  }

  /// Resolves a duration respecting OS reduced motion setting:
  /// Under reduced motion, transitions become <= 150ms (or zero if decorative).
  static Duration duration(
    BuildContext context,
    Duration normal, {
    bool zeroWhenReduced = false,
  }) {
    if (reduceMotion(context)) {
      return zeroWhenReduced
          ? Duration.zero
          : (normal > fast ? fast : normal);
    }
    return normal;
  }
}
