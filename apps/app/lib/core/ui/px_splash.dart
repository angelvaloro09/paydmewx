import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/motion.dart';
import '../theme/theme.dart';
import '../theme/tokens.dart';
import 'px_button.dart';

/// PaydMex splash screen: mark pulses in a ring (<= 1.2s, skippable, reduce-motion aware).
class PxSplash extends StatefulWidget {
  final VoidCallback onFinished;
  final Duration duration;

  const PxSplash({
    super.key,
    required this.onFinished,
    this.duration = const Duration(milliseconds: 1100),
  });

  @override
  State<PxSplash> createState() => _PxSplashState();
}

class _PxSplashState extends State<PxSplash>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  Timer? _timer;
  bool _completed = false;

  @override
  void initState() {
    super.initState();
    final clampedDuration = widget.duration > PxMotion.splashMax
        ? PxMotion.splashMax
        : widget.duration;
    _controller = AnimationController(
      vsync: this,
      duration: clampedDuration,
    )..repeat(reverse: true);
    _timer = Timer(clampedDuration, _finish);
  }

  void _finish() {
    if (_completed || !mounted) return;
    _completed = true;
    _timer?.cancel();
    widget.onFinished();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.pxColors;
    final reduceMotion = PxMotion.reduceMotion(context);

    return Scaffold(
      backgroundColor: colors.bg,
      body: SafeArea(
        child: Semantics(
          label: 'PaydMex cargando',
          child: Stack(
            children: [
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedBuilder(
                      animation: _controller,
                      builder: (context, child) {
                        final t = reduceMotion ? 0.5 : _controller.value;
                        final ringScale = 1.0 + (t * 0.25);
                        final ringAlpha = (1.0 - (t * 0.65)).clamp(0.15, 1.0);
                        return SizedBox(
                          width: 120,
                          height: 120,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              Transform.scale(
                                scale: ringScale,
                                child: Container(
                                  width: 88,
                                  height: 88,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: colors.brand
                                          .withValues(alpha: ringAlpha),
                                      width: 2.5,
                                    ),
                                  ),
                                ),
                              ),
                              Container(
                                width: 72,
                                height: 72,
                                decoration: BoxDecoration(
                                  color: colors.brand,
                                  shape: BoxShape.circle,
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  r'$',
                                  style: PxTheme.moneyStyle(
                                    fontSize: 36,
                                    color: colors.onBrand,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: PxSpacing.s24),
                    Text(
                      'PaydMex',
                      style: context.pxText.headlineMedium?.copyWith(
                        color: colors.ink,
                      ),
                    ),
                    const SizedBox(height: PxSpacing.s8),
                    Text(
                      'Cobra y compra en segundos.',
                      style: context.pxText.bodyMedium?.copyWith(
                        color: colors.inkMuted,
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                right: PxSpacing.s24,
                bottom: PxSpacing.s24,
                child: PxButton(
                  label: 'Omitir',
                  semanticLabel: 'Omitir animación de inicio',
                  variant: PxButtonVariant.ghost,
                  onPressed: _finish,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
