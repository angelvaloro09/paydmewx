import 'package:flutter/material.dart';

import '../../../core/api/formatters.dart';
import '../../../core/theme/motion.dart';
import '../../../core/theme/theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/ui/px_badge.dart';
import '../../../core/ui/px_button.dart';
import '../../../core/ui/px_card.dart';
import '../pos_models.dart';

/// Signature moment 3 ("Cobro exitoso"):
/// Cross-fades to a check inside an expanding ring in `brand`, amount counts up,
/// and announces "Pago recibido por X pesos".
/// Honors `MediaQuery.disableAnimationsOf(context)` with static check + amount.
class PosPaidCard extends StatelessWidget {
  final int amountCents;
  final VoidCallback onNewCharge;

  const PosPaidCard({
    super.key,
    required this.amountCents,
    required this.onNewCharge,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.pxColors;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final spokenAnnouncement = formatPaidAnnouncement(amountCents);

    return Semantics(
      liveRegion: true,
      label: spokenAnnouncement,
      container: true,
      child: PxCard(
        padding: const EdgeInsets.all(PxSpacing.s32),
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(
            begin: reduceMotion ? 1.0 : 0.0,
            end: 1.0,
          ),
          duration: reduceMotion ? Duration.zero : PxMotion.slow,
          curve: PxMotion.easeOut,
          builder: (context, progress, _) {
            final displayedCents = reduceMotion
                ? amountCents
                : (amountCents * progress).round();
            final ringScale = reduceMotion ? 1.0 : (0.75 + 0.65 * progress);
            final ringOpacity = reduceMotion
                ? 0.0
                : (1.0 - progress).clamp(0.0, 1.0) * 0.55;
            final checkScale = reduceMotion
                ? 1.0
                : (0.7 + 0.3 * progress).clamp(0.0, 1.0);

            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const PxBadge(
                  label: 'Cobro exitoso',
                  semanticLabel: 'Estado: Cobro exitoso',
                  tone: PxBadgeTone.brand,
                  icon: Icons.check_circle_outline_rounded,
                ),
                const SizedBox(height: PxSpacing.s24),
                SizedBox(
                  width: 120,
                  height: 120,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      if (!reduceMotion && ringOpacity > 0)
                        Transform.scale(
                          scale: ringScale,
                          child: Container(
                            width: 88,
                            height: 88,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: colors.brand.withValues(
                                  alpha: ringOpacity,
                                ),
                                width: 4,
                              ),
                            ),
                          ),
                        ),
                      Transform.scale(
                        scale: checkScale,
                        child: Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            color: colors.brand,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.check_rounded,
                            size: 40,
                            color: colors.onBrand,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: PxSpacing.s16),
                Text(
                  '¡Cobrado!',
                  textAlign: TextAlign.center,
                  style: context.pxText.headlineMedium?.copyWith(
                    color: colors.ink,
                  ),
                ),
                const SizedBox(height: PxSpacing.s8),
                Semantics(
                  label: spokenAnnouncement,
                  excludeSemantics: true,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      '+${formatMxn(displayedCents)}',
                      style: PxTheme.moneyStyle(
                        fontSize: PxTypographyTokens.h1Mobile,
                        color: colors.ink,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: PxSpacing.s8),
                Text(
                  'El pago por CoDi se acreditó correctamente.',
                  textAlign: TextAlign.center,
                  style: context.pxText.bodyMedium?.copyWith(
                    color: colors.inkMuted,
                  ),
                ),
                const SizedBox(height: PxSpacing.s32),
                PxButton(
                  label: 'Nuevo cobro',
                  semanticLabel: 'Nuevo cobro',
                  icon: Icons.add_rounded,
                  fullWidth: true,
                  onPressed: onNewCharge,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
