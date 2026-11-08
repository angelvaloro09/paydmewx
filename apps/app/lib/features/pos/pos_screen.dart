import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/formatters.dart';
import '../../core/theme/motion.dart';
import '../../core/theme/theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/ui/px_badge.dart';
import '../../core/ui/px_button.dart';
import '../../core/ui/px_card.dart';
import '../../core/ui/px_numpad.dart';
import '../../core/ui/px_qr_card.dart';
import '../../core/ui/px_stat.dart';
import 'pos_controller.dart';
import 'pos_models.dart';
import 'widgets/pos_paid_card.dart';

const bool kPosDemoMode = bool.fromEnvironment('DEMO_MODE');

class PosScreen extends ConsumerWidget {
  final bool? demoModeOverride;

  const PosScreen({
    super.key,
    this.demoModeOverride,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(posProvider);
    final notifier = ref.read(posProvider.notifier);
    final showDemoButton = demoModeOverride ?? kPosDemoMode;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= PxLayout.railBreakpoint;
        final horizontalPadding = isWide ? PxSpacing.s32 : PxSpacing.s16;
        final verticalPadding = isWide ? PxSpacing.s32 : PxSpacing.s16;

        return SingleChildScrollView(
          padding: EdgeInsets.symmetric(
            horizontal: horizontalPadding,
            vertical: verticalPadding,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: PxLayout.maxContentWidth,
              ),
              child: AnimatedSwitcher(
                duration: PxMotion.duration(context, PxMotion.base),
                switchInCurve: PxMotion.easeOut,
                switchOutCurve: PxMotion.easeStd,
                child: switch (state.phase) {
                  PosPhase.entry => _PosEntryView(
                      key: const ValueKey<String>('pos_phase_entry'),
                      state: state,
                      isWide: isWide,
                      onDigit: notifier.inputDigit,
                      onBackspace: notifier.backspace,
                      onClear: notifier.clear,
                      onCharge: state.canCharge
                          ? () => notifier.startCharge()
                          : null,
                    ),
                  PosPhase.creating => _PosCreatingView(
                      key: const ValueKey<String>('pos_phase_creating'),
                      amountCents: state.amountCents,
                    ),
                  PosPhase.waiting => _PosWaitingView(
                      key: const ValueKey<String>('pos_phase_waiting'),
                      state: state,
                      showDemoButton: showDemoButton,
                      onCancel: () => notifier.cancelWaitingOrder(),
                      onSimulatePaid: () => notifier.simulateDemoPayment(),
                    ),
                  PosPhase.paid => ConstrainedBox(
                      key: const ValueKey<String>('pos_phase_paid'),
                      constraints: const BoxConstraints(maxWidth: 460),
                      child: PosPaidCard(
                        amountCents: state.amountCents,
                        onNewCharge: notifier.newCharge,
                      ),
                    ),
                  PosPhase.expired => _PosTerminalStatusView(
                      key: const ValueKey<String>('pos_phase_expired'),
                      badgeLabel: 'QR expirado',
                      badgeTone: PxBadgeTone.attention,
                      badgeIcon: Icons.timer_off_outlined,
                      icon: Icons.timer_off_outlined,
                      title: 'El código QR expiró',
                      message:
                          'El tiempo para realizar el pago terminó. Genera un nuevo código para cobrar ${formatMxn(state.amountCents)}.',
                      onRetry: notifier.retryFromTerminal,
                    ),
                  PosPhase.cancelled => _PosTerminalStatusView(
                      key: const ValueKey<String>('pos_phase_cancelled'),
                      badgeLabel: 'Cobro cancelado',
                      badgeTone: PxBadgeTone.neutral,
                      badgeIcon: Icons.cancel_outlined,
                      icon: Icons.cancel_outlined,
                      title: 'Cobro cancelado',
                      message:
                          'Este cobro se canceló antes de completarse. Puedes iniciar uno nuevo cuando quieras.',
                      onRetry: notifier.retryFromTerminal,
                    ),
                  PosPhase.error => _PosTerminalStatusView(
                      key: const ValueKey<String>('pos_phase_error'),
                      badgeLabel: 'Error al cobrar',
                      badgeTone: PxBadgeTone.danger,
                      badgeIcon: Icons.error_outline_rounded,
                      icon: Icons.error_outline_rounded,
                      title: 'No pudimos generar el QR',
                      message: state.errorMessage ??
                          'No pudimos generar el QR. Intenta de nuevo.',
                      onRetry: notifier.retryFromTerminal,
                    ),
                },
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PosEntryView extends StatelessWidget {
  final PosState state;
  final bool isWide;
  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;
  final VoidCallback onClear;
  final VoidCallback? onCharge;

  const _PosEntryView({
    super.key,
    required this.state,
    required this.isWide,
    required this.onDigit,
    required this.onBackspace,
    required this.onClear,
    required this.onCharge,
  });

  @override
  Widget build(BuildContext context) {
    final formattedAmount = formatMxn(state.amountCents);
    final chargeLabel = 'Cobrar $formattedAmount';

    if (isWide) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 5,
            child: _PosAmountSummaryCard(
              amountCents: state.amountCents,
              formattedAmount: formattedAmount,
              chargeLabel: chargeLabel,
              isWide: true,
              onCharge: onCharge,
              onClear: state.amountCents > 0 ? onClear : null,
            ),
          ),
          const SizedBox(width: PxSpacing.s24),
          Expanded(
            flex: 5,
            child: PxCard(
              padding: const EdgeInsets.all(PxSpacing.s24),
              child: PxNumpad(
                onDigit: onDigit,
                onBackspace: onBackspace,
                onClear: onClear,
              ),
            ),
          ),
        ],
      );
    }

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 460),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PosAmountSummaryCard(
            amountCents: state.amountCents,
            formattedAmount: formattedAmount,
            chargeLabel: chargeLabel,
            isWide: false,
            onCharge: null,
            onClear: state.amountCents > 0 ? onClear : null,
          ),
          const SizedBox(height: PxSpacing.s16),
          PxNumpad(
            onDigit: onDigit,
            onBackspace: onBackspace,
            onClear: onClear,
          ),
          const SizedBox(height: PxSpacing.s16),
          PxButton(
            label: chargeLabel,
            semanticLabel: chargeLabel,
            icon: Icons.qr_code_2_rounded,
            fullWidth: true,
            onPressed: onCharge,
          ),
        ],
      ),
    );
  }
}

class _PosAmountSummaryCard extends StatelessWidget {
  final int amountCents;
  final String formattedAmount;
  final String chargeLabel;
  final bool isWide;
  final VoidCallback? onCharge;
  final VoidCallback? onClear;

  const _PosAmountSummaryCard({
    required this.amountCents,
    required this.formattedAmount,
    required this.chargeLabel,
    required this.isWide,
    required this.onCharge,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.pxColors;
    final hasAmount = amountCents > 0;
    final atMaxCap = amountCents >= kMaxPosAmountCents;

    return PxCard(
      padding: EdgeInsets.all(isWide ? PxSpacing.s32 : PxSpacing.s24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Flexible(
                child: PxEyebrow(text: 'COBRO EN CAJA'),
              ),
              const SizedBox(width: PxSpacing.s8),
              const PxBadge(
                label: 'CoDi QR',
                semanticLabel: 'Cobro instantáneo con CoDi QR',
                tone: PxBadgeTone.info,
                icon: Icons.qr_code_2_rounded,
              ),
            ],
          ),
          const SizedBox(height: PxSpacing.s16),
          Semantics(
            label: 'Monto a cobrar $formattedAmount',
            liveRegion: true,
            excludeSemantics: true,
            child: SizedBox(
              width: double.infinity,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  formattedAmount,
                  key: const ValueKey<String>('pos_amount_display'),
                  style: PxTheme.moneyStyle(
                    fontSize: isWide
                        ? PxTypographyTokens.h1Web
                        : PxTypographyTokens.displayMobile,
                    color: hasAmount ? colors.ink : colors.inkMuted,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: PxSpacing.s8),
          if (atMaxCap)
            Row(
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  size: 16,
                  color: colors.cempasuchil,
                ),
                const SizedBox(width: PxSpacing.s8),
                Flexible(
                  child: Text(
                    'Monto máximo alcanzado (${formatMxn(kMaxPosAmountCents)}).',
                    style: context.pxText.bodySmall?.copyWith(
                      color: colors.ink,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            )
          else
            Text(
              'Cobra en segundos. Ingresa el monto y muestra el QR a tu cliente.',
              style: context.pxText.bodySmall?.copyWith(
                color: colors.inkMuted,
              ),
            ),
          if (isWide) ...[
            const SizedBox(height: PxSpacing.s32),
            PxButton(
              label: chargeLabel,
              semanticLabel: chargeLabel,
              icon: Icons.qr_code_2_rounded,
              fullWidth: true,
              onPressed: onCharge,
            ),
          ],
        ],
      ),
    );
  }
}

class _PosCreatingView extends StatelessWidget {
  final int amountCents;

  const _PosCreatingView({
    super.key,
    required this.amountCents,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.pxColors;
    final reduceMotion = PxMotion.reduceMotion(context);

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 460),
      child: Semantics(
        liveRegion: true,
        label: 'Generando código QR',
        container: true,
        child: PxCard(
          padding: const EdgeInsets.all(PxSpacing.s32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
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
              Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.qr_code_2_rounded,
                    size: 22,
                    color: colors.ink,
                  ),
                  const SizedBox(width: PxSpacing.s8),
                  Flexible(
                    child: Text(
                      'Generando código QR',
                      textAlign: TextAlign.center,
                      style: context.pxText.headlineSmall?.copyWith(
                        color: colors.ink,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: PxSpacing.s8),
              Text(
                'Preparando cobro por ${formatMxn(amountCents)}...',
                textAlign: TextAlign.center,
                style: context.pxText.bodyMedium?.copyWith(
                  color: colors.inkMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PosWaitingView extends StatelessWidget {
  final PosState state;
  final bool showDemoButton;
  final VoidCallback onCancel;
  final VoidCallback onSimulatePaid;

  const _PosWaitingView({
    super.key,
    required this.state,
    required this.showDemoButton,
    required this.onCancel,
    required this.onSimulatePaid,
  });

  @override
  Widget build(BuildContext context) {
    String? politeCountdownAnnouncement;
    if (state.remainingSeconds == 60) {
      politeCountdownAnnouncement = 'Quedan 60 segundos para pagar el código QR';
    } else if (state.remainingSeconds == 10) {
      politeCountdownAnnouncement = 'Quedan 10 segundos para pagar el código QR';
    }

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 460),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (politeCountdownAnnouncement != null)
            Semantics(
              liveRegion: true,
              label: politeCountdownAnnouncement,
              child: const SizedBox.shrink(),
            ),
          PxQrCard(
            qrString: state.qrString ?? '',
            amountCents: state.amountCents,
            remainingSeconds: state.remainingSeconds,
            onCancel: onCancel,
            demoAction: showDemoButton
                ? PxButton(
                    label: 'Simular pago (demo)',
                    semanticLabel: 'Simular pago de demostración',
                    variant: PxButtonVariant.secondary,
                    icon: Icons.bolt_rounded,
                    fullWidth: true,
                    onPressed: onSimulatePaid,
                  )
                : null,
          ),
        ],
      ),
    );
  }
}

class _PosTerminalStatusView extends StatelessWidget {
  final String badgeLabel;
  final PxBadgeTone badgeTone;
  final IconData badgeIcon;
  final IconData icon;
  final String title;
  final String message;
  final VoidCallback onRetry;

  const _PosTerminalStatusView({
    super.key,
    required this.badgeLabel,
    required this.badgeTone,
    required this.badgeIcon,
    required this.icon,
    required this.title,
    required this.message,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.pxColors;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 460),
      child: Semantics(
        liveRegion: true,
        container: true,
        child: PxCard(
          padding: const EdgeInsets.all(PxSpacing.s32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              PxBadge(
                label: badgeLabel,
                tone: badgeTone,
                icon: badgeIcon,
              ),
              const SizedBox(height: PxSpacing.s24),
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: colors.surface2,
                  shape: BoxShape.circle,
                  border: Border.all(color: colors.line),
                ),
                child: Icon(
                  icon,
                  size: 36,
                  color: colors.ink,
                ),
              ),
              const SizedBox(height: PxSpacing.s16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: context.pxText.headlineSmall?.copyWith(
                  color: colors.ink,
                ),
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
                label: 'Intentar de nuevo',
                semanticLabel: 'Intentar de nuevo',
                icon: Icons.refresh_rounded,
                fullWidth: true,
                onPressed: onRetry,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
