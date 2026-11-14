import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/api/models.dart';
import '../../core/theme/motion.dart';
import '../../core/theme/theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/ui/px_ui.dart';
import 'inventory_controller.dart';
import 'widgets/inventory_icons.dart';
import 'widgets/inventory_sheet_container.dart';

enum StockAdjustReason {
  compra('compra', 'Compra'),
  merma('merma', 'Merma'),
  conteo('conteo', 'Conteo'),
  otro('otro', 'Otro');

  final String apiValue;
  final String label;
  const StockAdjustReason(this.apiValue, this.label);
}

Future<bool?> showStockAdjustSheet({
  required BuildContext context,
  required Product product,
}) {
  return showInventorySheet<bool>(
    context: context,
    title: 'Ajustar existencias',
    builder: (sheetContext) => StockSheet(product: product),
  );
}

class StockSheet extends ConsumerStatefulWidget {
  final Product product;

  const StockSheet({
    super.key,
    required this.product,
  });

  @override
  ConsumerState<StockSheet> createState() => _StockSheetState();
}

class _StockSheetState extends ConsumerState<StockSheet> {
  int _delta = 0;
  StockAdjustReason _reason = StockAdjustReason.compra;
  bool _saving = false;
  String? _error;

  int get _newStock {
    final result = widget.product.stock + _delta;
    return result < 0 ? 0 : result;
  }

  void _increment() {
    setState(() {
      _delta += 1;
      _error = null;
    });
  }

  void _decrement() {
    if (widget.product.stock + _delta <= 0) return;
    setState(() {
      _delta -= 1;
      _error = null;
    });
  }

  Future<void> _save() async {
    if (_delta == 0 || _saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(inventoryControllerProvider.notifier).adjustStock(
            widget.product.id,
            delta: _delta,
            reason: _reason.apiValue,
          );
      if (!mounted) return;
      // Announce via SemanticsService for screen readers
      // ignore: deprecated_member_use
      SemanticsService.announce(
        'Existencias actualizadas',
        Directionality.of(context),
      );
      PxToast.show(
        context,
        message: 'Existencias actualizadas.',
        type: PxToastType.success,
      );
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e.message;
      });
      PxToast.show(context, message: e.message, type: PxToastType.error);
    } catch (_) {
      if (!mounted) return;
      const fallback =
          'No pudimos actualizar las existencias. Intenta de nuevo.';
      setState(() {
        _saving = false;
        _error = fallback;
      });
      PxToast.show(context, message: fallback, type: PxToastType.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.pxColors;
    final canDecrement = (widget.product.stock + _delta) > 0 && !_saving;
    final canSave = _delta != 0 && !_saving;
    final deltaFormatted = _delta > 0 ? '+$_delta' : '$_delta';

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          widget.product.name,
          style: context.pxText.titleMedium?.copyWith(
            color: colors.ink,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: PxSpacing.s4),
        Text(
          'Existencia actual: ${widget.product.stock} → Nueva: $_newStock',
          style: context.pxText.bodyMedium?.copyWith(
            color: colors.inkMuted,
          ),
        ),
        const SizedBox(height: PxSpacing.s24),
        PxCard(
          padding: const EdgeInsets.symmetric(
            horizontal: PxSpacing.s16,
            vertical: PxSpacing.s24,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _StepperButton(
                icon: PhosphorIconsBold.minus,
                semanticLabel: 'Disminuir cantidad en 1',
                enabled: canDecrement,
                onTap: _decrement,
              ),
              Expanded(
                child: Semantics(
                  liveRegion: true,
                  label:
                      'Cambio de inventario: $deltaFormatted, total final $_newStock',
                  excludeSemantics: true,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        deltaFormatted,
                        textAlign: TextAlign.center,
                        style: PxTheme.moneyStyle(
                          fontSize: PxTypographyTokens.h1Mobile,
                          color: _delta == 0
                              ? colors.inkMuted
                              : (_delta > 0 ? colors.brandText : colors.danger),
                        ),
                      ),
                      const SizedBox(height: PxSpacing.s4),
                      Text(
                        'ajuste de unidades',
                        textAlign: TextAlign.center,
                        style: context.pxText.bodySmall?.copyWith(
                          color: colors.inkMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              _StepperButton(
                icon: PhosphorIconsBold.plus,
                semanticLabel: 'Aumentar cantidad en 1',
                enabled: !_saving,
                onTap: _increment,
              ),
            ],
          ),
        ),
        const SizedBox(height: PxSpacing.s24),
        Text(
          'Motivo del ajuste',
          style: context.pxText.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: colors.ink,
          ),
        ),
        const SizedBox(height: PxSpacing.s12),
        Wrap(
          spacing: PxSpacing.s8,
          runSpacing: PxSpacing.s8,
          children: StockAdjustReason.values.map((reason) {
            final isSelected = _reason == reason;
            return PxChip(
              label: reason.label,
              semanticLabel: 'Motivo ${reason.label}',
              selected: isSelected,
              onSelected: _saving
                  ? null
                  : () {
                      setState(() {
                        _reason = reason;
                      });
                    },
            );
          }).toList(),
        ),
        if (_error != null) ...[
          const SizedBox(height: PxSpacing.s16),
          Semantics(
            liveRegion: true,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  PhosphorIconsBold.warningCircle,
                  size: 18,
                  color: colors.danger,
                ),
                const SizedBox(width: PxSpacing.s8),
                Expanded(
                  child: Text(
                    _error!,
                    style: context.pxText.bodySmall?.copyWith(
                      color: colors.danger,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: PxSpacing.s24),
        PxButton(
          label: 'Guardar ajuste',
          semanticLabel: 'Guardar ajuste de existencias',
          fullWidth: true,
          loading: _saving,
          onPressed: canSave ? _save : null,
          icon: PhosphorIconsBold.check,
        ),
      ],
    );
  }
}

class _StepperButton extends StatefulWidget {
  final IconData icon;
  final String semanticLabel;
  final bool enabled;
  final VoidCallback onTap;

  const _StepperButton({
    required this.icon,
    required this.semanticLabel,
    required this.enabled,
    required this.onTap,
  });

  @override
  State<_StepperButton> createState() => _StepperButtonState();
}

class _StepperButtonState extends State<_StepperButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.pxColors;
    final bg = widget.enabled ? colors.surface2 : colors.surface;
    final fg = widget.enabled ? colors.ink : colors.inkMuted;

    return Semantics(
      button: true,
      enabled: widget.enabled,
      label: widget.semanticLabel,
      excludeSemantics: true,
      child: FocusableActionDetector(
        enabled: widget.enabled,
        onShowFocusHighlight: (v) => setState(() => _focused = v),
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              if (widget.enabled) widget.onTap();
              return null;
            },
          ),
        },
        child: AnimatedContainer(
          duration: PxMotion.duration(context, PxMotion.fast),
          curve: PxMotion.easeStd,
          constraints: const BoxConstraints(
            minWidth: 56,
            minHeight: 56,
          ),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: PxRadius.brPill,
            border: Border.all(
              color: _focused ? colors.brand : colors.line,
              width: _focused ? 2 : (colors.isHighContrast ? 1.5 : 1),
            ),
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: PxRadius.brPill,
              onTap: widget.enabled ? widget.onTap : null,
              child: SizedBox(
                width: 56,
                height: 56,
                child: Icon(widget.icon, size: 24, color: fg),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
