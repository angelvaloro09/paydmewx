import 'package:flutter/material.dart';

import '../../../core/theme/motion.dart';
import '../../../core/theme/theme.dart';
import '../../../core/theme/tokens.dart';
import 'inventory_icons.dart';

/// Opens a responsive PxSheet:
/// - Below 900px: full-height scrollable modal bottom sheet.
/// - >= 900px: side-aligned dialog panel on the right.
Future<T?> showInventorySheet<T>({
  required BuildContext context,
  required String title,
  required Widget Function(BuildContext sheetContext) builder,
}) {
  final width = MediaQuery.sizeOf(context).width;
  final isWide = width >= PxLayout.railBreakpoint;

  if (isWide) {
    return showGeneralDialog<T>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Cerrar $title',
      barrierColor: const Color(0x8A000000),
      transitionDuration: PxMotion.duration(context, PxMotion.base),
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        final colors = dialogContext.pxColors;
        final isDark = Theme.of(dialogContext).brightness == Brightness.dark;
        final bg = isDark
            ? Color.alphaBlend(colors.surface, colors.bg)
            : colors.bg;

        return SafeArea(
          child: Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.all(PxSpacing.s16),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: 480,
                  maxHeight: double.infinity,
                ),
                child: Material(
                  color: bg,
                  shape: RoundedRectangleBorder(
                    borderRadius: PxRadius.brXl,
                    side: BorderSide(
                      color: colors.line,
                      width: colors.isHighContrast ? 1.5 : 1,
                    ),
                  ),
                  elevation: 0,
                  child: Container(
                    decoration: const BoxDecoration(
                      borderRadius: PxRadius.brXl,
                      boxShadow: PxShadows.floating,
                    ),
                    child: _SheetContentFrame(
                      title: title,
                      child: builder(dialogContext),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
      transitionBuilder: (dialogContext, animation, _, child) {
        if (PxMotion.reduceMotion(dialogContext)) {
          return FadeTransition(opacity: animation, child: child);
        }
        final curved = CurvedAnimation(
          parent: animation,
          curve: PxMotion.easeOut,
        );
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0.08, 0),
            end: Offset.zero,
          ).animate(curved),
          child: FadeTransition(opacity: curved, child: child),
        );
      },
    );
  }

  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) {
      final colors = sheetContext.pxColors;
      final isDark = Theme.of(sheetContext).brightness == Brightness.dark;
      final bg = isDark
          ? Color.alphaBlend(colors.surface, colors.bg)
          : colors.bg;
      final bottomInset = MediaQuery.viewInsetsOf(sheetContext).bottom;

      return Padding(
        padding: EdgeInsets.only(bottom: bottomInset),
        child: Container(
          decoration: BoxDecoration(
            color: bg,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(PxRadius.xl),
            ),
            border: Border(
              top: BorderSide(
                color: colors.line,
                width: colors.isHighContrast ? 1.5 : 1,
              ),
            ),
            boxShadow: PxShadows.floating,
          ),
          child: _SheetContentFrame(
            title: title,
            showDragHandle: true,
            child: builder(sheetContext),
          ),
        ),
      );
    },
  );
}

class _SheetContentFrame extends StatefulWidget {
  final String title;
  final Widget child;
  final bool showDragHandle;

  const _SheetContentFrame({
    required this.title,
    required this.child,
    this.showDragHandle = false,
  });

  @override
  State<_SheetContentFrame> createState() => _SheetContentFrameState();
}

class _SheetContentFrameState extends State<_SheetContentFrame> {
  bool _closeFocused = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.pxColors;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.showDragHandle)
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: PxSpacing.s12),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: colors.line,
                borderRadius: PxRadius.brPill,
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            PxSpacing.s24,
            PxSpacing.s16,
            PxSpacing.s16,
            PxSpacing.s12,
          ),
          child: Row(
            children: [
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(
                    widget.title,
                    style: context.pxText.titleLarge?.copyWith(
                      color: colors.ink,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: PxSpacing.s8),
              Semantics(
                button: true,
                label: 'Cerrar ${widget.title}',
                excludeSemantics: true,
                child: FocusableActionDetector(
                  onShowFocusHighlight: (v) =>
                      setState(() => _closeFocused = v),
                  actions: <Type, Action<Intent>>{
                    ActivateIntent: CallbackAction<ActivateIntent>(
                      onInvoke: (_) {
                        Navigator.of(context).maybePop();
                        return null;
                      },
                    ),
                  },
                  child: InkWell(
                    borderRadius: PxRadius.brPill,
                    onTap: () => Navigator.of(context).maybePop(),
                    child: Container(
                      width: PxLayout.minTapTarget,
                      height: PxLayout.minTapTarget,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: colors.surface2,
                        borderRadius: PxRadius.brPill,
                        border: Border.all(
                          color: _closeFocused ? colors.brand : colors.line,
                          width: _closeFocused ? 2 : 1,
                        ),
                      ),
                      child: Icon(
                        PhosphorIconsRegular.x,
                        size: 20,
                        color: colors.ink,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: colors.line),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(PxSpacing.s24),
            child: widget.child,
          ),
        ),
      ],
    );
  }
}
