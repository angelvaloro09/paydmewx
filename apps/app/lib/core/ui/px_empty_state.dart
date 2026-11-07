import 'package:flutter/material.dart';

import '../theme/theme.dart';
import '../theme/tokens.dart';
import 'px_button.dart';

/// Illustration-free empty state: big glyph + title + 1-line subtitle + optional CTA.
class PxEmptyState extends StatelessWidget {
  final String glyph;
  final String title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const PxEmptyState({
    super.key,
    this.glyph = '◎',
    required this.title,
    this.message,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.pxColors;
    return Semantics(
      container: true,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(PxSpacing.s24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ExcludeSemantics(
                  child: Text(
                    glyph,
                    style: PxTheme.monoStyle(
                      fontSize: 48,
                      fontWeight: FontWeight.w400,
                      color: colors.brandText,
                    ),
                  ),
                ),
                const SizedBox(height: PxSpacing.s16),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: context.pxText.headlineSmall?.copyWith(
                    color: colors.ink,
                  ),
                ),
                if (message != null && message!.isNotEmpty) ...[
                  const SizedBox(height: PxSpacing.s8),
                  Text(
                    message!,
                    textAlign: TextAlign.center,
                    style: context.pxText.bodyMedium?.copyWith(
                      color: colors.inkMuted,
                    ),
                  ),
                ],
                if (actionLabel != null && onAction != null) ...[
                  const SizedBox(height: PxSpacing.s24),
                  PxButton(
                    label: actionLabel!,
                    onPressed: onAction,
                    variant: PxButtonVariant.secondary,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
