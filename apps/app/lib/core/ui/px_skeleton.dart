import 'package:flutter/material.dart';

import '../theme/motion.dart';
import '../theme/theme.dart';
import '../theme/tokens.dart';

/// Skeleton loading block that respects OS reduce-motion.
class PxSkeleton extends StatefulWidget {
  final double width;
  final double height;
  final BorderRadius borderRadius;

  const PxSkeleton({
    super.key,
    this.width = double.infinity,
    required this.height,
    this.borderRadius = PxRadius.brLg,
  });

  @override
  State<PxSkeleton> createState() => _PxSkeletonState();
}

class _PxSkeletonState extends State<PxSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: PxMotion.hero,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.pxColors;
    final reduceMotion = PxMotion.reduceMotion(context);

    if (reduceMotion) {
      return Semantics(
        label: 'Cargando contenido',
        child: Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            color: colors.surface2,
            borderRadius: widget.borderRadius,
          ),
        ),
      );
    }

    return Semantics(
      label: 'Cargando contenido',
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final alpha = 0.45 + (_controller.value * 0.45);
          return Container(
            width: widget.width,
            height: widget.height,
            decoration: BoxDecoration(
              color: colors.surface2.withValues(alpha: alpha),
              borderRadius: widget.borderRadius,
            ),
          );
        },
      ),
    );
  }
}
