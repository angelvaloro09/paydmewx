import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/formatters.dart';
import '../../core/api/models.dart';
import '../../core/theme/theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/ui/px_ui.dart';
import 'cart_controller.dart';
import 'checkout_controller.dart';
import 'checkout_sheet.dart';

Future<void> showCartSheet(
  BuildContext context, {
  required String businessId,
  String? businessName,
  bool? demoModeOverride,
}) {
  final colors = context.pxColors;
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: colors.bg,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(PxRadius.xl),
      ),
    ),
    builder: (sheetContext) => CartSheet(
      businessId: businessId,
      businessName: businessName,
      demoModeOverride: demoModeOverride,
    ),
  );
}

class CartSheet extends ConsumerStatefulWidget {
  final String businessId;
  final String? businessName;
  final bool? demoModeOverride;
  final VoidCallback? onPayWithCodi;

  const CartSheet({
    super.key,
    required this.businessId,
    this.businessName,
    this.demoModeOverride,
    this.onPayWithCodi,
  });

  @override
  ConsumerState<CartSheet> createState() => _CartSheetState();
}

class _CartSheetState extends ConsumerState<CartSheet> {
  late final TextEditingController _noteController;

  @override
  void initState() {
    super.initState();
    final initialNote = ref.read(cartProvider).note;
    _noteController = TextEditingController(text: initialNote);
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  void _handlePayWithCodi() {
    final cart = ref.read(cartProvider);
    if (cart.isEmpty) return;

    final effectiveBusinessId = widget.businessId.isNotEmpty
        ? widget.businessId
        : (cart.businessId ?? '');

    if (widget.onPayWithCodi != null) {
      widget.onPayWithCodi!();
      return;
    }

    ref
        .read(checkoutProvider.notifier)
        .startCheckout(businessId: effectiveBusinessId);

    final nav = Navigator.of(context);
    final rootContext = nav.context;
    if (nav.canPop()) {
      nav.pop();
    }
    showCheckoutSheet(
      rootContext,
      businessId: effectiveBusinessId,
      demoModeOverride: widget.demoModeOverride,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartProvider);
    final colors = context.pxColors;

    if (_noteController.text != cart.note) {
      _noteController.value = TextEditingValue(
        text: cart.note,
        selection: TextSelection.collapsed(offset: cart.note.length),
      );
    }

    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.only(
          left: PxSpacing.s24,
          right: PxSpacing.s24,
          top: PxSpacing.s16,
          bottom: MediaQuery.viewInsetsOf(context).bottom + PxSpacing.s24,
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: ExcludeSemantics(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: colors.line,
                        borderRadius: PxRadius.brPill,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: PxSpacing.s16),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const PxEyebrow(text: 'TU PEDIDO'),
                          const SizedBox(height: PxSpacing.s4),
                          Text(
                            widget.businessName ??
                                cart.businessName ??
                                'Resumen del pedido',
                            style: context.pxText.headlineSmall,
                          ),
                        ],
                      ),
                    ),
                    Semantics(
                      button: true,
                      label: 'Cerrar pedido',
                      excludeSemantics: true,
                      child: SizedBox(
                        width: PxLayout.minTapTarget,
                        height: PxLayout.minTapTarget,
                        child: IconButton(
                          tooltip: 'Cerrar',
                          icon: Icon(
                            Icons.close_rounded,
                            color: colors.ink,
                          ),
                          onPressed: () => Navigator.of(context).maybePop(),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: PxSpacing.s16),
                if (cart.isEmpty)
                  PxEmptyState(
                    glyph: '□',
                    title: 'Tu pedido está vacío',
                    message:
                        'Agrega productos del catálogo para pagar con CoDi.',
                    actionLabel: 'Regresar',
                    onAction: () => Navigator.of(context).maybePop(),
                  )
                else ...[
                  ...cart.items.map(
                    (line) => Padding(
                      padding: const EdgeInsets.only(bottom: PxSpacing.s12),
                      child: _CartLineTile(
                        product: line.product,
                        qty: line.qty,
                        lineTotalCents: line.lineTotalCents,
                        canIncrement: line.canIncrement,
                        onDecrement: () => ref
                            .read(cartProvider.notifier)
                            .decrementProduct(line.product.id),
                        onIncrement: () => ref
                            .read(cartProvider.notifier)
                            .addProduct(
                              line.product,
                              businessId: widget.businessId,
                              businessName: widget.businessName,
                            ),
                      ),
                    ),
                  ),
                  const SizedBox(height: PxSpacing.s8),
                  PxField(
                    label: 'Nota para el negocio (opcional)',
                    hintText: 'Ej. Sin cebolla, salsa aparte',
                    controller: _noteController,
                    maxLines: 2,
                    textInputAction: TextInputAction.done,
                    onChanged: (value) =>
                        ref.read(cartProvider.notifier).setNote(value),
                  ),
                  const SizedBox(height: PxSpacing.s24),
                  PxCard(
                    padding: const EdgeInsets.all(PxSpacing.s16),
                    backgroundColor: colors.surface2,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Total a pagar',
                                style: context.pxText.titleMedium,
                              ),
                              Text(
                                '${cart.totalItems} ${cart.totalItems == 1 ? 'producto' : 'productos'}',
                                style: context.pxText.bodySmall?.copyWith(
                                  color: colors.inkMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: PxSpacing.s12),
                        Flexible(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              formatMxn(cart.totalCents),
                              style: PxTheme.moneyStyle(
                                fontSize: PxTypographyTokens.h2Mobile,
                                color: colors.ink,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: PxSpacing.s24),
                  PxButton(
                    label: 'Pagar con CoDi',
                    semanticLabel:
                        'Pagar con CoDi ${formatMxn(cart.totalCents)}',
                    icon: Icons.qr_code_2_rounded,
                    fullWidth: true,
                    onPressed: _handlePayWithCodi,
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

class _CartLineTile extends StatelessWidget {
  final Product product;
  final int qty;
  final int lineTotalCents;
  final bool canIncrement;
  final VoidCallback onDecrement;
  final VoidCallback onIncrement;

  const _CartLineTile({
    required this.product,
    required this.qty,
    required this.lineTotalCents,
    required this.canIncrement,
    required this.onDecrement,
    required this.onIncrement,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.pxColors;
    return PxCard(
      padding: const EdgeInsets.all(PxSpacing.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.name,
                      style: context.pxText.titleMedium,
                    ),
                    const SizedBox(height: PxSpacing.s4),
                    Text(
                      '${formatMxn(product.priceCents)} c/u',
                      style: context.pxText.bodySmall?.copyWith(
                        color: colors.inkMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: PxSpacing.s12),
              Text(
                formatMxn(lineTotalCents),
                style: PxTheme.moneyStyle(
                  fontSize: PxTypographyTokens.h3Mobile,
                  color: colors.ink,
                ),
              ),
            ],
          ),
          const SizedBox(height: PxSpacing.s12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (product.trackStock) ...[
                Expanded(
                  child: Text(
                    'Disponibles: ${product.stock}',
                    style: context.pxText.bodySmall?.copyWith(
                      color: colors.inkMuted,
                    ),
                  ),
                ),
              ],
              PxProductStepper(
                productName: product.name,
                qty: qty,
                canIncrement: canIncrement,
                onDecrement: onDecrement,
                onIncrement: onIncrement,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Accessible quantity stepper (`- qty +`) with >= 48dp touch targets and
/// semantic labels `Agregar <name>` and `Quitar <name>`.
class PxProductStepper extends StatelessWidget {
  final String productName;
  final int qty;
  final bool canIncrement;
  final VoidCallback onDecrement;
  final VoidCallback onIncrement;

  const PxProductStepper({
    super.key,
    required this.productName,
    required this.qty,
    required this.canIncrement,
    required this.onDecrement,
    required this.onIncrement,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.pxColors;
    final canDecrement = qty > 0;

    return Container(
      decoration: BoxDecoration(
        color: colors.surface2,
        borderRadius: PxRadius.brPill,
        border: Border.all(
          color: colors.line,
          width: colors.isHighContrast ? 1.5 : 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _StepperIconButton(
            semanticLabel: 'Quitar $productName',
            icon: Icons.remove_rounded,
            enabled: canDecrement,
            onPressed: canDecrement ? onDecrement : null,
          ),
          Semantics(
            label: 'Cantidad de $productName: $qty',
            excludeSemantics: true,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 28),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: PxSpacing.s4),
                child: Text(
                  '$qty',
                  textAlign: TextAlign.center,
                  style: PxTheme.monoStyle(
                    fontSize: PxTypographyTokens.small,
                    fontWeight: FontWeight.w600,
                    color: colors.ink,
                  ),
                ),
              ),
            ),
          ),
          _StepperIconButton(
            semanticLabel: 'Agregar $productName',
            icon: Icons.add_rounded,
            enabled: canIncrement,
            backgroundColor: canIncrement ? colors.brand : null,
            iconColor: canIncrement ? colors.onBrand : colors.inkMuted,
            onPressed: canIncrement ? onIncrement : null,
          ),
        ],
      ),
    );
  }
}

class _StepperIconButton extends StatelessWidget {
  final String semanticLabel;
  final IconData icon;
  final bool enabled;
  final Color? backgroundColor;
  final Color? iconColor;
  final VoidCallback? onPressed;

  const _StepperIconButton({
    required this.semanticLabel,
    required this.icon,
    required this.enabled,
    this.backgroundColor,
    this.iconColor,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.pxColors;
    final fg =
        iconColor ?? (enabled ? colors.ink : colors.inkMuted.withValues(alpha: 0.5));

    return Semantics(
      button: true,
      enabled: enabled,
      label: semanticLabel,
      excludeSemantics: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minWidth: PxLayout.minTapTarget,
          minHeight: PxLayout.minTapTarget,
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: PxRadius.brPill,
            onTap: enabled ? onPressed : null,
            child: Center(
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: backgroundColor ?? Colors.transparent,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  size: 20,
                  color: fg,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
