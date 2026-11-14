import 'package:flutter/material.dart';

import '../theme/theme.dart';
import '../theme/tokens.dart';

enum PxBadgeTone { brand, attention, info, danger, neutral }

/// Status badge that always renders color + icon + label (never color alone).
class PxBadge extends StatelessWidget {
  final String label;
  final String? semanticLabel;
  final PxBadgeTone tone;
  final IconData? icon;

  const PxBadge({
    super.key,
    required this.label,
    this.semanticLabel,
    this.tone = PxBadgeTone.neutral,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.pxColors;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final (Color bg, Color fg, IconData defaultIcon) = switch (tone) {
      PxBadgeTone.brand => (
          colors.brand.withValues(alpha: isDark ? 0.2 : 0.16),
          colors.brandText,
          Icons.bolt_rounded,
        ),
      PxBadgeTone.attention => (
          colors.cempasuchil.withValues(alpha: isDark ? 0.22 : 0.18),
          isDark ? colors.cempasuchil : const Color(0xFF9A4700),
          Icons.schedule_rounded,
        ),
      PxBadgeTone.info => (
          colors.codi.withValues(alpha: isDark ? 0.22 : 0.14),
          isDark ? colors.codi : const Color(0xFF1747B8),
          Icons.qr_code_2_rounded,
        ),
      PxBadgeTone.danger => (
          colors.danger.withValues(alpha: isDark ? 0.22 : 0.14),
          colors.danger,
          Icons.error_outline_rounded,
        ),
      PxBadgeTone.neutral => (
          colors.surface2,
          colors.ink,
          Icons.label_outline_rounded,
        ),
    };

    return Semantics(
      label: semanticLabel ?? label,
      container: true,
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: PxSpacing.s12,
          vertical: PxSpacing.s4,
        ),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: PxRadius.brPill,
          border: Border.all(
            color: fg.withValues(alpha: colors.isHighContrast ? 0.8 : 0.3),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon ?? defaultIcon, size: 14, color: fg),
            const SizedBox(width: PxSpacing.s4),
            Flexible(
              child: Text(
                label,
                style: PxTheme.monoStyle(
                  fontSize: PxTypographyTokens.micro,
                  fontWeight: FontWeight.w600,
                  color: fg,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
