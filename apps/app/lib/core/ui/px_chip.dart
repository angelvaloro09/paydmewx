import 'package:flutter/material.dart';

import '../theme/motion.dart';
import '../theme/theme.dart';
import '../theme/tokens.dart';

class PxChip extends StatefulWidget {
  final String label;
  final String? semanticLabel;
  final bool selected;
  final VoidCallback? onSelected;
  final IconData? icon;

  const PxChip({
    super.key,
    required this.label,
    this.semanticLabel,
    this.selected = false,
    this.onSelected,
    this.icon,
  });

  @override
  State<PxChip> createState() => _PxChipState();
}

class _PxChipState extends State<PxChip> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.pxColors;
    final interactive = widget.onSelected != null;

    final bg = widget.selected ? colors.ink : colors.surface2;
    final fg = widget.selected ? colors.bg : colors.ink;
    final borderColor = _focused
        ? colors.brand
        : (widget.selected ? colors.ink : colors.line);

    return Semantics(
      button: interactive,
      selected: widget.selected,
      label: widget.semanticLabel ?? widget.label,
      excludeSemantics: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minHeight: PxLayout.minTapTarget,
          minWidth: PxLayout.minTapTarget,
        ),
        child: FocusableActionDetector(
          enabled: interactive,
          onShowFocusHighlight: (v) => setState(() => _focused = v),
          actions: <Type, Action<Intent>>{
            ActivateIntent: CallbackAction<ActivateIntent>(
              onInvoke: (_) {
                widget.onSelected?.call();
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
              border: Border.all(
                color: borderColor,
                width: _focused ? 2 : 1,
              ),
            ),
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                borderRadius: PxRadius.brPill,
                onTap: widget.onSelected,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: PxSpacing.s16,
                    vertical: PxSpacing.s12,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (widget.selected || widget.icon != null) ...[
                        Icon(
                          widget.icon ?? Icons.check_rounded,
                          size: 16,
                          color: fg,
                        ),
                        const SizedBox(width: PxSpacing.s8),
                      ],
                      Text(
                        widget.label,
                        style: context.pxText.bodyMedium?.copyWith(
                          color: fg,
                          fontWeight: widget.selected
                              ? FontWeight.w600
                              : FontWeight.w500,
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
