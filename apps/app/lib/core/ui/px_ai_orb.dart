import 'package:flutter/material.dart';

import '../theme/motion.dart';
import '../theme/theme.dart';

/// Decorative AI assistant orb with gradient `rosa -> cempasuchil` and soft glow.
///
/// Idle state: 3s breathing scale loop.
/// Thinking state: faster ring pulse.
/// Reduced motion (`MediaQuery.disableAnimationsOf`): static (scale 1.0, no ticker loop).
class PxAiOrb extends StatefulWidget {
  final double size;
  final bool thinking;

  const PxAiOrb({
    super.key,
    this.size = 96.0,
    this.thinking = false,
  });

  @override
  State<PxAiOrb> createState() => PxAiOrbState();
}

class PxAiOrbState extends State<PxAiOrb> with SingleTickerProviderStateMixin {
  static const Duration breathingDuration = Duration(seconds: 3);
  static const Duration thinkingDuration = Duration(milliseconds: 900);

  late final AnimationController _controller;

  bool get isAnimating => _controller.isAnimating;

  Duration get _targetDuration =>
      widget.thinking ? thinkingDuration : breathingDuration;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: _targetDuration,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncAnimation();
  }

  @override
  void didUpdateWidget(covariant PxAiOrb oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.thinking != widget.thinking) {
      _controller.duration = _targetDuration;
    }
    _syncAnimation();
  }

  void _syncAnimation() {
    final disableAnimations = MediaQuery.disableAnimationsOf(context);
    if (disableAnimations) {
      if (_controller.isAnimating) {
        _controller.stop();
      }
      _controller.value = 0.0;
    } else {
      _controller.duration = _targetDuration;
      if (!_controller.isAnimating) {
        _controller.repeat(reverse: true);
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.pxColors;
    final disableAnimations = MediaQuery.disableAnimationsOf(context);
    final effectiveSize = widget.size;

    return ExcludeSemantics(
      child: SizedBox(
        width: effectiveSize,
        height: effectiveSize,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            final t = disableAnimations
                ? 0.0
                : PxMotion.easeStd.transform(_controller.value);
            final coreScale = disableAnimations
                ? 1.0
                : (widget.thinking ? 0.94 + (t * 0.12) : 0.95 + (t * 0.10));
            final ringScale = disableAnimations ? 1.0 : 1.0 + (t * 0.28);
            final ringAlpha =
                disableAnimations ? 0.35 : (0.55 - (t * 0.40)).clamp(0.12, 0.6);

            final coreDiameter =
                widget.thinking ? effectiveSize * 0.76 : effectiveSize * 0.84;

            return Stack(
              alignment: Alignment.center,
              children: [
                if (widget.thinking)
                  Transform.scale(
                    key: const ValueKey('px_ai_orb_ring'),
                    scale: ringScale,
                    child: Container(
                      width: coreDiameter,
                      height: coreDiameter,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: colors.rosa.withValues(alpha: ringAlpha),
                          width: (effectiveSize * 0.045).clamp(1.5, 3.0),
                        ),
                      ),
                    ),
                  ),
                Transform.scale(
                  key: const ValueKey('px_ai_orb_core'),
                  scale: coreScale,
                  child: Container(
                    width: coreDiameter,
                    height: coreDiameter,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: colors.aiGradient,
                      boxShadow: [
                        BoxShadow(
                          color: colors.rosa.withValues(alpha: 0.32),
                          blurRadius: effectiveSize * 0.32,
                          spreadRadius: effectiveSize * 0.04,
                        ),
                        BoxShadow(
                          color: colors.cempasuchil.withValues(alpha: 0.24),
                          blurRadius: effectiveSize * 0.45,
                          offset: Offset(0, effectiveSize * 0.06),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
