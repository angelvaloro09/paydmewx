import 'package:flutter/material.dart';

import '../theme/motion.dart';
import '../theme/theme.dart';
import '../theme/tokens.dart';

enum PxButtonVariant { primary, secondary, ghost }

class PxButton extends StatefulWidget {
  final String label;
  final String? semanticLabel;
  final VoidCallback? onPressed;
  final PxButtonVariant variant;
  final bool loading;
  final IconData? icon;
  final bool fullWidth;

  const PxButton({
    super.key,
    required this.label,
    this.semanticLabel,
    required this.onPressed,
    this.variant = PxButtonVariant.primary,
    this.loading = false,
    this.icon,
    this.fullWidth = false,
  });

  @override
  State<PxButton> createState() => _PxButtonState();
}

class _PxButtonState extends State<PxButton> {
  bool _focused = false;
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.pxColors;
    final reduceMotion = PxMotion.reduceMotion(context);
    final enabled = widget.onPressed != null && !widget.loading;

    final Color bg;
    final Color fg;
    final BorderSide side;

    switch (widget.variant) {
      case PxButtonVariant.primary:
        bg = enabled ? colors.brand : colors.surface2;
        fg = enabled ? colors.onBrand : colors.inkMuted;
        side = BorderSide.none;
      case PxButtonVariant.secondary:
        bg = _hovered && enabled ? colors.surface2 : colors.surface;
        fg = enabled ? colors.ink : colors.inkMuted;
        side = BorderSide(
          color: _focused ? colors.brand : colors.line,
          width: _focused ? 2 : (colors.isHighContrast ? 1.5 : 1),
        );
      case PxButtonVariant.ghost:
        bg = _hovered && enabled ? colors.surface2 : Colors.transparent;
        fg = enabled ? colors.ink : colors.inkMuted;
        side = _focused
            ? BorderSide(color: colors.brand, width: 2)
            : BorderSide.none;
    }

    final effectiveLabel = widget.loading
        ? '${widget.semanticLabel ?? widget.label}, cargando'
        : (widget.semanticLabel ?? widget.label);

    return Semantics(
      button: true,
      enabled: enabled,
      label: effectiveLabel,
      excludeSemantics: true,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minWidth: widget.fullWidth ? double.infinity : PxLayout.minTapTarget,
          minHeight: PxLayout.buttonMinHeight,
        ),
        child: FocusableActionDetector(
          enabled: enabled,
          onShowFocusHighlight: (v) => setState(() => _focused = v),
          onShowHoverHighlight: (v) => setState(() => _hovered = v),
          actions: <Type, Action<Intent>>{
            ActivateIntent: CallbackAction<ActivateIntent>(
              onInvoke: (_) {
                if (enabled) widget.onPressed?.call();
                return null;
              },
            ),
          },
          child: AnimatedContainer(
            duration: PxMotion.duration(context, PxMotion.fast),
            curve: PxMotion.easeStd,
            decoration: BoxDecoration(
              color: bg,
              borderRadius: PxRadius.brPill,
              border: Border.fromBorderSide(
                _focused && widget.variant == PxButtonVariant.primary
                    ? BorderSide(color: colors.ink, width: 2)
                    : side,
              ),
            ),
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                borderRadius: PxRadius.brPill,
                onTap: enabled ? widget.onPressed : null,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: PxSpacing.s24,
                    vertical: PxSpacing.s12,
                  ),
                  child: Row(
                    mainAxisSize:
                        widget.fullWidth ? MainAxisSize.max : MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (widget.loading) ...[
                        SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            value: reduceMotion ? 0.75 : null,
                            valueColor: AlwaysStoppedAnimation<Color>(fg),
                          ),
                        ),
                        const SizedBox(width: PxSpacing.s12),
                      ] else if (widget.icon != null) ...[
                        Icon(widget.icon, size: 20, color: fg),
                        const SizedBox(width: PxSpacing.s8),
                      ],
                      Flexible(
                        child: Text(
                          widget.label,
                          textAlign: TextAlign.center,
                          style: context.pxText.labelLarge?.copyWith(color: fg),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
