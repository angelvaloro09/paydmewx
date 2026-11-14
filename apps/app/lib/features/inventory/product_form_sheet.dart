import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/api/models.dart';
import '../../core/theme/motion.dart';
import '../../core/theme/theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/ui/px_ui.dart';
import '../auth/auth_controller.dart';
import 'inventory_controller.dart';
import 'widgets/inventory_icons.dart';
import 'widgets/inventory_sheet_container.dart';

Future<bool?> showProductFormSheet({
  required BuildContext context,
  Product? product,
}) {
  final isEditing = product != null;
  return showInventorySheet<bool>(
    context: context,
    title: isEditing ? 'Editar producto' : 'Agregar producto',
    builder: (sheetContext) => ProductFormSheet(product: product),
  );
}

class ProductFormSheet extends ConsumerStatefulWidget {
  final Product? product;

  const ProductFormSheet({
    super.key,
    this.product,
  });

  @override
  ConsumerState<ProductFormSheet> createState() => _ProductFormSheetState();
}

class _ProductFormSheetState extends ConsumerState<ProductFormSheet> {
  late final TextEditingController _nameController;
  late final TextEditingController _priceController;
  late final TextEditingController _stockController;
  late final TextEditingController _prepController;

  late bool _trackStock;
  bool _saving = false;
  bool _deleting = false;
  bool _switchFocused = false;

  String? _nameError;
  String? _priceError;
  String? _stockError;
  String? _prepError;
  String? _formError;

  bool get _isEditing => widget.product != null;

  @override
  void initState() {
    super.initState();
    final p = widget.product;
    _nameController = TextEditingController(text: p?.name ?? '');
    _priceController = TextEditingController(
      text: p != null ? formatCentsForInput(p.priceCents) : '',
    );
    _stockController = TextEditingController(
      text: p != null ? p.stock.toString() : '0',
    );
    _prepController = TextEditingController(
      text: p?.prepMinutes != null ? p!.prepMinutes.toString() : '',
    );
    _trackStock = p?.trackStock ?? true;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    _stockController.dispose();
    _prepController.dispose();
    super.dispose();
  }

  bool _validate({required bool showPrepMinutes}) {
    String? nameErr;
    String? priceErr;
    String? stockErr;
    String? prepErr;

    final name = _nameController.text.trim();
    if (name.isEmpty) {
      nameErr = 'Escribe el nombre del producto.';
    } else if (name.toLowerCase() == kQuickChargeProductName.toLowerCase()) {
      nameErr = 'Usa otro nombre; este está reservado para cobro rápido.';
    }

    final priceCents = parsePesosToCents(_priceController.text);
    if (priceCents == null) {
      priceErr = 'Ingresa un precio válido mayor a \$0.00 (máx. 2 decimales).';
    }

    if (_trackStock && !_isEditing) {
      final rawStock = _stockController.text.trim();
      final parsedStock = int.tryParse(rawStock);
      if (parsedStock == null || parsedStock < 0) {
        stockErr = 'Ingresa una cantidad entera mayor o igual a 0.';
      }
    }

    if (showPrepMinutes) {
      final rawPrep = _prepController.text.trim();
      if (rawPrep.isNotEmpty) {
        final parsedPrep = int.tryParse(rawPrep);
        if (parsedPrep == null || parsedPrep < 0) {
          prepErr = 'Ingresa minutos enteros válidos.';
        }
      }
    }

    setState(() {
      _nameError = nameErr;
      _priceError = priceErr;
      _stockError = stockErr;
      _prepError = prepErr;
      _formError = null;
    });

    return nameErr == null &&
        priceErr == null &&
        stockErr == null &&
        prepErr == null;
  }

  Future<void> _submit({required bool showPrepMinutes}) async {
    if (_saving || _deleting) return;
    if (!_validate(showPrepMinutes: showPrepMinutes)) return;

    final name = _nameController.text.trim();
    final priceCents = parsePesosToCents(_priceController.text)!;
    final stock = _trackStock && !_isEditing
        ? (int.tryParse(_stockController.text.trim()) ?? 0)
        : (widget.product?.stock ?? 0);

    int? prepMinutes;
    if (showPrepMinutes) {
      final rawPrep = _prepController.text.trim();
      if (rawPrep.isNotEmpty) {
        prepMinutes = int.tryParse(rawPrep);
      }
    } else {
      prepMinutes = widget.product?.prepMinutes;
    }

    setState(() {
      _saving = true;
      _formError = null;
    });

    final notifier = ref.read(inventoryControllerProvider.notifier);

    try {
      if (_isEditing) {
        await notifier.updateProduct(
          widget.product!,
          name: name,
          priceCents: priceCents,
          trackStock: _trackStock,
          prepMinutes: prepMinutes,
        );
        if (!mounted) return;
        PxToast.show(
          context,
          message: 'Producto actualizado.',
          type: PxToastType.success,
        );
      } else {
        await notifier.createProduct(
          name: name,
          priceCents: priceCents,
          trackStock: _trackStock,
          stock: _trackStock ? stock : 0,
          prepMinutes: prepMinutes,
        );
        if (!mounted) return;
        PxToast.show(
          context,
          message: 'Producto agregado.',
          type: PxToastType.success,
        );
      }
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _formError = e.message;
      });
      PxToast.show(context, message: e.message, type: PxToastType.error);
    } catch (_) {
      if (!mounted) return;
      const fallback = 'No pudimos guardar el producto. Intenta de nuevo.';
      setState(() {
        _saving = false;
        _formError = fallback;
      });
      PxToast.show(context, message: fallback, type: PxToastType.error);
    }
  }

  Future<void> _confirmAndDelete() async {
    final product = widget.product;
    if (product == null || _saving || _deleting) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final colors = dialogContext.pxColors;
        return AlertDialog(
          backgroundColor: colors.bg,
          shape: RoundedRectangleBorder(
            borderRadius: PxRadius.brXl,
            side: BorderSide(color: colors.line),
          ),
          title: Text(
            '¿Eliminar producto?',
            style: dialogContext.pxText.titleLarge?.copyWith(color: colors.ink),
          ),
          content: Text(
            'Se ocultará "${product.name}" de tu inventario y del punto de venta.',
            style: dialogContext.pxText.bodyMedium?.copyWith(
              color: colors.inkMuted,
            ),
          ),
          actionsPadding: const EdgeInsets.fromLTRB(
            PxSpacing.s24,
            0,
            PxSpacing.s24,
            PxSpacing.s24,
          ),
          actions: [
            Row(
              children: [
                Expanded(
                  child: PxButton(
                    label: 'Cancelar',
                    semanticLabel: 'Cancelar eliminación',
                    variant: PxButtonVariant.ghost,
                    onPressed: () => Navigator.of(dialogContext).pop(false),
                  ),
                ),
                const SizedBox(width: PxSpacing.s12),
                Expanded(
                  child: PxButton(
                    label: 'Eliminar',
                    semanticLabel: 'Confirmar eliminar ${product.name}',
                    variant: PxButtonVariant.secondary,
                    icon: PhosphorIconsBold.trash,
                    onPressed: () => Navigator.of(dialogContext).pop(true),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) return;

    setState(() {
      _deleting = true;
      _formError = null;
    });

    try {
      await ref
          .read(inventoryControllerProvider.notifier)
          .deleteProduct(product.id);
      if (!mounted) return;
      PxToast.show(
        context,
        message: 'Producto eliminado.',
        type: PxToastType.success,
      );
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _deleting = false;
        _formError = e.message;
      });
      PxToast.show(context, message: e.message, type: PxToastType.error);
    } catch (_) {
      if (!mounted) return;
      const fallback = 'No pudimos eliminar el producto. Intenta de nuevo.';
      setState(() {
        _deleting = false;
        _formError = fallback;
      });
      PxToast.show(context, message: fallback, type: PxToastType.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.pxColors;
    final authState = ref.watch(authProvider);
    final showPrepMinutes =
        authState.business?.prepType == PrepType.madeToOrder;
    final busy = _saving || _deleting;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PxField(
          label: 'Nombre del producto',
          hintText: 'Ej. Orden de tacos al pastor',
          controller: _nameController,
          enabled: !busy,
          textInputAction: TextInputAction.next,
          errorText: _nameError,
          onChanged: (_) {
            if (_nameError != null) {
              setState(() => _nameError = null);
            }
          },
        ),
        const SizedBox(height: PxSpacing.s16),
        PxField(
          label: 'Precio (MXN)',
          hintText: '0.00',
          helperText: 'En pesos, hasta 2 decimales (ej. 85 o 85.50).',
          controller: _priceController,
          enabled: !busy,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          textInputAction: TextInputAction.next,
          prefixIcon: Icon(
            PhosphorIconsBold.currencyDollar,
            size: 18,
            color: colors.inkMuted,
          ),
          errorText: _priceError,
          onChanged: (_) {
            if (_priceError != null) {
              setState(() => _priceError = null);
            }
          },
        ),
        const SizedBox(height: PxSpacing.s16),
        Semantics(
          toggled: _trackStock,
          label: 'Controlar existencias',
          child: FocusableActionDetector(
            enabled: !busy,
            onShowFocusHighlight: (v) => setState(() => _switchFocused = v),
            actions: <Type, Action<Intent>>{
              ActivateIntent: CallbackAction<ActivateIntent>(
                onInvoke: (_) {
                  if (!busy) {
                    setState(() => _trackStock = !_trackStock);
                  }
                  return null;
                },
              ),
            },
            child: AnimatedContainer(
              duration: PxMotion.duration(context, PxMotion.fast),
              curve: PxMotion.easeStd,
              constraints: const BoxConstraints(
                minHeight: PxLayout.minTapTarget,
              ),
              decoration: BoxDecoration(
                color: colors.surface2,
                borderRadius: PxRadius.brLg,
                border: Border.all(
                  color: _switchFocused ? colors.brand : colors.line,
                  width: _switchFocused ? 2 : 1,
                ),
              ),
              child: Material(
                type: MaterialType.transparency,
                child: InkWell(
                  borderRadius: PxRadius.brLg,
                  onTap: busy
                      ? null
                      : () => setState(() => _trackStock = !_trackStock),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: PxSpacing.s16,
                      vertical: PxSpacing.s12,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          PhosphorIconsRegular.package,
                          size: 20,
                          color: colors.ink,
                        ),
                        const SizedBox(width: PxSpacing.s12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Controlar existencias',
                                style: context.pxText.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: colors.ink,
                                ),
                              ),
                              Text(
                                'Descuenta inventario en cada venta y avisa cuando quede poco.',
                                style: context.pxText.bodySmall?.copyWith(
                                  color: colors.inkMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: PxSpacing.s8),
                        ExcludeSemantics(
                          child: Switch(
                            value: _trackStock,
                            activeThumbColor: colors.onBrand,
                            activeTrackColor: colors.brand,
                            onChanged: busy
                                ? null
                                : (v) => setState(() => _trackStock = v),
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
        if (_trackStock) ...[
          const SizedBox(height: PxSpacing.s16),
          PxField(
            label: _isEditing ? 'Existencias actuales' : 'Existencia inicial',
            hintText: '0',
            helperText: _isEditing
                ? 'Para cambiar la cantidad usa "Ajustar" desde la lista.'
                : 'Unidades disponibles para vender hoy.',
            controller: _stockController,
            enabled: !busy && !_isEditing,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.next,
            errorText: _stockError,
            onChanged: (_) {
              if (_stockError != null) {
                setState(() => _stockError = null);
              }
            },
          ),
        ],
        if (showPrepMinutes) ...[
          const SizedBox(height: PxSpacing.s16),
          PxField(
            label: 'Tiempo de preparación en minutos (opcional)',
            hintText: 'Ej. 15',
            helperText: 'Tiempo aproximado para tener listo este producto.',
            controller: _prepController,
            enabled: !busy,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            prefixIcon: Icon(
              PhosphorIconsRegular.timer,
              size: 18,
              color: colors.inkMuted,
            ),
            errorText: _prepError,
            onChanged: (_) {
              if (_prepError != null) {
                setState(() => _prepError = null);
              }
            },
          ),
        ],
        if (_formError != null) ...[
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
                    _formError!,
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
          label: _isEditing ? 'Guardar cambios' : 'Agregar producto',
          semanticLabel: _isEditing
              ? 'Guardar cambios del producto'
              : 'Agregar producto al inventario',
          fullWidth: true,
          loading: _saving,
          icon: PhosphorIconsBold.check,
          onPressed:
              busy ? null : () => _submit(showPrepMinutes: showPrepMinutes),
        ),
        if (_isEditing) ...[
          const SizedBox(height: PxSpacing.s12),
          PxButton(
            label: 'Eliminar producto',
            semanticLabel: 'Eliminar producto ${widget.product!.name}',
            variant: PxButtonVariant.secondary,
            fullWidth: true,
            loading: _deleting,
            icon: PhosphorIconsRegular.trash,
            onPressed: busy ? null : _confirmAndDelete,
          ),
        ],
      ],
    );
  }
}
