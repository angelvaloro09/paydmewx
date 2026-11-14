import 'package:flutter/material.dart';

import '../theme/theme.dart';
import '../theme/tokens.dart';

enum PxToastType { info, success, error }

class PxToast {
  static void show(
    BuildContext context, {
    required String message,
    PxToastType type = PxToastType.info,
  }) {
    final colors = context.pxColors;
    final (Color accent, IconData icon) = switch (type) {
      PxToastType.success => (colors.brand, Icons.check_circle_rounded),
      PxToastType.error => (colors.danger, Icons.error_outline_rounded),
      PxToastType.info => (colors.codi, Icons.info_outline_rounded),
    };

    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: colors.ink,
        shape: const RoundedRectangleBorder(borderRadius: PxRadius.brLg),
        content: Semantics(
          liveRegion: true,
          label: message,
          child: Row(
            children: [
              Icon(icon, color: accent, size: 20),
              const SizedBox(width: PxSpacing.s12),
              Expanded(
                child: Text(
                  message,
                  style: context.pxText.bodyMedium?.copyWith(
                    color: colors.bg,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
