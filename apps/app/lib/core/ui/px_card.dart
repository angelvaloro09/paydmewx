import 'package:flutter/material.dart';

import '../theme/motion.dart';
import '../theme/theme.dart';
import '../theme/tokens.dart';

class PxCard extends StatefulWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final String? semanticLabel;
  final bool elevated;
  final Color? backgroundColor;

  const PxCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(PxSpacing.s24),
    this.onTap,
    this.semanticLabel,
    this.elevated = false,
    this.backgroundColor,
  });

  @override
  State<PxCard> createState() => _PxCardState();
}

class _PxCardState extends State<PxCard> {
  bool _focused = false;
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.pxColors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final defaultBg = isDark
        ? Color.alphaBlend(
            _hovered && widget.onTap != null ? colors.surface2 : colors.surface,
            colors.bg,
          )
        : (_hovered && widget.onTap != null ? colors.surface2 : colors.surface);

    final cardContent = AnimatedContainer(
      duration: PxMotion.duration(context, PxMotion.fast),
      curve: PxMotion.easeStd,
      decoration: BoxDecoration(
        color: widget.backgroundColor ?? defaultBg,
        borderRadius: PxRadius.brXl,
        border: Border.all(
          color: _focused ? colors.brand : colors.line,
          width: _focused ? 2 : (colors.isHighContrast ? 1.5 : 1),
        ),
        boxShadow: widget.elevated ? PxShadows.floating : null,
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: PxRadius.brXl,
          onTap: widget.onTap,
          onFocusChange: (v) => setState(() => _focused = v),
          onHover: (v) => setState(() => _hovered = v),
          child: Padding(
            padding: widget.padding,
            child: widget.child,
          ),
        ),
      ),
    );

    if (widget.onTap != null || widget.semanticLabel != null) {
      return Semantics(
        button: widget.onTap != null,
        label: widget.semanticLabel,
        container: true,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: PxLayout.minTapTarget,
          ),
          child: cardContent,
        ),
      );
    }

    return cardContent;
  }
}
