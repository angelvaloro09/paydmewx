import 'package:flutter/material.dart';

import '../theme/motion.dart';
import '../theme/theme.dart';
import '../theme/tokens.dart';

class PxSegmentOption<T> {
  final T value;
  final String label;
  final String? semanticLabel;
  final IconData? icon;

  const PxSegmentOption({
    required this.value,
    required this.label,
    this.semanticLabel,
    this.icon,
  });
}

/// Pill segmented toggle with a sliding thumb (300ms easeStd, respects reduce-motion).
class PxSegmented<T> extends StatefulWidget {
  final List<PxSegmentOption<T>> options;
  final T value;
  final ValueChanged<T> onChanged;
  final String? semanticGroupLabel;

  const PxSegmented({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
    this.semanticGroupLabel,
  }) : assert(options.length >= 2, 'PxSegmented requires at least 2 options');

  @override
  State<PxSegmented<T>> createState() => _PxSegmentedState<T>();
}

class _PxSegmentedState<T> extends State<PxSegmented<T>> {
  int? _focusedIndex;

  @override
  Widget build(BuildContext context) {
    final colors = context.pxColors;
    final selectedIndex = widget.options
        .indexWhere((option) => option.value == widget.value)
        .clamp(0, widget.options.length - 1);
    final count = widget.options.length;
    final alignX = count <= 1 ? 0.0 : -1.0 + (2.0 * selectedIndex / (count - 1));

    return Semantics(
      label: widget.semanticGroupLabel,
      container: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minHeight: PxLayout.minTapTarget,
        ),
        child: Container(
          padding: const EdgeInsets.all(PxSpacing.s4),
          decoration: BoxDecoration(
            color: colors.surface2,
            borderRadius: PxRadius.brPill,
            border: Border.all(
              color: colors.line,
              width: colors.isHighContrast ? 1.5 : 1,
            ),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              return Stack(
                alignment: Alignment.center,
                children: [
                  Positioned.fill(
                    child: AnimatedAlign(
                      alignment: Alignment(alignX, 0),
                      duration: PxMotion.duration(context, PxMotion.base),
                      curve: PxMotion.easeStd,
                      child: FractionallySizedBox(
                        widthFactor: 1 / count,
                        heightFactor: 1.0,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: colors.brand,
                            borderRadius: PxRadius.brPill,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: List.generate(count, (index) {
                      final option = widget.options[index];
                      final isSelected = index == selectedIndex;
                      final isFocused = _focusedIndex == index;
                      final fg = isSelected ? colors.onBrand : colors.ink;

                      return Expanded(
                        child: Semantics(
                          button: true,
                          selected: isSelected,
                          label: option.semanticLabel ?? option.label,
                          excludeSemantics: true,
                          child: FocusableActionDetector(
                            onShowFocusHighlight: (v) {
                              setState(() {
                                _focusedIndex = v ? index : null;
                              });
                            },
                            actions: <Type, Action<Intent>>{
                              ActivateIntent: CallbackAction<ActivateIntent>(
                                onInvoke: (_) {
                                  widget.onChanged(option.value);
                                  return null;
                                },
                              ),
                            },
                            child: InkWell(
                              borderRadius: PxRadius.brPill,
                              onTap: () => widget.onChanged(option.value),
                              child: Container(
                                constraints: const BoxConstraints(
                                  minHeight: PxLayout.minTapTarget - 8,
                                  minWidth: PxLayout.minTapTarget,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: PxSpacing.s16,
                                  vertical: PxSpacing.s8,
                                ),
                                decoration: isFocused
                                    ? BoxDecoration(
                                        borderRadius: PxRadius.brPill,
                                        border: Border.all(
                                          color: colors.ink,
                                          width: 2,
                                        ),
                                      )
                                    : null,
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (option.icon != null) ...[
                                      Icon(option.icon, size: 16, color: fg),
                                      const SizedBox(width: PxSpacing.s8),
                                    ],
                                    Flexible(
                                      child: Text(
                                        option.label,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: context.pxText.bodyMedium
                                            ?.copyWith(
                                          color: fg,
                                          fontWeight: isSelected
                                              ? FontWeight.w600
                                              : FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
