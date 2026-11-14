import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import '../theme/theme.dart';

/// Draws a 2px brand focus ring with 2px offset when [focused] is true.
class PxFocusRing extends StatelessWidget {
  final bool focused;
  final BorderRadius borderRadius;
  final Widget child;

  const PxFocusRing({
    super.key,
    required this.focused,
    this.borderRadius = PxRadius.brPill,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    if (!focused) return child;
    final colors = context.pxColors;
    return DecoratedBox(
      position: DecorationPosition.foreground,
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        border: Border.all(color: colors.brand, width: 2),
      ),
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: child,
      ),
    );
  }
}
