import 'package:flutter/material.dart';

import '../theme/theme.dart';
import '../theme/tokens.dart';

/// Mono eyebrow label with a leading 24px hairline.
class PxEyebrow extends StatelessWidget {
  final String text;
  final Color? color;

  const PxEyebrow({
    super.key,
    required this.text,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? context.pxColors.inkMuted;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 24,
          height: 1,
          color: c,
        ),
        const SizedBox(width: PxSpacing.s8),
        Flexible(
          child: Text(
            text.toUpperCase(),
            style: PxTheme.eyebrowStyle(c),
          ),
        ),
      ],
    );
  }
}

/// Big tabular number + mono eyebrow label.
class PxStat extends StatelessWidget {
  final String label;
  final String value;
  final String? helper;

  const PxStat({
    super.key,
    required this.label,
    required this.value,
    this.helper,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.pxColors;
    return Semantics(
      label: '$label: $value${helper != null ? ', $helper' : ''}',
      container: true,
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          PxEyebrow(text: label),
          const SizedBox(height: PxSpacing.s8),
          Text(
            value,
            style: PxTheme.moneyStyle(
              fontSize: PxTypographyTokens.h2Mobile,
              color: colors.ink,
            ),
          ),
          if (helper != null) ...[
            const SizedBox(height: PxSpacing.s4),
            Text(
              helper!,
              style: context.pxText.bodySmall?.copyWith(
                color: colors.inkMuted,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
