import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../api/formatters.dart';
import '../theme/theme.dart';
import '../theme/tokens.dart';
import 'px_badge.dart';
import 'px_button.dart';
import 'px_card.dart';

/// Builds the accessible screen-reader label for a CoDi QR code:
/// e.g. 8500 -> "Código QR CoDi por 85 pesos con 00 centavos".
String formatCodiQrSemanticLabel(int amountCents) {
  final safeCents = amountCents < 0 ? 0 : amountCents;
  final pesos = safeCents ~/ 100;
  final centavos = (safeCents % 100).toString().padLeft(2, '0');
  return 'Código QR CoDi por $pesos pesos con $centavos centavos';
}

/// Formats seconds remaining as tabular mm:ss, e.g. 599 -> "09:59".
String formatCountdownMmSs(int remainingSeconds) {
  final clamped = remainingSeconds < 0 ? 0 : remainingSeconds;
  final minutes = (clamped ~/ 60).toString().padLeft(2, '0');
  final seconds = (clamped % 60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}

/// Card that renders a live CoDi QR on a white tile (>= 260dp) with quiet zone,
/// tabular amount, countdown timer with icon+label, and cancel action.
class PxQrCard extends StatelessWidget {
  final String qrString;
  final int amountCents;
  final int remainingSeconds;
  final VoidCallback? onCancel;
  final Widget? demoAction;

  const PxQrCard({
    super.key,
    required this.qrString,
    required this.amountCents,
    required this.remainingSeconds,
    this.onCancel,
    this.demoAction,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.pxColors;
    final qrSemanticLabel = formatCodiQrSemanticLabel(amountCents);
    final countdownText = formatCountdownMmSs(remainingSeconds);
    final isLowTime = remainingSeconds <= 60;

    return PxCard(
      padding: const EdgeInsets.all(PxSpacing.s24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Flexible(
                child: PxBadge(
                  label: 'CoDi QR',
                  semanticLabel: 'Cobro con código QR CoDi',
                  tone: PxBadgeTone.info,
                  icon: Icons.qr_code_2_rounded,
                ),
              ),
              const SizedBox(width: PxSpacing.s8),
              Semantics(
                label: 'Tiempo restante $countdownText',
                excludeSemantics: true,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: PxSpacing.s12,
                    vertical: PxSpacing.s4,
                  ),
                  decoration: BoxDecoration(
                    color: isLowTime
                        ? colors.cempasuchil.withValues(alpha: 0.18)
                        : colors.surface2,
                    borderRadius: PxRadius.brPill,
                    border: Border.all(
                      color: isLowTime ? colors.cempasuchil : colors.line,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isLowTime
                            ? Icons.error_outline_rounded
                            : Icons.timer_outlined,
                        size: 14,
                        color: isLowTime ? colors.ink : colors.inkMuted,
                      ),
                      const SizedBox(width: PxSpacing.s4),
                      Text(
                        countdownText,
                        style: PxTheme.monoStyle(
                          fontSize: PxTypographyTokens.micro,
                          fontWeight: FontWeight.w600,
                          color: colors.ink,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: PxSpacing.s16),
          Semantics(
            label: 'Monto a cobrar ${formatMxn(amountCents)}',
            excludeSemantics: true,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                formatMxn(amountCents),
                style: PxTheme.moneyStyle(
                  fontSize: PxTypographyTokens.h1Mobile,
                  color: colors.ink,
                ),
              ),
            ),
          ),
          const SizedBox(height: PxSpacing.s4),
          Text(
            'Muestra este código a tu cliente para pagar desde su app bancaria.',
            textAlign: TextAlign.center,
            style: context.pxText.bodyMedium?.copyWith(
              color: colors.inkMuted,
            ),
          ),
          const SizedBox(height: PxSpacing.s24),
          Semantics(
            image: true,
            label: qrSemanticLabel,
            excludeSemantics: true,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minWidth: 260,
                minHeight: 260,
              ),
              child: Container(
                width: 260,
                height: 260,
                padding: const EdgeInsets.all(PxSpacing.s16),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFFFFF),
                  borderRadius: PxRadius.brLg,
                  border: Border.all(
                    color: colors.line,
                    width: colors.isHighContrast ? 2 : 1,
                  ),
                ),
                child: Center(
                  child: QrImageView(
                    data: qrString.isEmpty ? 'CODI' : qrString,
                    version: QrVersions.auto,
                    size: 228,
                    padding: EdgeInsets.zero,
                    backgroundColor: const Color(0xFFFFFFFF),
                    eyeStyle: const QrEyeStyle(
                      eyeShape: QrEyeShape.square,
                      color: Color(0xFF0A0A0A),
                    ),
                    dataModuleStyle: const QrDataModuleStyle(
                      dataModuleShape: QrDataModuleShape.square,
                      color: Color(0xFF0A0A0A),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: PxSpacing.s24),
          if (demoAction != null) ...[
            demoAction!,
            const SizedBox(height: PxSpacing.s12),
          ],
          if (onCancel != null)
            PxButton(
              label: 'Cancelar',
              semanticLabel: 'Cancelar cobro',
              variant: PxButtonVariant.ghost,
              icon: Icons.close_rounded,
              fullWidth: true,
              onPressed: onCancel,
            ),
        ],
      ),
    );
  }
}
