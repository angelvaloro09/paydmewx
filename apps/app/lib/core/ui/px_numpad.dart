import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/motion.dart';
import '../theme/theme.dart';
import '../theme/tokens.dart';
import 'px_focus_ring.dart';

class _NumpadKeySpec {
  final String id;
  final String? label;
  final IconData? icon;
  final String semanticLabel;
  final bool isBackspace;

  const _NumpadKeySpec({
    required this.id,
    this.label,
    this.icon,
    required this.semanticLabel,
    this.isBackspace = false,
  });
}

const List<List<_NumpadKeySpec>> _numpadRows = [
  [
    _NumpadKeySpec(id: '1', label: '1', semanticLabel: 'uno'),
    _NumpadKeySpec(id: '2', label: '2', semanticLabel: 'dos'),
    _NumpadKeySpec(id: '3', label: '3', semanticLabel: 'tres'),
  ],
  [
    _NumpadKeySpec(id: '4', label: '4', semanticLabel: 'cuatro'),
    _NumpadKeySpec(id: '5', label: '5', semanticLabel: 'cinco'),
    _NumpadKeySpec(id: '6', label: '6', semanticLabel: 'seis'),
  ],
  [
    _NumpadKeySpec(id: '7', label: '7', semanticLabel: 'siete'),
    _NumpadKeySpec(id: '8', label: '8', semanticLabel: 'ocho'),
    _NumpadKeySpec(id: '9', label: '9', semanticLabel: 'nueve'),
  ],
  [
    _NumpadKeySpec(id: '00', label: '00', semanticLabel: 'doble cero'),
    _NumpadKeySpec(id: '0', label: '0', semanticLabel: 'cero'),
    _NumpadKeySpec(
      id: 'backspace',
      icon: Icons.backspace_outlined,
      semanticLabel: 'borrar',
      isBackspace: true,
    ),
  ],
];

/// Large-key POS numpad (3x4: 1-9, 00, 0, backspace).
/// Keys are >= 72dp high and >= 48dp wide, with selectionClick haptic feedback
/// and full screen-reader labels. Long-pressing backspace triggers [onClear].
class PxNumpad extends StatelessWidget {
  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;
  final VoidCallback? onClear;
  final bool enabled;

  const PxNumpad({
    super.key,
    required this.onDigit,
    required this.onBackspace,
    this.onClear,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var r = 0; r < _numpadRows.length; r++) ...[
          if (r > 0) const SizedBox(height: PxSpacing.s8),
          Row(
            children: [
              for (var c = 0; c < _numpadRows[r].length; c++) ...[
                if (c > 0) const SizedBox(width: PxSpacing.s8),
                Expanded(
                  child: _PxNumpadKey(
                    spec: _numpadRows[r][c],
                    enabled: enabled,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      final spec = _numpadRows[r][c];
                      if (spec.isBackspace) {
                        onBackspace();
                      } else {
                        onDigit(spec.id);
                      }
                    },
                    onLongPress: _numpadRows[r][c].isBackspace && onClear != null
                        ? () {
                            HapticFeedback.selectionClick();
                            onClear!();
                          }
                        : null,
                  ),
                ),
              ],
            ],
          ),
        ],
      ],
    );
  }
}

class _PxNumpadKey extends StatefulWidget {
  final _NumpadKeySpec spec;
  final bool enabled;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const _PxNumpadKey({
    required this.spec,
    required this.enabled,
    required this.onTap,
    this.onLongPress,
  });

  @override
  State<_PxNumpadKey> createState() => _PxNumpadKeyState();
}

class _PxNumpadKeyState extends State<_PxNumpadKey> {
  bool _focused = false;
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.pxColors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final activeBg = isDark
        ? Color.alphaBlend(colors.surface2, colors.bg)
        : colors.surface2;
    final idleBg = isDark
        ? Color.alphaBlend(colors.surface, colors.bg)
        : colors.surface;

    final bg = (_pressed || _hovered) && widget.enabled ? activeBg : idleBg;
    final fg = widget.enabled ? colors.ink : colors.inkMuted;

    return Semantics(
      button: true,
      enabled: widget.enabled,
      label: widget.spec.semanticLabel,
      onTap: widget.enabled ? widget.onTap : null,
      onLongPress: widget.enabled ? widget.onLongPress : null,
      excludeSemantics: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minWidth: PxLayout.minTapTarget,
          minHeight: 72.0,
        ),
        child: FocusableActionDetector(
          enabled: widget.enabled,
          onShowFocusHighlight: (v) => setState(() => _focused = v),
          onShowHoverHighlight: (v) => setState(() => _hovered = v),
          actions: <Type, Action<Intent>>{
            ActivateIntent: CallbackAction<ActivateIntent>(
              onInvoke: (_) {
                if (widget.enabled) widget.onTap();
                return null;
              },
            ),
          },
          child: PxFocusRing(
            focused: _focused,
            borderRadius: PxRadius.brLg,
            child: AnimatedContainer(
              duration: PxMotion.duration(context, PxMotion.fast),
              curve: PxMotion.easeStd,
              decoration: BoxDecoration(
                color: bg,
                borderRadius: PxRadius.brLg,
                border: Border.all(
                  color: _focused ? colors.brand : colors.line,
                  width: _focused ? 2 : (colors.isHighContrast ? 1.5 : 1),
                ),
              ),
              child: Material(
                type: MaterialType.transparency,
                child: InkWell(
                  key: ValueKey<String>('px_numpad_key_${widget.spec.id}'),
                  borderRadius: PxRadius.brLg,
                  onTap: widget.enabled ? widget.onTap : null,
                  onLongPress: widget.enabled ? widget.onLongPress : null,
                  onHighlightChanged: (v) => setState(() => _pressed = v),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: PxSpacing.s8,
                      vertical: PxSpacing.s8,
                    ),
                    child: Center(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: widget.spec.icon != null
                            ? Icon(
                                widget.spec.icon,
                                size: 26,
                                color: fg,
                              )
                            : Text(
                                widget.spec.label ?? '',
                                style: PxTheme.monoStyle(
                                  fontSize: PxTypographyTokens.h2Mobile,
                                  fontWeight: FontWeight.w600,
                                  color: fg,
                                ),
                              ),
                      ),
                    ),
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
