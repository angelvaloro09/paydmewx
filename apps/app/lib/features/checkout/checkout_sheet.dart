import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/formatters.dart';
import '../../core/theme/motion.dart';
import '../../core/theme/theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/ui/px_qr_card.dart';
import '../../core/ui/px_ui.dart';
import 'checkout_controller.dart';
import 'checkout_models.dart';

const bool kCheckoutDemoMode = bool.fromEnvironment('DEMO_MODE');

Future<void> showCheckoutSheet(
  BuildContext context, {
  required String businessId,
  bool? demoModeOverride,
  String? existingOrderId,
  int? existingAmountCents,
}) {
  if (existingOrderId != null && existingOrderId.trim().isNotEmpty) {
    ProviderScope.containerOf(context, listen: false)
        .read(checkoutProvider.notifier)
        .startFromExistingOrder(
          orderId: existingOrderId,
          amountCents: existingAmountCents ?? 0,
        );
  }
  final colors = context.pxColors;
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: colors.bg,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(PxRadius.xl),
      ),
    ),
    builder: (sheetContext) => CheckoutSheet(
      businessId: businessId,
      demoModeOverride: demoModeOverride,
    ),
  );
}

class CheckoutSheet extends ConsumerWidget {
  final String businessId;
  final bool? demoModeOverride;

  const CheckoutSheet({
    super.key,
    required this.businessId,
    this.demoModeOverride,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(checkoutProvider);
    final colors = context.pxColors;
    final reduceMotion = PxMotion.reduceMotion(context);
    final isDemoMode = demoModeOverride ?? kCheckoutDemoMode;

    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.only(
          left: PxSpacing.s24,
          right: PxSpacing.s24,
          top: PxSpacing.s16,
          bottom: MediaQuery.viewInsetsOf(context).bottom + PxSpacing.s24,
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: ExcludeSemantics(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: colors.line,
                        borderRadius: PxRadius.brPill,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: PxSpacing.s16),
                Row(
                  children: [
                    const Expanded(
                      child: PxEyebrow(text: 'PAGO CON CODI'),
                    ),
                    Semantics(
                      button: true,
                      label: 'Cerrar ventana de pago',
                      excludeSemantics: true,
                      child: SizedBox(
                        width: PxLayout.minTapTarget,
                        height: PxLayout.minTapTarget,
                        child: IconButton(
                          tooltip: 'Cerrar',
                          icon: Icon(
                            Icons.close_rounded,
                            color: colors.ink,
                          ),
                          onPressed: () {
                            if (state.phase == CheckoutPhase.waiting) {
                              ref
                                  .read(checkoutProvider.notifier)
                                  .cancelWaitingOrder();
                            } else {
                              ref.read(checkoutProvider.notifier).reset();
                            }
                            Navigator.of(context).maybePop();
                          },
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: PxSpacing.s8),
                AnimatedSwitcher(
                  duration: PxMotion.duration(context, PxMotion.base),
                  switchInCurve: PxMotion.easeOut,
                  switchOutCurve: PxMotion.easeStd,
                  child: switch (state.phase) {
                    CheckoutPhase.idle || CheckoutPhase.creating => _CreatingView(
                        key: const ValueKey('checkout_creating'),
                        amountCents: state.amountCents,
                        reduceMotion: reduceMotion,
                      ),
                    CheckoutPhase.waiting => PxQrCard(
                      instruction:
                          'Escanea este código con tu app bancaria para pagar.',
                        key: const ValueKey('checkout_waiting'),
                        qrString: state.qrString ?? '',
                        amountCents: state.amountCents,
                        remainingSeconds: state.remainingSeconds,
                        onCancel: () => ref
                            .read(checkoutProvider.notifier)
                            .cancelWaitingOrder(),
                        demoAction: isDemoMode
                            ? PxButton(
                                label: 'Simular pago (demo)',
                                semanticLabel: 'Simular pago de demostración',
                                variant: PxButtonVariant.secondary,
                                icon: Icons.bolt_rounded,
                                fullWidth: true,
                                onPressed: () => ref
                                    .read(checkoutProvider.notifier)
                                    .simulateDemoPayment(),
                              )
                            : null,
                      ),
                    CheckoutPhase.paid => _PaidView(
                        key: const ValueKey('checkout_paid'),
                        amountCents: state.amountCents,
                        reduceMotion: reduceMotion,
                        onDone: () {
                          ref.read(checkoutProvider.notifier).reset();
                          Navigator.of(context).maybePop();
                        },
                      ),
                    CheckoutPhase.expired => _TerminalStatusView(
                        key: const ValueKey('checkout_expired'),
                        badgeLabel: 'Código expirado',
                        badgeTone: PxBadgeTone.attention,
                        icon: Icons.timer_off_rounded,
                        iconColor: colors.cempasuchil,
                        title: 'El código QR expiró',
                        message:
                            'El tiempo para completar el pago con CoDi terminó. Genera un nuevo código para intentar de nuevo.',
                        onRetry: () => ref
                            .read(checkoutProvider.notifier)
                            .retryCheckout(businessId: businessId),
                        onClose: () {
                          ref.read(checkoutProvider.notifier).reset();
                          Navigator.of(context).maybePop();
                        },
                      ),
                    CheckoutPhase.cancelled => _TerminalStatusView(
                        key: const ValueKey('checkout_cancelled'),
                        badgeLabel: 'Cancelado',
                        badgeTone: PxBadgeTone.danger,
                        icon: Icons.cancel_outlined,
                        iconColor: colors.danger,
                        title: 'Pago cancelado',
                        message:
                            'Cancelaste el cobro con código QR. Tu carrito sigue guardado por si deseas intentar de nuevo.',
                        onRetry: () => ref
                            .read(checkoutProvider.notifier)
                            .retryCheckout(businessId: businessId),
                        onClose: () {
                          ref.read(checkoutProvider.notifier).reset();
                          Navigator.of(context).maybePop();
                        },
                      ),
                    CheckoutPhase.error => _TerminalStatusView(
                        key: const ValueKey('checkout_error'),
                        badgeLabel: 'Error en el cobro',
                        badgeTone: PxBadgeTone.danger,
                        icon: Icons.error_outline_rounded,
                        iconColor: colors.danger,
                        title: 'No pudimos generar el cobro',
                        message: state.errorMessage ??
                            'No pudimos generar el QR. Intenta de nuevo.',
                        onRetry: () => ref
                            .read(checkoutProvider.notifier)
                            .retryCheckout(businessId: businessId),
                        onClose: () {
                          ref.read(checkoutProvider.notifier).reset();
                          Navigator.of(context).maybePop();
                        },
                      ),
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CreatingView extends StatelessWidget {
  final int amountCents;
  final bool reduceMotion;

  const _CreatingView({
    super.key,
    required this.amountCents,
    required this.reduceMotion,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.pxColors;
    return Semantics(
      liveRegion: true,
      label: 'Generando código QR CoDi por ${formatMxn(amountCents)}',
      child: PxCard(
        padding: const EdgeInsets.all(PxSpacing.s24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const PxBadge(
              label: 'CoDi QR',
              tone: PxBadgeTone.info,
              icon: Icons.qr_code_2_rounded,
            ),
            const SizedBox(height: PxSpacing.s24),
            SizedBox(
              width: 48,
              height: 48,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                value: reduceMotion ? 0.75 : null,
                valueColor: AlwaysStoppedAnimation<Color>(colors.brand),
              ),
            ),
            const SizedBox(height: PxSpacing.s24),
            Text(
              'Generando código QR...',
              textAlign: TextAlign.center,
              style: context.pxText.headlineSmall,
            ),
            const SizedBox(height: PxSpacing.s8),
            Text(
              'Estamos preparando tu orden por ${formatMxn(amountCents)}.',
              textAlign: TextAlign.center,
              style: context.pxText.bodyMedium?.copyWith(
                color: colors.inkMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PaidView extends StatelessWidget {
  final int amountCents;
  final bool reduceMotion;
  final VoidCallback onDone;

  const _PaidView({
    super.key,
    required this.amountCents,
    required this.reduceMotion,
    required this.onDone,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.pxColors;
    final spokenConfirmation = formatCheckoutPaidAnnouncement(amountCents);

    return Semantics(
      liveRegion: true,
      label: spokenConfirmation,
      child: PxCard(
        padding: const EdgeInsets.all(PxSpacing.s24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const PxBadge(
              label: 'Pagado con CoDi',
              tone: PxBadgeTone.brand,
              icon: Icons.check_circle_rounded,
            ),
            const SizedBox(height: PxSpacing.s24),
            TweenAnimationBuilder<double>(
              tween: Tween<double>(
                begin: reduceMotion ? 1.0 : 0.75,
                end: 1.0,
              ),
              duration: PxMotion.duration(context, PxMotion.slow),
              curve: PxMotion.easeOut,
              builder: (context, scale, child) {
                return Transform.scale(
                  scale: scale,
                  child: child,
                );
              },
              child: Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: colors.brand,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.check_rounded,
                  size: 44,
                  color: colors.onBrand,
                ),
              ),
            ),
            const SizedBox(height: PxSpacing.s24),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                formatMxn(amountCents),
                style: PxTheme.moneyStyle(
                  fontSize: PxTypographyTokens.h1Mobile,
                  color: colors.ink,
                ),
              ),
            ),
            const SizedBox(height: PxSpacing.s8),
            Text(
              spokenConfirmation,
              textAlign: TextAlign.center,
              style: context.pxText.titleLarge,
            ),
            const SizedBox(height: PxSpacing.s8),
            Text(
              'El pago se registró correctamente.',
              textAlign: TextAlign.center,
              style: context.pxText.bodyMedium?.copyWith(
                color: colors.inkMuted,
              ),
            ),
            const SizedBox(height: PxSpacing.s24),
            PxButton(
              label: 'Listo',
              semanticLabel: 'Listo, cerrar confirmación de pago',
              icon: Icons.check_rounded,
              fullWidth: true,
              onPressed: onDone,
            ),
          ],
        ),
      ),
    );
  }
}

class _TerminalStatusView extends StatelessWidget {
  final String badgeLabel;
  final PxBadgeTone badgeTone;
  final IconData icon;
  final Color iconColor;
  final String title;
  final String message;
  final VoidCallback onRetry;
  final VoidCallback onClose;

  const _TerminalStatusView({
    super.key,
    required this.badgeLabel,
    required this.badgeTone,
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.message,
    required this.onRetry,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.pxColors;
    return Semantics(
      liveRegion: true,
      child: PxCard(
        padding: const EdgeInsets.all(PxSpacing.s24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            PxBadge(
              label: badgeLabel,
              tone: badgeTone,
              icon: icon,
            ),
            const SizedBox(height: PxSpacing.s24),
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.14),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: 32,
                color: iconColor,
              ),
            ),
            const SizedBox(height: PxSpacing.s16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: context.pxText.headlineSmall,
            ),
            const SizedBox(height: PxSpacing.s8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: context.pxText.bodyMedium?.copyWith(
                color: colors.inkMuted,
              ),
            ),
            const SizedBox(height: PxSpacing.s24),
            PxButton(
              label: 'Reintentar',
              semanticLabel: 'Reintentar pago con CoDi',
              icon: Icons.refresh_rounded,
              fullWidth: true,
              onPressed: onRetry,
            ),
            const SizedBox(height: PxSpacing.s12),
            PxButton(
              label: 'Cerrar',
              semanticLabel: 'Cerrar ventana',
              variant: PxButtonVariant.ghost,
              icon: Icons.close_rounded,
              fullWidth: true,
              onPressed: onClose,
            ),
          ],
        ),
      ),
    );
  }
}
