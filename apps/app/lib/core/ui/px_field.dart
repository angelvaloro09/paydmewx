import 'package:flutter/material.dart';

import '../theme/theme.dart';
import '../theme/tokens.dart';

/// Input field with label ABOVE and helper/error BELOW, radius 16 (or pill on search).
class PxField extends StatelessWidget {
  final String label;
  final String? hintText;
  final String? helperText;
  final String? errorText;
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final bool obscureText;
  final bool enabled;
  final int maxLines;
  final Widget? prefixIcon;
  final Widget? suffixIcon;
  final bool pill;
  final Iterable<String>? autofillHints;

  const PxField({
    super.key,
    required this.label,
    this.hintText,
    this.helperText,
    this.errorText,
    this.controller,
    this.onChanged,
    this.onSubmitted,
    this.keyboardType,
    this.textInputAction,
    this.obscureText = false,
    this.enabled = true,
    this.maxLines = 1,
    this.prefixIcon,
    this.suffixIcon,
    this.pill = false,
    this.autofillHints,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.pxColors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fillColor = isDark
        ? Color.alphaBlend(colors.surface, colors.bg)
        : colors.surface;
    final radius = pill ? PxRadius.brPill : PxRadius.brInput;
    final hasError = errorText != null && errorText!.trim().isNotEmpty;

    return Semantics(
      textField: true,
      label: label,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: context.pxText.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: colors.ink,
            ),
          ),
          const SizedBox(height: PxSpacing.s8),
          ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: PxLayout.minTapTarget,
            ),
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              onSubmitted: onSubmitted,
              keyboardType: keyboardType,
              textInputAction: textInputAction,
              obscureText: obscureText,
              enabled: enabled,
              maxLines: maxLines,
              autofillHints: autofillHints,
              style: context.pxText.bodyLarge?.copyWith(color: colors.ink),
              decoration: InputDecoration(
                hintText: hintText,
                hintStyle: context.pxText.bodyLarge?.copyWith(
                  color: colors.inkMuted,
                ),
                filled: true,
                fillColor: fillColor,
                prefixIcon: prefixIcon,
                suffixIcon: suffixIcon,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: PxSpacing.s16,
                  vertical: PxSpacing.s12,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: radius,
                  borderSide: BorderSide(
                    color: hasError ? colors.danger : colors.line,
                    width: hasError || colors.isHighContrast ? 1.5 : 1,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: radius,
                  borderSide: BorderSide(
                    color: hasError ? colors.danger : colors.brand,
                    width: 2,
                  ),
                ),
                disabledBorder: OutlineInputBorder(
                  borderRadius: radius,
                  borderSide: BorderSide(color: colors.line),
                ),
              ),
            ),
          ),
          if (hasError) ...[
            const SizedBox(height: PxSpacing.s8),
            Semantics(
              liveRegion: true,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.error_outline_rounded,
                    size: 16,
                    color: colors.danger,
                  ),
                  const SizedBox(width: PxSpacing.s4),
                  Expanded(
                    child: Text(
                      errorText!,
                      style: context.pxText.bodySmall?.copyWith(
                        color: colors.danger,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ] else if (helperText != null && helperText!.isNotEmpty) ...[
            const SizedBox(height: PxSpacing.s8),
            Text(
              helperText!,
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
